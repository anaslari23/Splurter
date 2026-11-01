package app.splurter

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import android.util.Base64
import org.json.JSONObject
import java.io.ByteArrayOutputStream

/** Now-playing + transport controls from the phone's active media session, and the music volume, in both directions. */
object Media {
    private lateinit var ctx: Context
    private val main = Handler(Looper.getMainLooper())
    private var watched = emptyList<MediaController>()
    private var lastTrack = ""
    private val cb = object : MediaController.Callback() {
        override fun onPlaybackStateChanged(state: PlaybackState?) = report()
        override fun onMetadataChanged(metadata: MediaMetadata?) = report()
        override fun onSessionDestroyed() = refresh()
    }

    /** Volume changes (hardware keys, Mac slider) arrive as this broadcast. */
    fun init(c: Context) {
        ctx = c.applicationContext
        ctx.registerReceiver(object : BroadcastReceiver() {
            override fun onReceive(c: Context, i: Intent) { if (i.getIntExtra("android.media.EXTRA_VOLUME_STREAM_TYPE", -1) == AudioManager.STREAM_MUSIC) sendVolume() }
        }, IntentFilter("android.media.VOLUME_CHANGED_ACTION"), Context.RECEIVER_EXPORTED)
    }

    /** Needs notification access (the same grant the notification mirror uses). */
    fun start(listener: ComponentName) = main.post {
        runCatching {
            val msm = ctx.getSystemService(MediaSessionManager::class.java)
            msm.addOnActiveSessionsChangedListener({ refresh(it) }, listener, main)
            refresh(msm.getActiveSessions(listener))
        }
    }

    private fun refresh(list: List<MediaController>? = null) {
        val l = list ?: runCatching { ctx.getSystemService(MediaSessionManager::class.java).getActiveSessions(ComponentName(ctx, NotifService::class.java)) }.getOrNull() ?: return
        watched.forEach { it.unregisterCallback(cb) }
        watched = l; l.forEach { it.registerCallback(cb, main) }
        report()
    }

    /** The session that is playing, else the most recent one. */
    private fun current() = watched.firstOrNull { it.playbackState?.state == PlaybackState.STATE_PLAYING } ?: watched.firstOrNull()

    fun resync() { lastTrack = ""; main.post { report() }; sendVolume() }

    private fun report() {
        val c = current()
        val m = c?.metadata
        if (c == null || m == null) { App.link.send(JSONObject().put("t", "media").put("active", false)); lastTrack = ""; return }
        val ps = c.playbackState
        val title = m.getString(MediaMetadata.METADATA_KEY_TITLE).orEmpty()
        val artist = (m.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: m.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST)).orEmpty()
        val j = JSONObject().put("t", "media").put("active", true).put("title", title).put("artist", artist)
            .put("app", runCatching { ctx.packageManager.getApplicationLabel(ctx.packageManager.getApplicationInfo(c.packageName, 0)).toString() }.getOrDefault(c.packageName))
            .put("playing", ps?.state == PlaybackState.STATE_PLAYING).put("dur", m.getLong(MediaMetadata.METADATA_KEY_DURATION))
            .put("pos", ps?.position ?: 0L).put("speed", ps?.playbackSpeed ?: 1f.toDouble())
        val key = "${c.packageName}|$title|$artist"
        if (key != lastTrack) { lastTrack = key; j.put("art", art(m)) } // art only when the track changes; the Mac keeps it
        App.link.send(j)
    }

    private fun art(m: MediaMetadata): String {
        val b = m.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART) ?: m.getBitmap(MediaMetadata.METADATA_KEY_ART) ?: return ""
        val s = Bitmap.createScaledBitmap(b, 160, 160, true)
        return Base64.encodeToString(ByteArrayOutputStream().also { s.compress(Bitmap.CompressFormat.JPEG, 80, it) }.toByteArray(), Base64.NO_WRAP)
    }

    private fun sendVolume() {
        val am = ctx.getSystemService(AudioManager::class.java)
        App.link.send(JSONObject().put("t", "volume").put("level", am.getStreamVolume(AudioManager.STREAM_MUSIC)).put("max", am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)))
    }

    fun handle(m: JSONObject) = runCatching {
        when (m.optString("t")) {
            "media_cmd" -> main.post {
                val tc = current()?.transportControls ?: return@post
                when (m.getString("cmd")) {
                    "play" -> tc.play(); "pause" -> tc.pause(); "next" -> tc.skipToNext(); "prev" -> tc.skipToPrevious()
                    "seek" -> tc.seekTo(m.getLong("pos"))
                }
            }
            "volume_set" -> { // fraction 0..1
                val am = ctx.getSystemService(AudioManager::class.java)
                am.setStreamVolume(AudioManager.STREAM_MUSIC, Math.round(m.getDouble("level") * am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)).toInt(), 0)
            }
        }
    }
}
