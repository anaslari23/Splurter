package app.splurter

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.hardware.display.DisplayManager
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Bundle
import org.json.JSONObject

/**
 * Screen mirroring. The Mac asks ("mirror_start"); we show a notification and the user must tap it and accept
 * Android's capture prompt — nothing records without an explicit yes on the phone.
 * Video frames are link frame type 2: [2][kind: 0 = SPS/PPS, 1 = keyframe, 2 = delta][H.264 Annex-B].
 */
object Mirror {
    fun request(ctx: Context) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel("mirror", "Screen mirroring requests", NotificationManager.IMPORTANCE_HIGH))
        nm.notify(2, Notification.Builder(ctx, "mirror").setSmallIcon(android.R.drawable.ic_menu_view)
            .setContentTitle("Your Mac wants to show this screen").setContentText("Tap to review and allow")
            .setAutoCancel(true)
            .setContentIntent(PendingIntent.getActivity(ctx, 0, Intent(ctx, ConsentActivity::class.java), PendingIntent.FLAG_IMMUTABLE)).build())
        App.link.send(JSONObject().put("t", "mirror_state").put("state", "waiting"))
    }
}

/** Transparent activity that shows the system screen-capture prompt. */
class ConsentActivity : Activity() {
    override fun onCreate(b: Bundle?) {
        super.onCreate(b)
        startActivityForResult(getSystemService(MediaProjectionManager::class.java).createScreenCaptureIntent(), 1)
    }

    @Deprecated("fine for a transparent trampoline")
    override fun onActivityResult(req: Int, res: Int, data: Intent?) {
        if (res == RESULT_OK && data != null)
            startForegroundService(Intent(this, MirrorService::class.java).putExtra("code", res).putExtra("data", data))
        else App.link.send(JSONObject().put("t", "mirror_state").put("state", "denied"))
        finish()
    }
}

class MirrorService : Service() {
    @Volatile private var running = false
    private var projection: MediaProjection? = null
    private var codec: MediaCodec? = null

    override fun onBind(i: Intent?) = null

    override fun onStartCommand(i: Intent, f: Int, id: Int): Int {
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel("mirror_live", "Screen mirroring", NotificationManager.IMPORTANCE_LOW))
        startForeground(3, Notification.Builder(this, "mirror_live").setSmallIcon(android.R.drawable.ic_menu_view)
            .setContentTitle("Sharing your screen with your Mac").build(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        instance = this
        val mp = getSystemService(MediaProjectionManager::class.java).getMediaProjection(i.getIntExtra("code", 0), i.getParcelableExtra("data", Intent::class.java)!!)!!
        projection = mp
        mp.registerCallback(object : MediaProjection.Callback() { override fun onStop() { stopSelf() } }, null) // required on Android 14+

        // ponytail: fixed size from the current orientation; rotating the phone mid-session isn't handled.
        val b = getSystemService(android.view.WindowManager::class.java).currentWindowMetrics.bounds
        val w = 720; val h = (b.height() * 720f / b.width()).toInt() / 2 * 2
        val fmt = MediaFormat.createVideoFormat("video/avc", w, h).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, 5_000_000); setInteger(MediaFormat.KEY_FRAME_RATE, 30)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 2)
            setLong(MediaFormat.KEY_REPEAT_PREVIOUS_FRAME_AFTER, 200_000) // keep frames flowing on a static screen
            setInteger(MediaFormat.KEY_PRIORITY, 0)
        }
        val enc = MediaCodec.createEncoderByType("video/avc").also { codec = it }
        enc.configure(fmt, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        val surface = enc.createInputSurface(); enc.start()
        val dpi = resources.displayMetrics.densityDpi
        val vd = mp.createVirtualDisplay("splurter", w, h, dpi, DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, surface, null, null)!!

        App.link.send(JSONObject().put("t", "mirror_info").put("w", w).put("h", h))
        App.link.send(JSONObject().put("t", "mirror_state").put("state", "live"))
        running = true
        Thread {
            val info = MediaCodec.BufferInfo(); var needKey = false
            while (running && App.link.connected) {
                val idx = enc.dequeueOutputBuffer(info, 100_000)
                if (idx < 0) continue
                val data = ByteArray(info.size).also { enc.getOutputBuffer(idx)!!.apply { position(info.offset) }.get(it) }
                enc.releaseOutputBuffer(idx, false)
                val kind = when {
                    info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0 -> 0
                    info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME != 0 -> 1
                    else -> 2
                }
                if (kind == 1) needKey = false
                if (kind == 2 && (needKey || App.link.backlog > 4)) { // Mac/network can't keep up: drop, resync at next keyframe
                    if (!needKey) { needKey = true; enc.setParameters(Bundle().apply { putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0) }) }
                    continue
                }
                App.link.sendVideo(byteArrayOf(2, kind.toByte()) + data)
            }
            runCatching { vd.release(); enc.stop(); enc.release(); mp.stop() }
            App.link.send(JSONObject().put("t", "mirror_state").put("state", "stopped"))
            stopSelf()
        }.start()
        return START_NOT_STICKY
    }

    override fun onDestroy() { running = false; if (instance === this) instance = null; super.onDestroy() }

    companion object { @Volatile var instance: MirrorService? = null }
}
