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
    fun request(ctx: Context, src: String) {
        android.util.Log.d("splurter", "audio_start received, src=$src, notifying user")
        val nm = ctx.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel("audio", "Call audio requests", NotificationManager.IMPORTANCE_HIGH))
        nm.notify(4, Notification.Builder(ctx, "audio").setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("Your Mac wants to use this call").setContentText("Tap to let it hear and speak on the call").setAutoCancel(true)
            .setContentIntent(PendingIntent.getForegroundService(ctx, 1, Intent(ctx, AudioService::class.java).putExtra("src", src), PendingIntent.FLAG_IMMUTABLE)).build())
        App.link.send(JSONObject().put("t", "audio_state").put("state", "waiting"))
    }
    fun onFrame(plain: ByteArray) { AudioService.instance?.play(plain) }
    private var rx = 0
    fun logRx() { if (++rx % 100 == 1) android.util.Log.d("splurter", "mac audio frames received: $rx") }
}

class AudioService : Service() {
    @Volatile private var running = false
    private var track: AudioTrack? = null

    override fun onBind(i: Intent?) = null

    override fun onStartCommand(i: Intent, f: Int, id: Int): Int {
        getSystemService(NotificationManager::class.java).createNotificationChannel(NotificationChannel("audio_live", "Call audio", NotificationManager.IMPORTANCE_LOW))
        startForeground(5, Notification.Builder(this, "audio_live").setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("Your Mac is using this call's audio").build(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        instance = this
        android.util.Log.d("splurter", "AudioService started src=${i.getStringExtra("src")}")
        getSystemService(AudioManager::class.java).apply { @Suppress("DEPRECATION") runCatching { isSpeakerphoneOn = true } } // best effort; user may need to tap speaker
        val src = when (i.getStringExtra("src")) { "comm" -> MediaRecorder.AudioSource.VOICE_COMMUNICATION; "recog" -> MediaRecorder.AudioSource.VOICE_RECOGNITION; else -> MediaRecorder.AudioSource.MIC }
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
                for (k in 0 until r - 1 step 2) { val v = (buf[k].toInt() and 0xff) or (buf[k + 1].toInt() shl 8); sum += v.toShort() * v.toShort().toDouble() ; cnt++ }
                if (n % 50 == 0) android.util.Log.d("splurter", "mic rms=${"%.4f".format(sqrt(sum / cnt.coerceAtLeast(1)) / 32768.0)} read=$r")
                if (++n % 50 == 0) { // ~1 s: report mic level so the Mac can show whether Android is feeding us real audio or silence
                    App.link.send(JSONObject().put("t", "audio_state").put("state", "live").put("level", sqrt(sum / cnt.coerceAtLeast(1)) / 32768.0)); sum = 0.0; cnt = 0
                }
            }
            runCatching { rec.stop(); rec.release(); track?.stop(); track?.release() }
            App.link.send(JSONObject().put("t", "audio_state").put("state", "off"))
            stopSelf()
        }.start()
        return START_NOT_STICKY
    }

    fun play(plain: ByteArray) { Audio.logRx(); track?.write(plain, 1, plain.size - 1, AudioTrack.WRITE_NON_BLOCKING) }

    override fun onDestroy() { running = false; if (instance === this) instance = null; super.onDestroy() }
    companion object { @Volatile var instance: AudioService? = null }
}
