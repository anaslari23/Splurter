package app.splurter

import android.app.Notification
import android.graphics.Bitmap
import android.graphics.Canvas
import android.util.Base64
import java.io.ByteArrayOutputStream
import android.app.RemoteInput
import android.content.Intent
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONObject

/** Mirrors phone notifications to the Mac and executes dismiss/reply coming back. */
class NotifService : NotificationListenerService() {
    override fun onListenerConnected() { instance = this; snapshot(); Media.start(android.content.ComponentName(this, NotifService::class.java)) }
    override fun onListenerDisconnected() { if (instance === this) instance = null }
    override fun onNotificationPosted(sbn: StatusBarNotification) = push(sbn, sync = false)
    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        App.link.send(JSONObject().put("t", "notif_gone").put("id", sbn.key))
    }

    /** Re-sends everything currently showing (quietly) — used on connect so the Mac catches up. */
    fun snapshot() { sentIcons.clear(); activeNotifications.forEach { push(it, sync = true) } }

    private val sentIcons = HashSet<String>() // per connection: the Mac caches icons by package

    private fun sendIcon(pkg: String) {
        if (!sentIcons.add(pkg)) return
        runCatching {
            val d = packageManager.getApplicationIcon(pkg)
            val bmp = Bitmap.createBitmap(128, 128, Bitmap.Config.ARGB_8888)
            d.setBounds(0, 0, 128, 128); d.draw(Canvas(bmp))
            val png = ByteArrayOutputStream().also { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
            App.link.send(JSONObject().put("t", "app_icon").put("pkg", pkg).put("png", Base64.encodeToString(png, Base64.NO_WRAP)))
        }
    }

    fun reply(key: String, text: String) {
        val sbn = activeNotifications.firstOrNull { it.key == key } ?: return
        val act = sbn.notification.actions?.firstOrNull { it.remoteInputs?.isNotEmpty() == true } ?: return
        val i = Intent()
        RemoteInput.addResultsToIntent(act.remoteInputs, i, Bundle().apply { putCharSequence(act.remoteInputs[0].resultKey, text) })
        act.actionIntent.send(this, 0, i)
    }

    private fun push(sbn: StatusBarNotification, sync: Boolean) {
        val n = sbn.notification
        if (sbn.packageName == packageName || sbn.isOngoing || n.flags and Notification.FLAG_GROUP_SUMMARY != 0 ||
            n.category == Notification.CATEGORY_CALL) return // calls are handled natively, see Phone.kt
        val e = n.extras
        val title = e.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val text = (e.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: e.getCharSequence(Notification.EXTRA_TEXT))?.toString().orEmpty()
        if (title.isEmpty() && text.isEmpty()) return
        val app = runCatching { packageManager.getApplicationLabel(packageManager.getApplicationInfo(sbn.packageName, 0)).toString() }.getOrDefault(sbn.packageName)
        sendIcon(sbn.packageName) // before the notification itself: the link keeps order, so the Mac has it when the banner is built
        App.link.send(JSONObject().put("t", "notif").put("id", sbn.key).put("pkg", sbn.packageName).put("app", app).put("title", title).put("text", text)
            .put("canReply", n.actions?.any { it.remoteInputs?.isNotEmpty() == true } == true).put("sync", sync))
    }

    companion object { @Volatile var instance: NotifService? = null }
}
