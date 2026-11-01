package com.splurter.splurter_android

import android.app.Notification
import android.app.RemoteInput
import android.content.Intent
import android.os.Bundle
import android.os.IBinder
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentHashMap

class NotificationListener : NotificationListenerService() {

    companion object {
        const val CHANNEL_NAME = "splurter/notifications"
        var instance: NotificationListener? = null
        val replyActions = ConcurrentHashMap<String, Notification.Action>()
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
        instance = this
        syncActiveNotifications()
    }

    fun syncActiveNotifications() {
        try {
            activeNotifications?.forEach { sbn ->
                onNotificationPosted(sbn)
            }
        } catch (e: Exception) {
            // Ignore
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        sbn?.let {
            val packageName = it.packageName ?: return@let

            // Filter out Splurter's own foreground service & internal notifications
            if (packageName == "com.splurter.splurter" || packageName == applicationContext.packageName) {
                return@let
            }

            // Filter out Android System UI and background system services (like Adaptive charging, USB charging, etc.)
            if (packageName == "com.android.systemui" || packageName == "android" || packageName == "com.android.settings" || packageName.startsWith("com.android.providers.")) {
                return@let
            }

            // Filter out ongoing background system notifications (e.g. download progress bars)
            if ((it.notification.flags and Notification.FLAG_ONGOING_EVENT) != 0) {
                return@let
            }

            val extras = it.notification.extras
            val title = extras.getString(Notification.EXTRA_TITLE) ?: ""
            val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""

            // Ignore empty notifications
            if (title.isEmpty() && text.isEmpty()) {
                return@let
            }

            // Resolve human-readable application label (e.g., "WhatsApp", "Slack", "Messages")
            val appName = try {
                val pm = applicationContext.packageManager
                val ai = pm.getApplicationInfo(packageName, 0)
                pm.getApplicationLabel(ai).toString()
            } catch (e: Exception) {
                packageName.substringAfterLast('.').replaceFirstChar { char -> char.uppercase() }
            }

            val key = it.key ?: it.id.toString()

            // Detect if this notification has a direct reply action (e.g. WhatsApp, Messages, Telegram, Slack)
            var canReply = false
            val actions = it.notification.actions
            if (actions != null) {
                for (action in actions) {
                    val remoteInputs = action.remoteInputs
                    if (remoteInputs != null && remoteInputs.isNotEmpty()) {
                        replyActions[key] = action
                        canReply = true
                        break
                    }
                }
            }

            val payload = mapOf(
                "action" to "post",
                "id" to key,
                "packageName" to packageName,
                "appName" to appName,
                "title" to title,
                "text" to text,
                "canReply" to canReply,
                "timestamp" to System.currentTimeMillis()
            )

            channel?.invokeMethod("onNotificationPosted", payload)

            // Send notification signal directly to Firestore so macOS receives it even when Flutter is in background
            try {
                val prefs = getSharedPreferences("splurter_prefs", android.content.Context.MODE_PRIVATE)
                val hostUid = prefs.getString("host_uid", null)
                if (hostUid != null) {
                    val db = com.google.firebase.firestore.FirebaseFirestore.getInstance()
                    db.collection("users")
                        .document(hostUid)
                        .collection("signals")
                        .add(
                            mapOf(
                                "version" to 1,
                                "senderId" to "android",
                                "recipientId" to "broadcast",
                                "kind" to "notification",
                                "payload" to payload,
                                "sentAt" to com.google.firebase.firestore.FieldValue.serverTimestamp()
                            )
                        )
                }

                val isMedia = packageName.contains("music", true) ||
                        packageName.contains("spotify", true) ||
                        packageName.contains("audio", true) ||
                        packageName.contains("player", true) ||
                        packageName.contains("podcast", true) ||
                        packageName.contains("soundcloud", true) ||
                        extras.containsKey(Notification.EXTRA_MEDIA_SESSION)

                if (isMedia && title.isNotEmpty() && hostUid != null) {
                    val db = com.google.firebase.firestore.FirebaseFirestore.getInstance()
                    db.collection("users")
                        .document(hostUid)
                        .collection("devices")
                        .document("android-device-id")
                        .set(mapOf(
                            "nowPlayingTitle" to title,
                            "nowPlayingArtist" to text
                        ), com.google.firebase.firestore.SetOptions.merge())
                }
            } catch (e: Exception) {
                // Ignore Firestore write failures if offline
            }
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        super.onNotificationRemoved(sbn)
        sbn?.let {
            val key = it.key ?: it.id.toString()
            replyActions.remove(key)

            val payload = mapOf(
                "action" to "remove",
                "id" to key,
                "packageName" to it.packageName
            )
            channel?.invokeMethod("onNotificationRemoved", payload)

            try {
                val isMedia = it.packageName.contains("music", true) ||
                        it.packageName.contains("spotify", true) ||
                        it.packageName.contains("audio", true) ||
                        it.packageName.contains("player", true) ||
                        it.packageName.contains("podcast", true) ||
                        it.packageName.contains("soundcloud", true)
                if (isMedia) {
                    val prefs = getSharedPreferences("splurter_prefs", android.content.Context.MODE_PRIVATE)
                    val hostUid = prefs.getString("host_uid", null)
                    if (hostUid != null) {
                        val db = com.google.firebase.firestore.FirebaseFirestore.getInstance()
                        db.collection("users")
                            .document(hostUid)
                            .collection("devices")
                            .document("android-device-id")
                            .set(mapOf(
                                "nowPlayingTitle" to null,
                                "nowPlayingArtist" to null
                            ), com.google.firebase.firestore.SetOptions.merge())
                    }
                }
            } catch (e: Exception) {}
        }
    }

    fun reply(key: String, text: String): Boolean {
        val action = replyActions[key] ?: return false
        val remoteInputs = action.remoteInputs ?: return false
        val intent = Intent()
        val bundle = Bundle()
        for (remoteInput in remoteInputs) {
            bundle.putCharSequence(remoteInput.resultKey, text)
        }
        RemoteInput.addResultsToIntent(remoteInputs, intent, bundle)
        return try {
            action.actionIntent.send(this, 0, intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    fun dismiss(key: String): Boolean {
        return try {
            cancelNotification(key)
            true
        } catch (e: Exception) {
            false
        }
    }

    override fun onDestroy() {
        if (instance == this) instance = null
        replyActions.clear()
        super.onDestroy()
        flutterEngine?.destroy()
        flutterEngine = null
        channel = null
    }

    override fun onBind(intent: Intent?): IBinder? {
        return super.onBind(intent)
    }
}