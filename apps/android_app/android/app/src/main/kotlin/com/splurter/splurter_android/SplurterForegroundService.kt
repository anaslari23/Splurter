package com.splurter.splurter_android

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import android.content.ClipboardManager
import android.content.ClipData
import android.content.ClipDescription

class SplurterForegroundService : Service() {

    private var flutterEngine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private val handler = Handler(Looper.getMainLooper())
    private var lastClipContent: String? = null
    private lateinit var clipboardManager: ClipboardManager
    private var bleAdvertiser: BleAdvertiser? = null
    private var localRelayServer: LocalRelayServer? = null

    companion object {
        const val NOTIFICATION_ID = 1001
        const val CHANNEL_ID = "splurter_foreground"
        const val CHANNEL_NAME = "Splurter Service"

        fun start(context: Context) {
            val intent = Intent(context, SplurterForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, SplurterForegroundService::class.java)
            context.stopService(intent)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        clipboardManager = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        setupFlutterEngine()
        startForegroundCompat(NOTIFICATION_ID, buildNotification("Initializing..."))

        // BLE peripheral — advertises Wi-Fi IP so Mac can connect directly over LAN
        bleAdvertiser = BleAdvertiser(this).also { it.start() }

        // Local TCP relay server — receives envelopes from Mac over LAN socket
        localRelayServer = LocalRelayServer { envelope ->
            val kind = envelope["kind"] ?: return@LocalRelayServer
            val content = envelope["text"] ?: return@LocalRelayServer
            if (kind == "clipboard") {
                val clip = android.content.ClipData.newPlainText("splurter", content)
                clipboardManager.setPrimaryClip(clip)
            }
        }.also { it.start() }
    }


    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForegroundCompat(NOTIFICATION_ID, buildNotification("Running"))
        setupClipboardListener()
        return START_STICKY
    }

    /** API-safe startForeground that avoids ForegroundServiceStartNotAllowedException. */
    private fun startForegroundCompat(id: Int, notification: Notification) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    id,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC or
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
                )
            } else {
                startForeground(id, notification)
            }
        } catch (e: Exception) {
            // Android 12+ ForegroundServiceStartNotAllowedException —
            // app was launched from background. Log and continue; the
            // service will be restarted by WorkManager keepalive.
            android.util.Log.w("SplurterFGS", "startForeground blocked: ${e.message}")
        }
    }

    override fun onBind(intent: Intent): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        bleAdvertiser?.stop()
        localRelayServer?.stop()
        flutterEngine?.destroy()
        flutterEngine = null
        channel = null
    }


    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps Splurter running in the background"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(status: String): Notification {
        val launchIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Splurter")
            .setContentText(status)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setSilent(true)
            .build()
    }

    fun updateStatus(text: String) {
        startForeground(NOTIFICATION_ID, buildNotification(text))
    }

    private fun setupFlutterEngine() {
        flutterEngine = FlutterEngine(this).also { engine ->
            // Load the Dart entrypoint
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault()
            )

            channel = MethodChannel(engine.dartExecutor.binaryMessenger, "splurter/foreground_service")
            channel?.setMethodCallHandler { call, result ->
                when (call.method) {
                    "updateNotification" -> {
                        val text = call.argument<String>("text") ?: "Running"
                        updateStatus(text)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun setupClipboardListener() {
        handler.postDelayed(object : Runnable {
            override fun run() {
                try {
                    val clip = clipboardManager.primaryClip
                    if (clip != null && clip.itemCount > 0) {
                        val item = clip.getItemAt(0)
                        val content = when {
                            item.text != null -> item.text.toString()
                            item.uri != null -> item.uri.toString()
                            else -> null
                        }
                        if (content != null && content != lastClipContent) {
                            lastClipContent = content
                            channel?.invokeMethod(
                                "onClipboardChanged",
                                mapOf("content" to content, "mimeType" to "text/plain")
                            )
                        }
                    }
                } catch (e: Exception) {
                    // clipboard may not be available
                }
                handler.postDelayed(this, 1500)
            }
        }, 1500)
    }
}