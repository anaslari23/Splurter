package app.splurter

import android.Manifest
import android.app.Activity
import android.content.ClipboardManager
import android.content.Intent
import android.os.Bundle
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import org.json.JSONObject

class MainActivity : Activity() {
    private lateinit var status: TextView
    private val link get() = App.link

    override fun onCreate(b: Bundle?) {
        super.onCreate(b)
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS, Manifest.permission.SEND_SMS, Manifest.permission.READ_PHONE_STATE,
            Manifest.permission.READ_CALL_LOG, Manifest.permission.ANSWER_PHONE_CALLS, Manifest.permission.CALL_PHONE,
            Manifest.permission.READ_CONTACTS), 0)
        startForegroundService(Intent(this, LinkService::class.java))

        status = TextView(this).apply { text = link.state; textSize = 18f }
        fun btn(t: String, f: () -> Unit) = Button(this).apply { text = t; setOnClickListener { f() } }
        setContentView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; setPadding(48, 96, 48, 48)
            addView(status)
            addView(btn("Scan Mac QR") {
                GmsBarcodeScanning.getClient(this@MainActivity).startScan()
                    .addOnSuccessListener { link.pair(it.rawValue ?: return@addOnSuccessListener) }
                    .addOnFailureListener { status.text = "Scan failed: ${it.message}" }
            })
            // Android 10+ only allows clipboard reads while we're focused — hence a button, not a background watcher.
            addView(btn("Send clipboard to Mac") {
                val t = getSystemService(ClipboardManager::class.java).primaryClip?.getItemAt(0)?.text?.toString() ?: return@btn
                Thread { link.send(JSONObject().put("t", "clip").put("text", t)) }.start()
            })
            addView(btn("Send file to Mac") {
                startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply { type = "*/*"; addCategory(Intent.CATEGORY_OPENABLE) }, 1)
            })
            addView(btn("Allow notification access") { startActivity(Intent(android.provider.Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)) })
            addView(btn("Forget Mac") { link.forget() })
        })
    }

    override fun onActivityResult(req: Int, res: Int, data: Intent?) { data?.data?.let { Files.send(applicationContext, it) } }

    override fun onResume() { super.onResume(); link.onState = { s -> runOnUiThread { status.text = s } }; status.text = link.state }
    override fun onPause() { super.onPause(); link.onState = null }
}
