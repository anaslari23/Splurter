package com.splurter.splurter_android

import android.app.Notification
import android.os.IBinder
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class NotificationListener : NotificationListenerService() {

    companion object {
        const val CHANNEL_NAME = "splurter/notifications"
    }

    private var flutterEngine: FlutterEngine? = null
    private var channel: MethodChannel? = null

    override fun onCreate() {
        super.onCreate()
        setupFlutterEngine()
    }

    private fun setupFlutterEngine() {
        flutterEngine = FlutterEngine(this).also { engine ->
            engine.dartExecutor.executeDartEntrypoint(
                io.flutter.embedding.engine.dart.DartExecutor.DartEntrypoint.createDefault()
            )
            channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        }
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        // Listen for active notifications so we can dispatch them to Dart
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        sbn?.let {
            val extras = it.notification.extras
            val title = extras.getString(Notification.EXTRA_TITLE) ?: ""
            val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
            val packageName = it.packageName

            val payload = mapOf(
                "id" to it.id.toString() + "-" + System.nanoTime().toString(),
                "packageName" to packageName,
                "title" to title,
                "text" to text,
                "timestamp" to System.currentTimeMillis()
            )

            channel?.invokeMethod("onNotificationPosted", payload)
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        super.onNotificationRemoved(sbn)
        sbn?.let {
            val payload = mapOf(
                "id" to it.id.toString() + "-" + System.nanoTime().toString(),
                "packageName" to it.packageName
            )
            channel?.invokeMethod("onNotificationRemoved", payload)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        flutterEngine?.destroy()
        flutterEngine = null
        channel = null
    }

    override fun onBind(intent: Intent?): IBinder? {
        return super.onBind(intent)
    }
}