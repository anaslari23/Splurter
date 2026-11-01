package app.splurter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import org.json.JSONObject
import kotlin.math.sqrt

/**
 * Call-audio bridge (frame type 3 = [3][PCM16 mono 16 kHz]). Android won't let apps tap or inject call audio, so this
 * is acoustic: phone mic -> Mac (hears the call on speakerphone), Mac voice -> phone speaker -> phone mic -> call.
 * Mic capture needs the user's tap on a notification (starting a microphone service from the background isn't allowed).
 */
object Audio {
    /** Armed + mid-call: start at once. Otherwise fall back to a notification the user must tap (Android blocks starting mic capture from the background). */
    fun request(ctx: Context, src: String) {
        android.util.Log.d("splurter", "audio_start received, src=$src armed=${AudioService.instance?.armed} call=${Phone.state}")
        val svc = AudioService.instance
        if (svc != null && svc.armed && Phone.state == "offhook") { svc.begin(src); return }
        val nm = ctx.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel("audio", "Call audio requests", NotificationManager.IMPORTANCE_HIGH))
        nm.notify(4, Notification.Builder(ctx, "audio").setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("Your Mac wants to use this call").setContentText("Tap to let it hear and speak on the call").setAutoCancel(true)
            .setContentIntent(PendingIntent.getForegroundService(ctx, 1, Intent(ctx, AudioService::class.java).putExtra("src", src), PendingIntent.FLAG_IMMUTABLE)).build())
        App.link.send(JSONObject().put("t", "audio_state").put("state", "waiting"))
    }
    fun onFrame(plain: ByteArray) { AudioService.instance?.play(plain) }
    fun stop() { AudioService.instance?.stopAudio() }
}

/**
 * Foreground service of type microphone. Armed ("arm" extra, started from the visible app so Android allows it) it idles
 * with mic access reserved; begin() then starts capture on demand. Unarmed it captures right away and stops itself.
 */
class AudioService : Service() {
    @Volatile private var running = false
    @Volatile var armed = false
    private var track: AudioTrack? = null

    override fun onBind(i: Intent?) = null

    private fun foreground(text: String) {
        getSystemService(NotificationManager::class.java).createNotificationChannel(NotificationChannel("audio_live", "Call audio", NotificationManager.IMPORTANCE_LOW))
        startForeground(5, Notification.Builder(this, "audio_live").setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle(text).build(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
    }

    override fun onStartCommand(i: Intent, f: Int, id: Int): Int {
        instance = this
        if (i.getBooleanExtra("arm", false)) { armed = true; foreground("Ready: your Mac can use call audio"); return START_NOT_STICKY }
        foreground("Your Mac is using this call\'s audio")
        begin(i.getStringExtra("src"))
        return START_NOT_STICKY
    }

    fun begin(srcName: String?) {
        if (running) return
        android.util.Log.d("splurter", "audio begin src=$srcName")
        foreground("Your Mac is using this call\'s audio")
        getSystemService(AudioManager::class.java).apply { @Suppress("DEPRECATION") runCatching { isSpeakerphoneOn = true } } // best effort; user may need to tap speaker
        val src = when (srcName) { "comm" -> MediaRecorder.AudioSource.VOICE_COMMUNICATION; "recog" -> MediaRecorder.AudioSource.VOICE_RECOGNITION; else -> MediaRecorder.AudioSource.MIC }
        val sr = 16000
        val rec = AudioRecord(src, sr, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, 16000)
        // USAGE_MEDIA on purpose: the modem's echo canceller only references call audio, so this still reaches the far end.
        track = AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            .setAudioFormat(AudioFormat.Builder().setSampleRate(sr).setEncoding(AudioFormat.ENCODING_PCM_16BIT).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
            .setBufferSizeInBytes(16000).setTransferMode(AudioTrack.MODE_STREAM).build()
        rec.startRecording(); track!!.play(); running = true
        android.util.Log.d("splurter", "AudioRecord state=${rec.state} recording=${rec.recordingState} speaker=${getSystemService(AudioManager::class.java).isSpeakerphoneOn}")
        App.link.send(JSONObject().put("t", "audio_state").put("state", "live"))
        Thread {
            val buf = ByteArray(640); var n = 0; var sum = 0.0; var cnt = 0
            while (running && App.link.connected) {
                val r = rec.read(buf, 0, buf.size)
                if (r <= 0) continue
                App.link.sendVideo(byteArrayOf(3) + buf.copyOf(r))
                for (k in 0 until r - 1 step 2) { val v = ((buf[k].toInt() and 0xff) or (buf[k + 1].toInt() shl 8)).toShort().toDouble(); sum += v * v; cnt++ }
                if (n % 50 == 0) android.util.Log.d("splurter", "mic rms=${"%.4f".format(sqrt(sum / cnt.coerceAtLeast(1)) / 32768.0)} read=$r")
                if (++n % 50 == 0) { // ~1 s: report mic level so the Mac can show whether Android is feeding us real audio or silence
                    App.link.send(JSONObject().put("t", "audio_state").put("state", "live").put("level", sqrt(sum / cnt.coerceAtLeast(1)) / 32768.0)); sum = 0.0; cnt = 0
                }
            }
            running = false
            runCatching { rec.stop(); rec.release(); track?.stop(); track?.release() }
            App.link.send(JSONObject().put("t", "audio_state").put("state", "off"))
            if (armed) foreground("Ready: your Mac can use call audio") else stopSelf()
        }.start()
    }

    fun play(plain: ByteArray) { track?.write(plain, 1, plain.size - 1, AudioTrack.WRITE_NON_BLOCKING) }

    /** Ends a capture session; an armed service stays up for the next call. */
    fun stopAudio() { if (armed) running = false else stopSelf() }

    override fun onDestroy() { running = false; if (instance === this) instance = null; super.onDestroy() }
    companion object { @Volatile var instance: AudioService? = null }
}
