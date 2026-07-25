package com.splurter.splurter_android

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var shareChannel: MethodChannel? = null
    private var pendingSharedText: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val app = application as MainApplication
        app.clipboardHandler = ClipboardChannelHandler(this, flutterEngine)
        app.discoveryHandler = DiscoveryChannelHandler(this, flutterEngine)
        app.networkHandler = NetworkChannelHandler(this, flutterEngine)
        app.fileHandler = FileChannelHandler(this, flutterEngine)

        app.clipboardHandler.install()
        app.discoveryHandler.install()
        app.networkHandler.install()
        app.fileHandler.install()

        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "splurter/share")
        shareChannel?.setMethodCallHandler { call, result ->
            if (call.method == "consumeInitialText") {
                result.success(pendingSharedText)
                pendingSharedText = null
            } else result.notImplemented()
        }

        // Battery optimization — opens system dialog on first launch
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "splurter/battery_optimization")
            .setMethodCallHandler { call, result ->
                if (call.method == "requestBatteryExemption") {
                    BatteryOptimizationHelper.requestExemption(this)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }

        handleShareIntent(intent)
    }


    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleShareIntent(intent)
    }

    override fun onDestroy() {
        super.onDestroy()
        val app = application as? MainApplication ?: return
        app.clipboardHandler.dispose()
        app.discoveryHandler.dispose()
        app.networkHandler.dispose()
        app.fileHandler.dispose()
        shareChannel?.setMethodCallHandler(null)
        shareChannel = null
    }

    private fun handleShareIntent(intent: android.content.Intent?) {
        if (intent?.action != android.content.Intent.ACTION_SEND || intent.type != "text/plain") return
        val text = intent.getStringExtra(android.content.Intent.EXTRA_TEXT) ?: return
        if (shareChannel == null) pendingSharedText = text
        else shareChannel?.invokeMethod("onSharedText", text)
    }
}
