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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "splurter/permissions")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkStatus" -> {
                        val notifEnabled = androidx.core.app.NotificationManagerCompat.getEnabledListenerPackages(this).contains(packageName)
                        val imm = getSystemService(android.content.Context.INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager
                        val enabledIMEs = imm.enabledInputMethodList
                        val imeEnabled = enabledIMEs.any { it.packageName == packageName }
                        val currentIme = android.provider.Settings.Secure.getString(contentResolver, android.provider.Settings.Secure.DEFAULT_INPUT_METHOD)
                        val imeSelected = currentIme?.contains(packageName) == true
                        val pm = getSystemService(android.content.Context.POWER_SERVICE) as android.os.PowerManager
                        val batteryExempt = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) pm.isIgnoringBatteryOptimizations(packageName) else true

                        result.success(mapOf(
                            "notificationAccess" to notifEnabled,
                            "imeEnabled" to imeEnabled,
                            "imeSelected" to imeSelected,
                            "batteryExempt" to batteryExempt
                        ))
                    }
                    "openNotificationListenerSettings" -> {
                        startActivity(android.content.Intent(android.provider.Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(null)
                    }
                    "openInputMethodSettings" -> {
                        startActivity(android.content.Intent(android.provider.Settings.ACTION_INPUT_METHOD_SETTINGS))
                        result.success(null)
                    }
                    "showInputMethodPicker" -> {
                        val imm = getSystemService(android.content.Context.INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager
                        imm.showInputMethodPicker()
                        result.success(null)
                    }
                    "requestBatteryExemption" -> {
                        BatteryOptimizationHelper.requestExemption(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
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
