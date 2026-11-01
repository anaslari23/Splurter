package app.splurter

import android.util.Base64
import org.json.JSONObject
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.Socket
import java.nio.ByteBuffer
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.spec.X509EncodedKeySpec
import javax.crypto.Cipher
import javax.crypto.KeyAgreement
import javax.crypto.Mac
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

/** Phone end of the link. Wire format mirrors mac/Sources/Splurter/Crypto.swift. */
class Link(private val onMessage: (JSONObject) -> Unit, private val onState: (String) -> Unit) {
    private var out: DataOutputStream? = null
    private var sendKey = ByteArray(0); private var recvKey = ByteArray(0)
    private var sendN = 0L; private var recvN = 0L

    fun connect(qr: String) = Thread {
        try {
            val p = JSONObject(qr)
            val macStatic = Base64.decode(p.getString("key"), Base64.DEFAULT)
            val token = Base64.decode(p.getString("tok"), Base64.DEFAULT)
            val s = Socket(p.getString("host"), p.getInt("port"))
            val inp = DataInputStream(s.getInputStream()); out = DataOutputStream(s.getOutputStream())

            val eph = KeyPairGenerator.getInstance("X25519").generateKeyPair()
            val ephPub = eph.public.encoded.takeLast(32).toByteArray() // X.509 wrapper is a fixed 12-byte prefix
            out!!.write(ephPub); out!!.flush()
            val macEph = ByteArray(32).also { inp.readFully(it) }

            val dh1 = dh(eph, macStatic); val dh2 = dh(eph, macEph)
            val okm = hkdf(dh1 + dh2, token, "splurter/v1".toByteArray(), 64)
            sendKey = okm.copyOfRange(0, 32); recvKey = okm.copyOfRange(32, 64)

            send(JSONObject().put("t", "hello").put("name", android.os.Build.MODEL))
            onState("Connected")
            while (true) {
                val len = inp.readInt()
                require(len in 16..(1 shl 20))
                val body = ByteArray(len).also { inp.readFully(it) }
                onMessage(JSONObject(String(aead(Cipher.DECRYPT_MODE, recvKey, recvN++, body))))
            }
        } catch (e: Exception) { onState("Disconnected: ${e.message}") }
    }.start()

    @Synchronized fun send(m: JSONObject) {
        val o = out ?: return
        val ct = aead(Cipher.ENCRYPT_MODE, sendKey, sendN++, m.toString().toByteArray())
        o.writeInt(ct.size); o.write(ct); o.flush()
    }

    private fun aead(mode: Int, key: ByteArray, n: Long, data: ByteArray): ByteArray {
        val iv = ByteBuffer.allocate(12).putInt(0).putLong(n).array()
        return Cipher.getInstance("ChaCha20-Poly1305").run {
            init(mode, SecretKeySpec(key, "ChaCha20"), IvParameterSpec(iv)); doFinal(data)
        }
    }

    private fun dh(mine: java.security.KeyPair, peerRaw: ByteArray): ByteArray {
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
