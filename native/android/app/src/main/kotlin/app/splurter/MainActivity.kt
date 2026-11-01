package app.splurter

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Bundle
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import org.json.JSONObject

class MainActivity : Activity() {
    private lateinit var status: TextView
    private val clip by lazy { getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager }
    private val link = Link(
        onMessage = { m ->
            if (m.optString("t") == "clip") runOnUiThread {
                clip.setPrimaryClip(ClipData.newPlainText("mac", m.getString("text")))
                status.text = "← Mac: ${m.getString("text").take(60)}"
            }
        },
        onState = { runOnUiThread { status.text = it } },
    )

    override fun onCreate(b: Bundle?) {
        super.onCreate(b)
        status = TextView(this).apply { text = "Not paired"; textSize = 18f }
        val scan = Button(this).apply {
            text = "Scan Mac QR"
            setOnClickListener {
                GmsBarcodeScanning.getClient(this@MainActivity).startScan()
                    .addOnSuccessListener { link.connect(it.rawValue ?: return@addOnSuccessListener) }
                    .addOnFailureListener { status.text = "Scan failed: ${it.message}" }
            }
        }
        val send = Button(this).apply {
            text = "Send clipboard to Mac"
            // Android 10+ only allows clipboard reads while we're focused — hence a button, not a background watcher.
            setOnClickListener {
                val t = clip.primaryClip?.getItemAt(0)?.text?.toString() ?: return@setOnClickListener
                Thread { link.send(JSONObject().put("t", "clip").put("text", t)) }.start()
                status.text = "→ Mac: ${t.take(60)}"
            }
        }
        setContentView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; setPadding(48, 96, 48, 48)
            addView(status); addView(scan); addView(send)
        })
    }
}
