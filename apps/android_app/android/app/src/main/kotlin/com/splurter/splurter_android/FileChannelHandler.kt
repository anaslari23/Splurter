package com.splurter.splurter_android

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class FileChannelHandler(
    private val context: Context,
    private val flutterEngine: FlutterEngine,
) {
    private val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
    private var pendingResult: Result? = null

    fun setActivityProvider(provider: () -> Activity?) {
        activityProvider = provider
    }

    fun install() {
        channel.setMethodCallHandler { call, result ->
            val args = call.arguments as? Map<*, *>
            when (call.method) {
                "pickFile" -> pickFile(result)
                "saveFileDialog" -> saveFile(args, result)
                else -> result.notImplemented()
            }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        pendingResult?.success(null)
        pendingResult = null
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        val result = pendingResult ?: return false
        pendingResult = null

        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(null)
            return true
        }

        val uri = data.data ?: run {
            result.success(null)
            return true
        }

        when (requestCode) {
            REQUEST_PICK_FILE -> result.success(readMetadata(uri))
            REQUEST_SAVE_FILE -> result.success(uri.toString())
            else -> result.notImplemented()
        }
        return true
    }

    private fun pickFile(result: Result) {
        if (pendingResult != null) {
            result.error("BUSY", "File operation in progress", null)
            return
        }
        val activity = activityProvider?.invoke() ?: run {
            result.error("NO_ACTIVITY", "No foreground activity", null)
            return
        }
        pendingResult = result
        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
            type = "*/*"
            addCategory(Intent.CATEGORY_OPENABLE)
        }
        activity.startActivityForResult(
            Intent.createChooser(intent, "Select a file"),
            REQUEST_PICK_FILE,
        )
    }

    private fun saveFile(args: Map<*, *>?, result: Result) {
        if (pendingResult != null) {
            result.error("BUSY", "File operation in progress", null)
            return
        }
        val activity = activityProvider?.invoke() ?: run {
            result.error("NO_ACTIVITY", "No foreground activity", null)
            return
        }
        pendingResult = result
        val suggestedName = (args?.get("suggestedName") as? String) ?: "untitled"
        val mimeType = (args?.get("mimeType") as? String) ?: "*/*"
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            this.type = mimeType
            putExtra(Intent.EXTRA_TITLE, suggestedName)
        }
        activity.startActivityForResult(intent, REQUEST_SAVE_FILE)
    }

    private fun readMetadata(uri: Uri): Map<String, Any> {
        var name = uri.lastPathSegment ?: "unknown"
        var size: Long = 0
        var mimeType = "application/octet-stream"

        context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameIdx >= 0) cursor.getString(nameIdx)?.let { name = it }
                val sizeIdx = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (sizeIdx >= 0) size = cursor.getLong(sizeIdx)
            }
        }
        context.contentResolver.getType(uri)?.let { mimeType = it }

        return mapOf(
            "path" to uri.toString(),
            "name" to name,
            "size" to size,
            "mimeType" to mimeType,
        )
    }

    companion object {
        const val CHANNEL_NAME = "splurter/file"
        private var activityProvider: (() -> Activity?)? = null

        fun setCurrentActivityProvider(provider: (() -> Activity?)?) {
            activityProvider = provider
        }

        private const val REQUEST_PICK_FILE = 1001
        private const val REQUEST_SAVE_FILE = 1002
    }
}
