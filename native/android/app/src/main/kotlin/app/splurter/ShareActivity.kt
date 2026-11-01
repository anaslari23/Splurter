package app.splurter

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.Toast
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicInteger

/** Share-sheet target: "Splurter" sends shared files (or text, as clipboard) to the Mac. Stays alive until reads finish. */
class ShareActivity : Activity() {
    override fun onCreate(b: Bundle?) {
        super.onCreate(b)
        startForegroundService(Intent(this, LinkService::class.java))
        val uris = if (intent.action == Intent.ACTION_SEND_MULTIPLE) intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java).orEmpty()
                   else listOfNotNull(intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java))
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)
        if (!App.link.connected) { Toast.makeText(this, "Mac not connected", Toast.LENGTH_SHORT).show(); return finish() }
        if (uris.isEmpty() && text != null) App.link.send(JSONObject().put("t", "clip").put("text", text))
        val left = AtomicInteger(uris.size)
        uris.forEach { Files.send(this, it) { if (left.decrementAndGet() == 0) finish() } }
        Toast.makeText(this, "Sending to Mac…", Toast.LENGTH_SHORT).show()
        if (uris.isEmpty()) finish()
    }
}
