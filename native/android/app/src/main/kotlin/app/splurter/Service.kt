package app.splurter

import android.app.Application
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.content.IntentFilter
import android.os.Handler
import android.os.Looper
import android.telephony.TelephonyManager

class App : Application() {
    override fun onCreate() {
        super.onCreate()
        link = Link(this).also { l ->
            l.onConnected = { NotifService.instance?.snapshot() }
            l.onBinary = { b -> if (b[0] == 1.toByte()) Files.onChunk(b) else if (b[0] == 3.toByte()) Audio.onFrame(b) }
            l.onMsg = { m ->
                when (m.optString("t")) {
                    "clip" -> Handler(Looper.getMainLooper()).post {
                        getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("Mac", m.getString("text")))
                    }
                    "dismiss" -> NotifService.instance?.cancelNotification(m.getString("id"))
                    "reply" -> NotifService.instance?.reply(m.getString("id"), m.getString("text"))
                    "tap", "swipe", "key", "text" -> ControlService.instance?.handle(m)
                    "audio_start" -> Audio.request(this, m.optString("src"))
                    "audio_stop" -> AudioService.instance?.stopSelf()
                    "mirror_start" -> Mirror.request(this)
                    "mirror_stop" -> MirrorService.instance?.stopSelf()
                    "file", "file_end" -> Files.onJson(this, m)
                    else -> Phone.handle(this, m)
                }
            }
        }
    }
    companion object { lateinit var link: Link }
}

/** Keeps the link alive (and reconnecting) with the UI closed. */
class LinkService : Service() {
    override fun onCreate() {
        super.onCreate()
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel("link", "Mac connection", NotificationManager.IMPORTANCE_MIN))
        val n = Notification.Builder(this, "link").setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setContentTitle("Splurter").setContentText("Connected to your Mac in the background").build()
        startForeground(1, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        registerReceiver(object : BroadcastReceiver() {
            override fun onReceive(c: Context, i: Intent) = Phone.report(c, i.getStringExtra(TelephonyManager.EXTRA_STATE),
                i.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER))
        }, IntentFilter(TelephonyManager.ACTION_PHONE_STATE_CHANGED), Context.RECEIVER_EXPORTED)
        App.link.start()
    }
    override fun onStartCommand(i: Intent?, f: Int, id: Int) = START_STICKY
    override fun onBind(i: Intent?) = null
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(c: Context, i: Intent) { c.startForegroundService(Intent(c, LinkService::class.java)) }
}
