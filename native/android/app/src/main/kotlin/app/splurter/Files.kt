package app.splurter

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import org.json.JSONObject
import java.io.OutputStream
import java.nio.ByteBuffer
import kotlin.random.Random

/** File transfer: chunks are frame type 1 = [1][id:4 BE][data]; "file"/"file_end" JSON frames bracket them. */
object Files {
    private class In(val out: OutputStream, val uri: Uri, val name: String)
    private val incoming = HashMap<Int, In>()

    fun onJson(ctx: Context, m: JSONObject) {
        val id = m.optInt("id")
        when (m.optString("t")) {
            "file" -> {
                val name = m.getString("name").substringAfterLast('/').ifBlank { "file" }
                val v = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, name)
                    put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                    put(MediaStore.Downloads.IS_PENDING, 1)
                }
                val uri = ctx.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, v) ?: return
                incoming[id] = In(ctx.contentResolver.openOutputStream(uri)!!, uri, name)
            }
            "file_end" -> incoming.remove(id)?.let {
                it.out.close()
                ctx.contentResolver.update(it.uri, ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }, null, null)
                val nm = ctx.getSystemService(NotificationManager::class.java)
                nm.createNotificationChannel(NotificationChannel("files", "Received files", NotificationManager.IMPORTANCE_DEFAULT))
                nm.notify(id, android.app.Notification.Builder(ctx, "files").setSmallIcon(android.R.drawable.stat_sys_download_done)
                    .setContentTitle("Received from Mac").setContentText("${it.name} saved to Downloads").build())
            }
        }
    }

    fun onChunk(plain: ByteArray) {
        val id = ByteBuffer.wrap(plain, 1, 4).int
        incoming[id]?.out?.write(plain, 5, plain.size - 5)
    }

    /** Streams [uri] to the Mac in 192 KB chunks; calls [done] when finished (or immediately if not connected). */
    fun send(ctx: Context, uri: Uri, done: () -> Unit = {}) {
        val link = App.link
        if (!link.connected) return done()
        Thread {
            try {
                var name = "file"; var size = 0L
                ctx.contentResolver.query(uri, null, null, null, null)?.use { c ->
                    if (c.moveToFirst()) {
                        c.getColumnIndex(OpenableColumns.DISPLAY_NAME).takeIf { it >= 0 }?.let { name = c.getString(it) }
                        c.getColumnIndex(OpenableColumns.SIZE).takeIf { it >= 0 }?.let { size = c.getLong(it) }
                    }
                }
                val id = Random.nextInt(1, Int.MAX_VALUE)
                link.send(JSONObject().put("t", "file").put("id", id).put("name", name).put("size", size))
                ctx.contentResolver.openInputStream(uri)?.use { ins ->
                    val buf = ByteArray(192 * 1024); var n: Int
                    while (ins.read(buf).also { n = it } > 0)
                        link.sendBlocking(ByteBuffer.allocate(5 + n).put(1).putInt(id).put(buf, 0, n).array())
                }
                link.send(JSONObject().put("t", "file_end").put("id", id))
            } finally { done() }
        }.start()
    }
}
