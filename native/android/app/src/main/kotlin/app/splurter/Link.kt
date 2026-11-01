package app.splurter

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.util.Base64
import org.json.JSONObject
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.Inet4Address
import java.net.InetSocketAddress
import java.net.Socket
import java.nio.ByteBuffer
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.X509EncodedKeySpec
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.KeyAgreement
import javax.crypto.Mac
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Phone end of the link. Wire format mirrors mac/Sources/Splurter/{Crypto,Link}.swift.
 * Owns a reconnect loop: finds the paired Mac via Bonjour (fallback: last QR address) and keeps a session open.
 * ponytail: one paired Mac; identity key lives in app-private prefs (Android Keystore has no X25519).
 */
class Link(private val ctx: Context) {
    private val prefs = ctx.getSharedPreferences("link", Context.MODE_PRIVATE)
    private val lock = Object()
    @Volatile private var running = false
    @Volatile private var socket: Socket? = null
    @Volatile private var pendingToken: ByteArray? = null
    private var out: DataOutputStream? = null
    private var sendKey = ByteArray(0); private var recvKey = ByteArray(0)
    private var sendN = 0L; private var recvN = 0L

    @Volatile var state = if (prefs.contains("mac_key")) "Looking for Mac…" else "Not paired"; private set
    var onState: ((String) -> Unit)? = null
    var onMsg: ((JSONObject) -> Unit)? = null
    var onConnected: (() -> Unit)? = null
    var onChunk: ((ByteArray) -> Unit)? = null
    val connected get() = out != null
    private val pending = java.util.concurrent.atomic.AtomicInteger()
    val backlog get() = pending.get() // frames queued for the wire; video senders drop when this grows
    private val tx = java.util.concurrent.Executors.newSingleThreadExecutor()
    val paired get() = prefs.contains("mac_key")

    private fun set(s: String) { state = s; onState?.invoke(s) }
    private fun b64(s: String) = Base64.decode(s, Base64.NO_WRAP)
    private fun b64(b: ByteArray) = Base64.encodeToString(b, Base64.NO_WRAP)

    private val me: KeyPair by lazy {
        val kf = KeyFactory.getInstance("X25519")
        val priv = prefs.getString("sk_priv", null); val pub = prefs.getString("sk_pub", null)
        if (priv != null && pub != null) KeyPair(kf.generatePublic(X509EncodedKeySpec(b64(pub))), kf.generatePrivate(PKCS8EncodedKeySpec(b64(priv))))
        else KeyPairGenerator.getInstance("X25519").generateKeyPair().also {
            prefs.edit().putString("sk_priv", b64(it.private.encoded)).putString("sk_pub", b64(it.public.encoded)).apply()
        }
    }
    private fun raw(k: KeyPair) = k.public.encoded.takeLast(32).toByteArray() // X.509 wrapper = fixed 12-byte prefix

    fun start() { if (running) return; running = true; Thread(::loop, "link").start() }

    fun pair(qr: String) {
        val p = JSONObject(qr)
        prefs.edit().putString("mac_key", p.getString("key")).putString("mac_host", p.getString("host")).putInt("mac_port", p.getInt("port")).apply()
        pendingToken = b64(p.getString("tok"))
        set("Pairing…"); socket?.close(); wake()
    }

    fun forget() {
        prefs.edit().remove("mac_key").apply(); pendingToken = null; socket?.close(); set("Not paired")
    }

    /** Thread-safe, non-blocking; frames go out in call order. */
    fun send(m: JSONObject) { tx.execute { sendNow(m) } }

    fun sendVideo(plain: ByteArray) { pending.incrementAndGet(); tx.execute { try { sendRaw(plain) } finally { pending.decrementAndGet() } } }

    /** Waits until the frame is written — gives file senders backpressure so small messages can interleave. */
    fun sendBlocking(plain: ByteArray) { tx.submit { sendRaw(plain) }.get() }

    private fun sendNow(m: JSONObject) = sendRaw(byteArrayOf(0) + m.toString().toByteArray()) // frame type 0 = JSON, 1 = file chunk

    private fun sendRaw(plain: ByteArray) {
        val o = out ?: return
        try {
            val ct = aead(Cipher.ENCRYPT_MODE, sendKey, sendN++, plain)
            o.writeInt(ct.size); o.write(ct); o.flush()
        } catch (e: Exception) { socket?.close() }
    }

    private fun wake() = synchronized(lock) { lock.notifyAll() }
    private fun nap(ms: Long) = synchronized(lock) { lock.wait(ms) }

    private fun loop() {
        var backoff = 1000L
        while (running) {
            val macKey = prefs.getString("mac_key", null)?.let(::b64)
            if (macKey == null) { nap(60_000); continue }
            try {
                set(if (pendingToken != null) "Pairing…" else "Looking for Mac…")
                val addr = discover(macKey) ?: (prefs.getString("mac_host", "")!! to prefs.getInt("mac_port", 0))
                if (session(addr.first, addr.second, macKey)) backoff = 1000
            } catch (e: Exception) { if (paired) set("Reconnecting… (${e.javaClass.simpleName})") }
            out = null
            if (paired) { nap(backoff); backoff = (backoff * 2).coerceAtMost(30_000) }
        }
    }

