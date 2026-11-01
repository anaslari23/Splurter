package app.splurter

import android.content.Context
import android.net.Uri
import android.provider.ContactsContract.PhoneLookup
import android.telecom.TelecomManager
import android.telephony.SmsManager
import org.json.JSONObject

/** Call state out, call/SMS commands in. All permission-gated calls fail soft (SecurityException is swallowed). */
object Phone {
    private var lastNumber: String? = null
    @Volatile var state = "idle"

    fun report(ctx: Context, state: String?, number: String?) {
        if (number != null) lastNumber = number
        val st = state?.lowercase() ?: return
        this.state = st
        App.link.send(JSONObject().put("t", "call").put("state", st).put("number", lastNumber ?: "")
            .put("name", lastNumber?.let { name(ctx, it) } ?: ""))
        if (st == "idle") lastNumber = null
    }

    /** On every (re)connect: tell the Mac the real call state, since a message sent while disconnected is lost. */
    @Suppress("DEPRECATION")
    fun resync(ctx: Context) {
        val st = runCatching { ctx.getSystemService(android.telephony.TelephonyManager::class.java).callState }.getOrNull() ?: return
        state = when (st) { android.telephony.TelephonyManager.CALL_STATE_RINGING -> "ringing"; android.telephony.TelephonyManager.CALL_STATE_OFFHOOK -> "offhook"; else -> "idle" }
        App.link.send(JSONObject().put("t", "call").put("state", state).put("number", lastNumber ?: "").put("name", lastNumber?.let { name(ctx, it) } ?: ""))
        if (state == "idle") lastNumber = null
    }

    fun handle(ctx: Context, m: JSONObject) = runCatching {
        val tm = ctx.getSystemService(TelecomManager::class.java)
        when (m.optString("t")) {
            "call_answer" -> tm.acceptRingingCall()
            "call_end" -> tm.endCall()
            "dial" -> tm.placeCall(Uri.fromParts("tel", m.getString("number"), null), null)
            "sms_send" -> {
                val sms = ctx.getSystemService(SmsManager::class.java)
                sms.sendMultipartTextMessage(m.getString("to"), null, sms.divideMessage(m.getString("text")), null, null)
                App.link.send(JSONObject().put("t", "sms_sent").put("to", m.getString("to")))
            }
        }
    }

    private fun name(ctx: Context, number: String) = runCatching {
        ctx.contentResolver.query(Uri.withAppendedPath(PhoneLookup.CONTENT_FILTER_URI, Uri.encode(number)),
            arrayOf(PhoneLookup.DISPLAY_NAME), null, null, null)?.use { if (it.moveToFirst()) it.getString(0) else null }
    }.getOrNull()
}
