package app.splurter

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.telephony.TelephonyManager
import org.json.JSONObject

/** What a status bar shows (battery, Wi-Fi, signal), for the Mac's phone window; and the screen wake lock that keeps a locked phone running it. */
object Status {
    private val main = Handler(Looper.getMainLooper())
    private var wl: PowerManager.WakeLock? = null

    fun start(ctx: Context) {
        main.removeCallbacksAndMessages(null)
        val tick = object : Runnable { override fun run() { send(ctx); main.postDelayed(this, 20_000) } }
        tick.run()
    }

    fun send(ctx: Context) = runCatching {
        val b = ctx.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = b?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = b?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
        val charging = (b?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1).let { it == BatteryManager.BATTERY_STATUS_CHARGING || it == BatteryManager.BATTERY_STATUS_FULL }
        val cm = ctx.getSystemService(ConnectivityManager::class.java)
        val wifi = cm.getNetworkCapabilities(cm.activeNetwork)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        val tm = ctx.getSystemService(TelephonyManager::class.java)
        val signal = runCatching { tm.signalStrength?.level ?: 0 }.getOrDefault(0)
        App.link.send(JSONObject().put("t", "status").put("battery", if (level < 0) -1 else level * 100 / scale).put("charging", charging)
            .put("wifi", wifi).put("signal", signal).put("carrier", tm.networkOperatorName.orEmpty()))
    }

    /** Keeps the screen "on" (the Mac turns the panel off) so a locked phone keeps running the Mac's virtual screen. Expires by itself
     *  after a minute unless the Mac renews it, so a vanished Mac can't leave the phone awake. */
    @Suppress("DEPRECATION")
    fun awake(ctx: Context, on: Boolean) {
        wl?.takeIf { it.isHeld }?.release(); wl = null
        if (!on) return
        wl = ctx.getSystemService(PowerManager::class.java).newWakeLock(PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP, "splurter:mirror").apply { acquire(60_000) }
    }
}