    /** Runs one session; returns true if it got as far as an authenticated hello. */
    private fun session(host: String, port: Int, macStatic: ByteArray): Boolean {
        val s = Socket().also { socket = it }
        s.connect(InetSocketAddress(host, port), 5000); s.keepAlive = true; s.soTimeout = 35_000 // Mac pings every 10s
        val inp = DataInputStream(s.getInputStream()); val dos = DataOutputStream(s.getOutputStream())
        val token = pendingToken
        val eph = KeyPairGenerator.getInstance("X25519").generateKeyPair()
        dos.write(raw(eph) + byteArrayOf(if (token != null) 0 else 1) + raw(me)); dos.flush()
        val macEph = ByteArray(32).also { inp.readFully(it) }

        val ikm = dh(eph, macStatic) + dh(eph, macEph) + dh(me, macStatic) + dh(me, macEph)
        val okm = hkdf(ikm, token ?: ByteArray(32), "splurter/v2".toByteArray(), 64)
        sendKey = okm.copyOfRange(0, 32); recvKey = okm.copyOfRange(32, 64); sendN = 0; recvN = 0
        out = dos
        sendNow(JSONObject().put("t", "hello").put("name", android.os.Build.MODEL))

        var ok = false
        try {
            while (true) {
                val len = inp.readInt(); require(len in 16..(1 shl 20))
                val body = ByteArray(len).also { inp.readFully(it) }
                val plain = aead(Cipher.DECRYPT_MODE, recvKey, recvN++, body)
                if (plain[0] == 1.toByte()) { onChunk?.invoke(plain); continue }
                val m = JSONObject(String(plain, 1, plain.size - 1))
                when (m.optString("t")) {
                    "hello" -> { ok = true; pendingToken = null; set("Connected to ${m.optString("name", "Mac")}"); onConnected?.invoke() }
                    else -> onMsg?.invoke(m)
                }
            }
        } catch (e: Exception) { if (!ok) throw e } finally { s.close() }
        return ok
    }

    private fun discover(macStatic: ByteArray): Pair<String, Int>? {
        val fp = MessageDigest.getInstance("SHA-256").digest(macStatic).take(8).joinToString("") { "%02x".format(it) }
        val nsd = ctx.getSystemService(NsdManager::class.java)
        val latch = CountDownLatch(1); var found: Pair<String, Int>? = null
        val resolver = object : NsdManager.ResolveListener {
            override fun onResolveFailed(i: NsdServiceInfo, e: Int) {}
            override fun onServiceResolved(i: NsdServiceInfo) {
                val h = i.host
                if (i.attributes["id"]?.toString(Charsets.UTF_8) == fp && h is Inet4Address) { found = h.hostAddress!! to i.port; latch.countDown() }
            }
        }
        val disc = object : NsdManager.DiscoveryListener {
            override fun onServiceFound(i: NsdServiceInfo) { nsd.resolveService(i, resolver) }
            override fun onStartDiscoveryFailed(t: String, e: Int) { latch.countDown() }
            override fun onStopDiscoveryFailed(t: String, e: Int) {}
            override fun onDiscoveryStarted(t: String) {}
            override fun onDiscoveryStopped(t: String) {}
            override fun onServiceLost(i: NsdServiceInfo) {}
        }
        nsd.discoverServices("_splurter._tcp", NsdManager.PROTOCOL_DNS_SD, disc)
        latch.await(4, TimeUnit.SECONDS)
        runCatching { nsd.stopServiceDiscovery(disc) }
        return found
    }

    // --- crypto -----------------------------------------------------------------------------------------

    private fun aead(mode: Int, key: ByteArray, n: Long, data: ByteArray): ByteArray {
        val iv = ByteBuffer.allocate(12).putInt(0).putLong(n).array()
        return Cipher.getInstance("ChaCha20-Poly1305").run {
            init(mode, SecretKeySpec(key, "ChaCha20"), IvParameterSpec(iv)); doFinal(data)
        }
    }

    private fun dh(mine: KeyPair, peerRaw: ByteArray): ByteArray {
        val prefix = byteArrayOf(0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x6e, 0x03, 0x21, 0x00)
        val pub = KeyFactory.getInstance("X25519").generatePublic(X509EncodedKeySpec(prefix + peerRaw))
        return KeyAgreement.getInstance("X25519").run { init(mine.private); doPhase(pub, true); generateSecret() }
    }

    private fun hmac(key: ByteArray, d: ByteArray) =
        Mac.getInstance("HmacSHA256").run { init(SecretKeySpec(key, "HmacSHA256")); doFinal(d) }

    private fun hkdf(ikm: ByteArray, salt: ByteArray, info: ByteArray, len: Int): ByteArray {
        val prk = hmac(salt, ikm); var t = ByteArray(0); var out = ByteArray(0); var i = 1
        while (out.size < len) { t = hmac(prk, t + info + byteArrayOf(i++.toByte())); out += t }
        return out.copyOf(len)
    }
}
