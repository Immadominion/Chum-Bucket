package dev.cleva.chumbucket

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var blockStore: BlockStoreChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Session + on-phone wallet continuity across reinstall (Google Block Store).
        blockStore = BlockStoreChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        blockStore?.dispose()
        blockStore = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
