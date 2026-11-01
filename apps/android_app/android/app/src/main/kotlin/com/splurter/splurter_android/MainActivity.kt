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
                    "getDeviceAesthetics" -> {
                        var batteryLevel = 88
                        var isCharging = false
                        try {
                            val bm = getSystemService(android.content.Context.BATTERY_SERVICE) as android.os.BatteryManager
                            batteryLevel = bm.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY)
                            val ifilter = android.content.IntentFilter(android.content.Intent.ACTION_BATTERY_CHANGED)
                            val batteryStatus = registerReceiver(null, ifilter)
                            val status = batteryStatus?.getIntExtra(android.os.BatteryManager.EXTRA_STATUS, -1) ?: -1
                            isCharging = status == android.os.BatteryManager.BATTERY_STATUS_CHARGING || status == android.os.BatteryManager.BATTERY_STATUS_FULL
                        } catch (e: Exception) {}

                        var carrierName = "5G"
                        try {
                            val tm = getSystemService(android.content.Context.TELEPHONY_SERVICE) as android.telephony.TelephonyManager
                            carrierName = tm.networkOperatorName.takeIf { !it.isNullOrEmpty() } ?: "5G"
                        } catch (e: Exception) {}

                        var wallpaperTheme = "aurora"
                        try {
                            val wm = android.app.WallpaperManager.getInstance(this)
                            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O_MR1) {
                                val colors = wm.getWallpaperColors(android.app.WallpaperManager.FLAG_SYSTEM)
                                val primary = colors?.primaryColor
                                if (primary != null) {
                                    val r = android.graphics.Color.red(primary.toArgb())
                                    val g = android.graphics.Color.green(primary.toArgb())
                                    val b = android.graphics.Color.blue(primary.toArgb())
                                    if (g > r && g > b) wallpaperTheme = "emerald"
                                    else if (r > b && r > g) wallpaperTheme = "sunset"
                                    else if (r < 60 && g < 60 && b < 80) wallpaperTheme = "dark"
                                }
                            }
                        } catch (e: Exception) {}

                        result.success(mapOf(
                            "batteryLevel" to batteryLevel,
                            "isCharging" to isCharging,
                            "carrier" to carrierName,
                            "wallpaperTheme" to wallpaperTheme,
                            "deviceName" to (android.os.Build.MODEL ?: "Android Phone")
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "splurter/foreground_service")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        SplurterForegroundService.start(this)
                        result.success(null)
                    }
                    "stop" -> {
                        SplurterForegroundService.stop(this)
                        result.success(null)
                    }
                    "setHostUid" -> {
                        val uid = call.argument<String>("uid")
                        getSharedPreferences("splurter_prefs", android.content.Context.MODE_PRIVATE)
                            .edit()
                            .putString("host_uid", uid)
                            .apply()
                        result.success(null)
                    }
                    "getHostUid" -> {
                        val uid = getSharedPreferences("splurter_prefs", android.content.Context.MODE_PRIVATE)
                            .getString("host_uid", null)
                        result.success(uid)
                    }
                    "updateNotification" -> {
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "splurter/notifications")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPermission" -> {
                        startActivity(android.content.Intent(android.provider.Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(null)
                    }
                    "dismiss" -> {
                        val id = call.argument<String>("id")
                        if (id != null) {
                            NotificationListener.instance?.dismiss(id)
                        }
                        result.success(null)
                    }
                    "reply" -> {
                        val id = call.argument<String>("id")
                        val text = call.argument<String>("text")
                        if (id != null && text != null) {
                            val ok = NotificationListener.instance?.reply(id, text) ?: false
                            result.success(ok)
                        } else {
                            result.success(false)
                        }
                    }
                    "syncActiveNotifications" -> {
                        NotificationListener.instance?.syncActiveNotifications()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        val callChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "splurter/calls")
        PhoneCallReceiver.callChannel = callChannel
        callChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "answerCall" -> {
                    PhoneCallReceiver.answerCall(this)
                    result.success(null)
                }
                "endCall" -> {
                    PhoneCallReceiver.endCall(this)
                    result.success(null)
                }
                else -> result.notImplemented()
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
        PhoneCallReceiver.callChannel = null
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
