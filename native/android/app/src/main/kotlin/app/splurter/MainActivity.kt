package app.splurter

import android.Manifest
import android.content.ClipboardManager
import android.content.ComponentName
import android.content.Intent
import android.app.NotificationManager
import android.content.pm.PackageManager
import android.os.Bundle
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import org.json.JSONObject

class MainActivity : ComponentActivity() {
    private val link get() = App.link
    private var state by mutableStateOf(App.link.state)
    private var paired by mutableStateOf(App.link.paired)
    private var tick by mutableIntStateOf(0) // bumped to re-check permissions

    private val ask = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { tick++ }
    private val pick = registerForActivityResult(ActivityResultContracts.OpenDocument()) { it?.let { u -> Files.send(applicationContext, u) } }

    private fun has(vararg p: String) = p.all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }

    override fun onCreate(b: Bundle?) {
        super.onCreate(b)
        enableEdgeToEdge()
        ask.launch(arrayOf(Manifest.permission.POST_NOTIFICATIONS))
        startForegroundService(Intent(this, LinkService::class.java))
        setContent {
            SplurterTheme {
                tick // read so permission rows recompose
                val calls = arrayOf(Manifest.permission.READ_PHONE_STATE, Manifest.permission.READ_CALL_LOG, Manifest.permission.ANSWER_PHONE_CALLS, Manifest.permission.CALL_PHONE)
                HomeScreen(state, paired,
                    features = listOf(
                        Feature("Notifications", "Mirror to your Mac, reply from there", featureIcons["notifications"]!!,
                            getSystemService(NotificationManager::class.java).isNotificationListenerAccessGranted(ComponentName(this, NotifService::class.java)))
                        { startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)) },
                        Feature("Calls", "Answer and decline from your Mac", featureIcons["calls"]!!, has(*calls)) { ask.launch(calls) },
                        Feature("Text messages", "Send texts from your Mac", featureIcons["sms"]!!, has(Manifest.permission.SEND_SMS)) { ask.launch(arrayOf(Manifest.permission.SEND_SMS)) },
                        Feature("Contacts", "Show names instead of numbers", featureIcons["contacts"]!!, has(Manifest.permission.READ_CONTACTS)) { ask.launch(arrayOf(Manifest.permission.READ_CONTACTS)) },
                    ),
                    onScan = {
                        GmsBarcodeScanning.getClient(this).startScan()
                            .addOnSuccessListener { link.pair(it.rawValue ?: return@addOnSuccessListener); paired = true }
                            .addOnFailureListener { state = "Scan failed: ${it.message}" }
                    },
                    // Android 10+ only allows clipboard reads while we're focused — hence a button, not a background watcher.
                    onClipboard = {
                        getSystemService(ClipboardManager::class.java).primaryClip?.getItemAt(0)?.text?.toString()
                            ?.let { link.send(JSONObject().put("t", "clip").put("text", it)) }
                    },
                    onFile = { pick.launch(arrayOf("*/*")) },
                    onForget = { link.forget(); paired = false },
                )
            }
        }
    }

    override fun onResume() { super.onResume(); tick++; paired = link.paired; state = link.state; link.onState = { state = it } }
    override fun onPause() { super.onPause(); link.onState = null }
}
