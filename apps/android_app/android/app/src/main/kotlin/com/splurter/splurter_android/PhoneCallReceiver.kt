package com.splurter.splurter_android

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.provider.ContactsContract
import android.telecom.TelecomManager
import android.telephony.TelephonyManager
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import io.flutter.plugin.common.MethodChannel

class PhoneCallReceiver : BroadcastReceiver() {

    companion object {
        private var lastState = TelephonyManager.EXTRA_STATE_IDLE
        private var currentCallId: String? = null
        var callChannel: MethodChannel? = null

        fun answerCall(context: Context) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val telecom = context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
                    telecom?.acceptRingingCall()
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        fun endCall(context: Context) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    val telecom = context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
                    telecom?.endCall()
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) return

        val stateStr = intent.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return
        if (stateStr == lastState) return
        lastState = stateStr

        val incomingNumber = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER) ?: "Unknown"

        val prefs = context.getSharedPreferences("splurter_prefs", Context.MODE_PRIVATE)
        val hostUid = prefs.getString("host_uid", null)

        when (stateStr) {
            TelephonyManager.EXTRA_STATE_RINGING -> {
                val callId = "call_${System.currentTimeMillis()}"
                currentCallId = callId
                val callerName = resolveContactName(context, incomingNumber)

                val payload = mapOf(
                    "action" to "ringing",
                    "callId" to callId,
                    "number" to incomingNumber,
                    "callerName" to callerName,
                    "timestamp" to System.currentTimeMillis()
                )

                callChannel?.invokeMethod("onCallEvent", payload)
                dispatchRelaySignal(hostUid, payload)
            }
            TelephonyManager.EXTRA_STATE_OFFHOOK -> {
                val callId = currentCallId ?: "call_${System.currentTimeMillis()}"
                val payload = mapOf(
                    "action" to "offhook",
                    "callId" to callId,
                    "timestamp" to System.currentTimeMillis()
                )
                callChannel?.invokeMethod("onCallEvent", payload)
                dispatchRelaySignal(hostUid, payload)
            }
            TelephonyManager.EXTRA_STATE_IDLE -> {
                val callId = currentCallId ?: ""
                val payload = mapOf(
                    "action" to "idle",
                    "callId" to callId,
                    "timestamp" to System.currentTimeMillis()
                )
                callChannel?.invokeMethod("onCallEvent", payload)
                dispatchRelaySignal(hostUid, payload)
                currentCallId = null
            }
        }
    }

    private fun resolveContactName(context: Context, number: String): String {
        if (number.isEmpty() || number == "Unknown") return "Unknown Caller"
        return try {
            val uri = Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(number))
            val cursor: Cursor? = context.contentResolver.query(
                uri,
                arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME),
                null,
                null,
                null
            )
            cursor?.use {
                if (it.moveToFirst()) {
                    val nameIdx = it.getColumnIndex(ContactsContract.PhoneLookup.DISPLAY_NAME)
                    if (nameIdx >= 0) it.getString(nameIdx) else number
                } else number
            } ?: number
        } catch (_: Exception) {
            number
        }
    }

    private fun dispatchRelaySignal(hostUid: String?, payload: Map<String, Any?>) {
        if (hostUid.isNullOrEmpty()) return
        try {
            val db = FirebaseFirestore.getInstance()
            db.collection("users")
                .document(hostUid)
                .collection("signals")
                .add(
                    mapOf(
                        "version" to 1,
                        "senderId" to "android",
                        "recipientId" to "broadcast",
                        "kind" to "call",
                        "payload" to payload,
                        "sentAt" to FieldValue.serverTimestamp()
                    )
                )
        } catch (_: Exception) {}
    }
}
