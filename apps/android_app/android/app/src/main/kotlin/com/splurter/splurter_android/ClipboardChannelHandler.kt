package com.splurter.splurter_android

import android.app.Activity
import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class ClipboardChannelHandler(
    private val context: Context,
    private val flutterEngine: FlutterEngine,
) {
    private val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
    private val clipboardManager: ClipboardManager =
        context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    private val mainHandler = Handler(Looper.getMainLooper())
    private var lastSeenContent: String? = null

    private val clipListener = ClipboardManager.OnPrimaryClipChangedListener {
        mainHandler.post { emitChange() }
    }

    fun install() {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "read" -> readClipboard(result)
                "write" -> {
                    val args = call.arguments as? Map<*, *>
                    val content = args?.get("content") as? String
                    val mimeType = (args?.get("mimeType") as? String) ?: "text/plain"
                    writeClipboard(content, mimeType, result)
                }
                "startListening" -> {
                    clipboardManager.addPrimaryClipChangedListener(clipListener)
                    result.success(null)
                }
                "stopListening" -> {
                    clipboardManager.removePrimaryClipChangedListener(clipListener)
                    result.success(null)
                }
                "openImeSettings" -> {
                    try {
                        val intent = android.content.Intent(android.provider.Settings.ACTION_INPUT_METHOD_SETTINGS).apply {
                            addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        context.startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("IME_ERROR", e.message, null)
                    }
                }
                "isImeEnabled" -> {
                    try {
                        val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager
                        val enabled = imm.enabledInputMethodList.any { it.packageName == context.packageName }
                        result.success(enabled)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    fun dispose() {
        try { clipboardManager.removePrimaryClipChangedListener(clipListener) } catch (_: Exception) { }
        channel.setMethodCallHandler(null)
    }

    private fun readClipboard(result: MethodChannel.Result) {
        try {
            val clip = clipboardManager.primaryClip
            if (clip == null || clip.itemCount == 0) {
                result.success(mapOf("content" to "", "mimeType" to "text/plain"))
                return
            }
            val item = clip.getItemAt(0)
            val desc = clip.description
            val mimeType = if (desc != null && desc.mimeTypeCount > 0) desc.getMimeType(0) else "text/plain"
            val content = item.coerceToText(context).toString()
            result.success(mapOf("content" to content, "mimeType" to mimeType))
        } catch (e: SecurityException) {
            result.error("CLIPBOARD_DENIED", "Background clipboard access restricted", null)
        } catch (e: Exception) {
            result.error("CLIPBOARD_ERROR", e.message, null)
        }
    }

    private fun writeClipboard(content: String?, mimeType: String, result: MethodChannel.Result) {
        if (content == null) {
            result.error("INVALID_ARGS", "content is required", null)
            return
        }
        try {
            val clip = ClipData.newPlainText("splurter", content)
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.N_MR1) {
                val extras = clip.description.extras ?: android.os.PersistableBundle()
                extras.putBoolean("android.content.extra.IS_REMOTE_DEVICE", true)
                clip.description.extras = extras
            }
            clipboardManager.setPrimaryClip(clip)
            result.success(null)
        } catch (e: Exception) {
            result.error("CLIPBOARD_ERROR", e.message, null)
        }
    }

    private fun emitChange() {
        try {
            val clip = clipboardManager.primaryClip ?: return
            if (clip.itemCount == 0) return
            val item = clip.getItemAt(0)
            val desc = clip.description
            val mimeType = if (desc != null && desc.mimeTypeCount > 0) desc.getMimeType(0) else "text/plain"
            val content = item.coerceToText(context).toString()
            if (content == lastSeenContent) return
            lastSeenContent = content
            channel.invokeMethod("onClipboardChanged", mapOf("content" to content, "mimeType" to mimeType))
        } catch (_: Exception) { }
    }

    companion object {
        const val CHANNEL_NAME = "splurter/clipboard"
    }
}
