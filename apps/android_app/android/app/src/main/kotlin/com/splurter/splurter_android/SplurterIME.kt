package com.splurter.splurter_android

import android.content.ClipboardManager
import android.content.Context
import android.inputmethodservice.InputMethodService
import android.view.View
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore

/**
 * SplurterIME — invisible background Input Method Service.
 *
 * Android API 29+ blocks clipboard reads from background apps.
 * However, a registered InputMethodService runs as a privileged system
 * service, allowing ClipboardManager.OnPrimaryClipChangedListener to
 * fire without the SecurityException restriction.
 *
 * This IME never shows any UI (returns null from onCreateInputView).
 * The user enables it once in Settings → Keyboard → Manage keyboards.
 */
class SplurterIME : InputMethodService() {

    private lateinit var clipboardManager: ClipboardManager
    private val db = FirebaseFirestore.getInstance()
    private val auth = FirebaseAuth.getInstance()
    private var lastContent: String? = null

    private val clipListener = ClipboardManager.OnPrimaryClipChangedListener {
        onClipboardChanged()
    }

    override fun onCreate() {
        super.onCreate()
        clipboardManager = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboardManager.addPrimaryClipChangedListener(clipListener)
    }

    override fun onCreateInputView(): View? {
        // Return null — this IME has no keyboard UI, it runs invisibly
        return null
    }

    override fun onDestroy() {
        super.onDestroy()
        clipboardManager.removePrimaryClipChangedListener(clipListener)
    }

    private fun onClipboardChanged() {
        val clip = clipboardManager.primaryClip ?: return
        if (clip.itemCount == 0) return
        val content = clip.getItemAt(0).coerceToText(this).toString()
        if (content.isBlank() || content == lastContent) return
        lastContent = content

        // 1. Local broadcast to foreground service (for instant LAN TCP delivery if active)
        val localIntent = android.content.Intent("com.splurter.ACTION_CLIPBOARD_CHANGED").apply {
            putExtra("content", content)
            setPackage(packageName)
        }
        sendBroadcast(localIntent)

        // 2. Fallback / Cloud signal via Firestore
        val prefs = getSharedPreferences("splurter_prefs", Context.MODE_PRIVATE)
        val uid = prefs.getString("host_uid", null) ?: auth.currentUser?.uid ?: return
        db.collection("users")
            .document(uid)
            .collection("devices")
            .whereNotEqualTo("platform", "android")
            .get()
            .addOnSuccessListener { query ->
                for (doc in query.documents) {
                    val recipientId = doc.id
                    db.collection("users")
                        .document(uid)
                        .collection("signals")
                        .add(
                            mapOf(
                                "version" to 1,
                                "senderId" to "android",
                                "recipientId" to recipientId,
                                "kind" to "clipboard",
                                "payload" to mapOf("text" to content),
                                "sentAt" to FieldValue.serverTimestamp(),
                            )
                        )
                }
            }
    }
}
