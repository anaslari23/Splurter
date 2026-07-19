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

/**
 * Handles the "splurter/clipboard" MethodChannel.
 */
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
                    val content = call.argument<String>("content")
                    val mimeType = call.argument<String>("mimeType") ?: "text/plain"
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
