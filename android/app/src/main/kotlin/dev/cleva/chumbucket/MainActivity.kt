package dev.cleva.chumbucket

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var blockStore: BlockStoreChannel? = null
    private var secureWindow: MethodChannel? = null
    private var notifications: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Session + on-phone wallet continuity across reinstall (Google Block Store).
        blockStore = BlockStoreChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        // While a recovery phrase or private key is on screen: no screenshots,
        // no screen recording, a blank recents thumbnail (FLAG_SECURE).
        secureWindow =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURE_WINDOW).also {
                it.setMethodCallHandler { call, result ->
                    if (call.method != "set") return@setMethodCallHandler result.notImplemented()
                    if (call.argument<Boolean>("secure") == true) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                }
            }
        // Settings → Notifications, only when the person taps it after
        // refusing twice (the app never opens settings on its own).
        notifications =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATIONS).also {
                it.setMethodCallHandler { call, result ->
                    if (call.method != "openSettings") return@setMethodCallHandler result.notImplemented()
                    result.success(openNotificationSettings())
                }
            }
    }

    private fun openNotificationSettings(): Boolean {
        val intents =
            listOf(
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName),
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                    .setData(Uri.fromParts("package", packageName, null)),
            )
        for (intent in intents) {
            try {
                startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return true
            } catch (_: Exception) {
                // Try the next one.
            }
        }
        return false
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        blockStore?.dispose()
        blockStore = null
        secureWindow?.setMethodCallHandler(null)
        secureWindow = null
        notifications?.setMethodCallHandler(null)
        notifications = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    companion object {
        private const val SECURE_WINDOW = "dev.cleva.chumbucket/secure_window"
        private const val NOTIFICATIONS = "dev.cleva.chumbucket/notifications"
    }
}
