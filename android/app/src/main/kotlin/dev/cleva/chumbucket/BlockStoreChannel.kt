package dev.cleva.chumbucket

import android.content.Context
import com.google.android.gms.auth.blockstore.Blockstore
import com.google.android.gms.auth.blockstore.DeleteBytesRequest
import com.google.android.gms.auth.blockstore.RetrieveBytesRequest
import com.google.android.gms.auth.blockstore.StoreBytesData
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Google's Block Store, for the Dart side's `MethodChannelBlockStore`
 * (lib/features/authentication/continuity/block_store.dart).
 *
 * What it is for: keeping a person signed in, and their on-phone wallet key,
 * across an uninstall/reinstall or a move to a new phone. Block Store keeps up
 * to 16 small entries per app in Google Play services; they survive an
 * uninstall when the person has Backup on, and are backed up to their Google
 * account end-to-end encrypted when the device has a screen lock. The Dart
 * side decides what to store and whether to ask for cloud backup (only when
 * [isEndToEndEncryptionAvailable] says yes).
 *
 * Four methods, each with fixed result shapes:
 *   availability            -> {"available": Boolean, "e2ee": Boolean}
 *   retrieve {key}          -> ByteArray or null
 *   store {key, bytes, backupToCloud} -> null
 *   delete {key}            -> null
 *
 * Errors carry a fixed code ("unavailable", "bad_args", "failed") and never
 * the exception's message or the bytes: an entry can hold a credential.
 */
class BlockStoreChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, NAME)

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    private fun playServicesReady(): Boolean =
        try {
            GoogleApiAvailability.getInstance()
                .isGooglePlayServicesAvailable(context) == ConnectionResult.SUCCESS
        } catch (_: Exception) {
            false
        }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (!playServicesReady()) {
            // No Play services (some ROMs, emulators without Google APIs):
            // the Dart side degrades to "not backed up".
            if (call.method == "availability") {
                result.success(mapOf("available" to false, "e2ee" to false))
            } else {
                result.error("unavailable", null, null)
            }
            return
        }
        val client =
            try {
                Blockstore.getClient(context)
            } catch (_: Exception) {
                result.error("unavailable", null, null)
                return
            }
        when (call.method) {
            "availability" ->
                client.isEndToEndEncryptionAvailable
                    .addOnSuccessListener { e2ee ->
                        result.success(mapOf("available" to true, "e2ee" to (e2ee == true)))
                    }
                    .addOnFailureListener {
                        result.success(mapOf("available" to false, "e2ee" to false))
                    }

            "retrieve" -> {
                val key = keyOf(call) ?: return result.error("bad_args", null, null)
                val request = RetrieveBytesRequest.Builder().setKeys(listOf(key)).build()
                client.retrieveBytes(request)
                    .addOnSuccessListener { response ->
                        result.success(response.blockstoreDataMap[key]?.bytes)
                    }
                    .addOnFailureListener { result.error("failed", null, null) }
            }

            "store" -> {
                val key = keyOf(call) ?: return result.error("bad_args", null, null)
                val bytes = call.argument<ByteArray>("bytes")
                val backupToCloud = call.argument<Boolean>("backupToCloud") == true
                if (bytes == null || bytes.isEmpty() || bytes.size > MAX_ENTRY_BYTES) {
                    return result.error("bad_args", null, null)
                }
                val data =
                    StoreBytesData.Builder()
                        .setKey(key)
                        .setBytes(bytes)
                        .setShouldBackupToCloud(backupToCloud)
                        .build()
                client.storeBytes(data)
                    .addOnSuccessListener { result.success(null) }
                    .addOnFailureListener { result.error("failed", null, null) }
            }

            "delete" -> {
                val key = keyOf(call) ?: return result.error("bad_args", null, null)
                val request = DeleteBytesRequest.Builder().setKeys(listOf(key)).build()
                client.deleteBytes(request)
                    .addOnSuccessListener { result.success(null) }
                    .addOnFailureListener { result.error("failed", null, null) }
            }

            else -> result.notImplemented()
        }
    }

    private fun keyOf(call: MethodCall): String? =
        call.argument<String>("key")?.takeIf { KEY.matches(it) }

    companion object {
        const val NAME = "dev.cleva.chumbucket/block_store"

        /** Block Store's own per-entry ceiling. */
        private const val MAX_ENTRY_BYTES = 4 * 1024

        /** Only this app's own fixed key names, never arbitrary input. */
        private val KEY = Regex("^chumbucket\\.[a-z0-9_.]{1,64}$")
    }
}
