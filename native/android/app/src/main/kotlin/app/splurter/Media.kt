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
import org.json.JSONArray
import org.json.JSONObject
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.util.Log
import java.io.ByteArrayOutputStream

/** Now-playing + transport controls from the phone's active media session, and the music volume, in both directions. */
object Media {
    private lateinit var ctx: Context
    private val main = Handler(Looper.getMainLooper())
    private var watched = emptyList<MediaController>()
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

    fun resync() { sentArt.clear(); main.post { report() }; sendVolume() }

    /** Playing sessions first, like Android's own media output switcher. */
    private fun ordered() = watched.sortedByDescending { it.playbackState?.state == PlaybackState.STATE_PLAYING }

    private val artCache = HashMap<String, String>() // track key -> base64 JPEG ("" = none found)
    private val sentArt = HashMap<String, String>()  // package -> track key whose art the Mac already has
    private val fetching = HashSet<String>()

    private fun report() {
        val sessions = JSONArray()
        for (c in ordered()) {
            val m = c.metadata ?: continue
            val ps = c.playbackState
            val title = m.getString(MediaMetadata.METADATA_KEY_TITLE).orEmpty()
            val artist = (m.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: m.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST)).orEmpty()
            val key = "${c.packageName}|$title|$artist"
            val j = JSONObject().put("pkg", c.packageName).put("title", title).put("artist", artist)
                .put("app", runCatching { ctx.packageManager.getApplicationLabel(ctx.packageManager.getApplicationInfo(c.packageName, 0)).toString() }.getOrDefault(c.packageName))
                .put("playing", ps?.state == PlaybackState.STATE_PLAYING).put("dur", m.getLong(MediaMetadata.METADATA_KEY_DURATION))
                .put("pos", ps?.position ?: 0L).put("speed", (ps?.playbackSpeed ?: 1f).toDouble())
            var art = artCache[key].orEmpty()
            if (art.isEmpty()) { art = artSync(c, m) ?: run { fetchArt(key, m); "" }; artCache[key] = art } // retried each report: the notification may arrive later
            if (art.isNotEmpty() && sentArt[c.packageName] != key) { j.put("art", art); sentArt[c.packageName] = key } // art only once per track
            sessions.put(j)
        }
        App.link.send(JSONObject().put("t", "media").put("sessions", sessions))
    }

    private fun jpeg(b: Bitmap): String {
        val s = Bitmap.createScaledBitmap(b, 160, 160, true)
        return Base64.encodeToString(ByteArrayOutputStream().also { s.compress(Bitmap.CompressFormat.JPEG, 80, it) }.toByteArray(), Base64.NO_WRAP)
    }

    /** Bitmap in the metadata, else the large icon of the app's media notification (most players put the cover there). */
    private fun artSync(c: MediaController, m: MediaMetadata): String? {
        val bmp = listOf(MediaMetadata.METADATA_KEY_ALBUM_ART, MediaMetadata.METADATA_KEY_ART, MediaMetadata.METADATA_KEY_DISPLAY_ICON).firstNotNullOfOrNull { m.getBitmap(it) }
        if (bmp != null) return jpeg(bmp)
        val n = NotifService.instance?.activeNotifications?.firstOrNull { it.packageName == c.packageName && it.notification.getLargeIcon() != null } ?: return null
        val d = n.notification.getLargeIcon().loadDrawable(ctx) ?: return null
        val b = Bitmap.createBitmap(160, 160, Bitmap.Config.ARGB_8888)
        d.setBounds(0, 0, 160, 160); d.draw(Canvas(b))
        return jpeg(b)
    }

    /** Last resort: an art URI (https or content) in the metadata, fetched off the main thread. */
    private fun fetchArt(key: String, m: MediaMetadata) {
        val uri = listOf(MediaMetadata.METADATA_KEY_ALBUM_ART_URI, MediaMetadata.METADATA_KEY_ART_URI, MediaMetadata.METADATA_KEY_DISPLAY_ICON_URI)
            .firstNotNullOfOrNull { m.getString(it)?.takeIf { u -> u.isNotEmpty() } }
        if (!fetching.add(key)) return
        Log.i("splurter", "media art for $key: no bitmap/notification icon; uri=$uri keys=${m.keySet()}")
        if (uri == null) return
        Thread {
            runCatching {
                val st = if (uri.startsWith("http")) java.net.URL(uri).openStream() else ctx.contentResolver.openInputStream(android.net.Uri.parse(uri))
                val b = st!!.use { BitmapFactory.decodeStream(it) }
                main.post { artCache[key] = jpeg(b); report() }
            }.onFailure { Log.w("splurter", "media art fetch failed: $it") }
        }.start()
    }

    private fun sendVolume() {
        val am = ctx.getSystemService(AudioManager::class.java)
        App.link.send(JSONObject().put("t", "volume").put("level", am.getStreamVolume(AudioManager.STREAM_MUSIC)).put("max", am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)))
    }

    fun handle(m: JSONObject) = runCatching {
        when (m.optString("t")) {
            "media_cmd" -> main.post {
                val tc = (watched.firstOrNull { it.packageName == m.optString("pkg") } ?: ordered().firstOrNull())?.transportControls ?: return@post
                when (m.getString("cmd")) {
                    "play" -> tc.play(); "pause" -> tc.pause(); "next" -> tc.skipToNext(); "prev" -> tc.skipToPrevious()
                    "seek" -> tc.seekTo(m.getLong("pos"))
                }
            }
            "volume_set" -> { // fraction 0..1
                val am = ctx.getSystemService(AudioManager::class.java)
                val idx = Math.round(m.getDouble("level") * am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)).toInt()
                am.setStreamVolume(AudioManager.STREAM_MUSIC, idx, 0)
                Log.i("splurter", "volume_set -> $idx, now ${am.getStreamVolume(AudioManager.STREAM_MUSIC)}")
            }
        }
    }.onFailure { Log.w("splurter", "media handle failed: $it") }
}
