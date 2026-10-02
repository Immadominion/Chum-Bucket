package dev.cleva.chumbucket

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var blockStore: BlockStoreChannel? = null
    private var secureWindow: MethodChannel? = null

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
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        blockStore?.dispose()
        blockStore = null
        secureWindow?.setMethodCallHandler(null)
        secureWindow = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    companion object {
        private const val SECURE_WINDOW = "dev.cleva.chumbucket/secure_window"
    }
}
