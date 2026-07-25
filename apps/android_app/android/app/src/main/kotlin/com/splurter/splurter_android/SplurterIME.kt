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

        val uid = auth.currentUser?.uid ?: return

        // Send clipboard to Mac via Firestore signal
        db.collection("users")
            .document(uid)
            .collection("signals")
            .add(
                mapOf(
                    "version" to 1,
                    "senderId" to "android-device-id",
                    "recipientId" to "mac-device-id",
                    "kind" to "clipboard",
                    "payload" to mapOf("text" to content),
                    "sentAt" to FieldValue.serverTimestamp(),
                )
            )
    }
}
