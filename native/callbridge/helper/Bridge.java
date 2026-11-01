import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.AudioTrack;
import android.os.Looper;
import java.io.InputStream;
import java.io.OutputStream;
import java.lang.reflect.Method;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;

/**
 * Two-way call audio bridge, run as the adb shell user on top of scrcpy-server's workarounds.
 *   phone -> client: the caller's voice (AudioRecord VOICE_DOWNLINK), PCM16 mono 16 kHz
 *   client -> phone: audio played into the call uplink (AudioTrack, system usage CALL_ASSISTANT), PCM16 mono 16 kHz
 * Usage: Bridge name=<abstract socket> [token=<secret>] [wait=<seconds>] [mute=0|1] [vol=0|1]
 *   token: if given, the client must send exactly these bytes first or it is dropped (random name + token keep other apps out)
 *   wait:  exit if no valid client connects within this many seconds (default 30)
 *   mute:  mute the phone's own mic;  vol: drop the local call volume
 */
public class Bridge {
    static final int RATE = 16000;
    static final long[] FRAMES_READ = {0};        // cumulative caller frames read from the recorder
    static final long[] FROMMAC = {0};            // bytes received from the Mac
    static final int[] FROMMAC_UNDER = {0}, FROMMAC_QMAX = {0}; // uplink underruns, max queued chunks
    static Object am; static Class<?> amc;
    static int oldVol = -1; static boolean oldMute;

    static android.content.Context fake() throws Exception {
        Method g = Class.forName("com.genymobile.scrcpy.FakeContext").getDeclaredMethod("get"); g.setAccessible(true);
        return (android.content.Context) g.invoke(null);
    }

    static AudioRecord record(int source, int rate, int mask) throws Exception {
        AudioRecord.Builder b = new AudioRecord.Builder();
        AudioRecord.Builder.class.getMethod("setContext", android.content.Context.class).invoke(b, fake());
        b.setAudioSource(source);
        b.setAudioFormat(new AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT).setSampleRate(rate).setChannelMask(mask).build());
        int min = AudioRecord.getMinBufferSize(rate, mask, AudioFormat.ENCODING_PCM_16BIT);
        if (min > 0) b.setBufferSizeInBytes(min * 6); // generous: a stalled send must not overflow the recorder
        return b.build();
    }

    static AudioTrack track() throws Exception {
        AudioAttributes.Builder ab = new AudioAttributes.Builder().setContentType(AudioAttributes.CONTENT_TYPE_SPEECH);
        AudioAttributes.Builder.class.getMethod("setSystemUsage", int.class).invoke(ab, 17); // USAGE_CALL_ASSISTANT -> telephony TX
        return new AudioTrack.Builder().setAudioAttributes(ab.build())
            .setAudioFormat(new AudioFormat.Builder().setSampleRate(RATE).setEncoding(AudioFormat.ENCODING_PCM_16BIT).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
            .setBufferSizeInBytes(RATE / 12 * 2).setTransferMode(AudioTrack.MODE_STREAM).build(); // ~80 ms: low latency, the jitter buffer below absorbs network bursts
    }

    /** How old the audio we just read is, per Android's own capture timestamps (-1 if unavailable). */
    static long captureLatencyMs(AudioRecord r) {
        try {
            android.media.AudioTimestamp ts = new android.media.AudioTimestamp();
            if (r.getTimestamp(ts, android.media.AudioTimestamp.TIMEBASE_MONOTONIC) != AudioRecord.SUCCESS) return -1;
            long capturedAt = ts.nanoTime + (FRAMES_READ[0] - ts.framePosition) * 1000000000L / RATE;
            return (System.nanoTime() - capturedAt) / 1000000;
        } catch (Throwable e) { return -2; }
    }

    /** PCM16 ring buffer with fractional-rate reads (linear interpolation). */
    static final class Ring {
        final short[] buf = new short[RATE * 2]; int rd, wr, fill; double pos; boolean started;
        static final int START = RATE * 150 / 1000, HARD = RATE; final double target = START;
        synchronized void push(byte[] b, int n) {
            for (int i = 0; i + 1 < n; i += 2) { buf[wr] = (short) ((b[i] & 0xff) | (b[i + 1] << 8)); wr = (wr + 1) % buf.length; fill++; }
            if (fill > FROMMAC_QMAX[0]) FROMMAC_QMAX[0] = fill;
            if (fill > HARD) { int drop = fill - (int) target; rd = (rd + drop) % buf.length; fill -= drop; } // emergency only
        }
        synchronized void pull(short[] out, int n) {
            if (!started) { if (fill >= START) { started = true; pos = 0; } else { java.util.Arrays.fill(out, 0, n, (short) 0); return; } }
            double ratio = 1.0 + Math.min(Math.max((fill - target) * 2e-5, -0.02), 0.08);
            if (fill < (int) Math.ceil(n * ratio) + 2) { started = false; FROMMAC_UNDER[0]++; java.util.Arrays.fill(out, 0, n, (short) 0); return; }
            for (int i = 0; i < n; i++) {
                int k = (int) pos; double f = pos - k; short a = buf[(rd + k) % buf.length], b = buf[(rd + k + 1) % buf.length];
                out[i] = (short) (a + (b - a) * f); pos += ratio;
            }
            int used = (int) pos; pos -= used; rd = (rd + used) % buf.length; fill -= used;
        }
    }

    static void restore() {
        try {
            if (am != null) {
                amc.getMethod("setMicrophoneMute", boolean.class).invoke(am, oldMute);
                if (oldVol >= 0) amc.getMethod("setStreamVolume", int.class, int.class, int.class).invoke(am, 0, oldVol, 0);
            }
            System.out.println("restored mic mute=" + oldMute + " voice volume=" + oldVol);
        } catch (Throwable e) { System.out.println("restore failed: " + e); }
    }

    public static void main(String[] a) {
        try {
            String name = "splurter_bridge_27300", token = null; int waitSec = 30; boolean mute = false, vol = false;
            for (String arg : a) {
                if (arg.startsWith("name=")) name = arg.substring(5);
                else if (arg.startsWith("token=")) token = arg.substring(6);
                else if (arg.startsWith("wait=")) waitSec = Integer.parseInt(arg.substring(5));
                else if (arg.equals("mute=1")) mute = true;
                else if (arg.equals("vol=1")) vol = true;
            }
            Looper.prepareMainLooper();
            Method ap = Class.forName("com.genymobile.scrcpy.Workarounds").getDeclaredMethod("apply"); ap.setAccessible(true); ap.invoke(null);

            java.lang.reflect.Constructor<?> c = Class.forName("android.media.AudioManager").getDeclaredConstructor(android.content.Context.class);
            c.setAccessible(true); am = c.newInstance(fake()); amc = am.getClass();
            oldMute = (Boolean) amc.getMethod("isMicrophoneMute").invoke(am);
            oldVol = (Integer) amc.getMethod("getStreamVolume", int.class).invoke(am, 0);
            Runtime.getRuntime().addShutdownHook(new Thread(Bridge::restore));
            System.out.println("start: mic mute=" + oldMute + " voice volume=" + oldVol + " mode=" + amc.getMethod("getMode").invoke(am));

            AudioRecord rx;
            try { rx = record(3, RATE, AudioFormat.CHANNEL_IN_MONO); System.out.println("downlink capture: 16 kHz mono"); }
            catch (Throwable e) { System.out.println("16 kHz mono capture failed (" + e + ")"); throw e; }
            final AudioTrack tx = track();
            tx.play(); // capture starts only after the client connects, so no stale audio is queued before we read
            System.out.println("capture state=" + rx.getRecordingState() + " track state=" + tx.getState() + " playState=" + tx.getPlayState());

            // Abstract unix socket (like scrcpy): adbd can reach it, unlike a TCP loopback port owned by the shell user.
            android.net.LocalServerSocket ss = new android.net.LocalServerSocket(name);
            System.out.println("listening on abstract socket " + name);
            final int waitMs = waitSec * 1000; final boolean[] connected = {false};
            Thread watchdog = new Thread(() -> { try { Thread.sleep(waitMs); } catch (InterruptedException e) { return; }
                if (!connected[0]) { System.out.println("no client within " + waitMs / 1000 + " s, exiting"); System.exit(2); } });
            watchdog.setDaemon(true); watchdog.start();
            android.net.LocalSocket s;
            while (true) {
                s = ss.accept();
                if (token == null) break;
                byte[] want = token.getBytes("UTF-8"), got = new byte[want.length]; int n = 0;
                try { s.setSoTimeout(3000); while (n < got.length) { int k = s.getInputStream().read(got, n, got.length - n); if (k < 0) break; n += k; } } catch (Throwable e) { n = -1; }
                if (n == got.length && java.security.MessageDigest.isEqual(want, got)) {
                    // The Mac sends one more byte (1) once its audio engines are running; capture starts only then, so no
                    // seconds of caller audio pile up in the adb pipe while the Mac is still starting.
                    int ready = -1; try { s.setSoTimeout(15000); ready = s.getInputStream().read(); } catch (Throwable e) { }
                    if (ready == 1) { s.setSoTimeout(0); break; }
                    System.out.println("client never signalled ready"); s.close(); continue;
                }
                System.out.println("rejected a client with a bad or missing token"); s.close();
            }
            connected[0] = true; ss.close(); // one client only: nobody else can attach afterwards
            System.out.println("client connected");
            rx.startRecording();
            if (mute) { amc.getMethod("setMicrophoneMute", boolean.class).invoke(am, true); System.out.println("phone mic muted -> " + amc.getMethod("isMicrophoneMute").invoke(am)); }
            if (vol) { amc.getMethod("setStreamVolume", int.class, int.class, int.class).invoke(am, 0, 1, 0); System.out.println("voice volume -> " + amc.getMethod("getStreamVolume", int.class).invoke(am, 0)); }

            final OutputStream out = s.getOutputStream(); final InputStream in = s.getInputStream();
            final AudioRecord rxf = rx;
            final java.util.concurrent.LinkedBlockingQueue<byte[]> outq = new java.util.concurrent.LinkedBlockingQueue<>();
            final int[] stat = new int[4]; // reads, dropped-on-send, max read gap ms, max send queue
            Thread t1 = new Thread(() -> { // capture the caller's voice (never blocks on the network)
                byte[] buf = new byte[640]; long last = System.nanoTime();
                try { while (true) { int n = rxf.read(buf, 0, buf.length); if (n <= 0) continue; FRAMES_READ[0] += n / 2;
                    long now = System.nanoTime(); int gap = (int) ((now - last) / 1000000); last = now; if (gap > stat[2]) stat[2] = gap; stat[0]++;
                    outq.offer(java.util.Arrays.copyOf(buf, n)); while (outq.size() > 50) { outq.poll(); stat[1]++; } if (outq.size() > stat[3]) stat[3] = outq.size(); } }
                catch (Throwable e) { System.out.println("rx loop ended: " + e); }
            });
            Thread t1b = new Thread(() -> { // send to the client
                try { while (true) { byte[] c2 = outq.take(); out.write(c2, 0, c2.length); } } catch (Throwable e) { System.out.println("send loop ended: " + e); }
            });
            t1b.setDaemon(true); t1b.start();
            Thread ts = new Thread(() -> { try { while (true) { Thread.sleep(2000);
                System.out.println("stats: caller reads=" + stat[0] + " dropped=" + stat[1] + " maxReadGapMs=" + stat[2] + " captureLatencyMs=" + captureLatencyMs(rxf) + " | from Mac: bytes=" + FROMMAC[0] + " underruns=" + FROMMAC_UNDER[0] + " queueMaxMs=" + (FROMMAC_QMAX[0] * 1000 / RATE)); stat[2] = 0; stat[3] = 0; FROMMAC_QMAX[0] = 0; } } catch (Throwable e) {} });
            ts.setDaemon(true); ts.start();
            // client -> call uplink, through a jitter buffer with drift compensation (see the Mac's Jitter): the Mac clock and
            // this track's clock differ slightly, so steer the buffer toward ~150 ms by playing a little faster or slower.
            final Ring ring = new Ring();
            Thread t2 = new Thread(() -> {
                byte[] buf = new byte[1280];
                try { int n; while ((n = in.read(buf)) > 0) { FROMMAC[0] += n; ring.push(buf, n); } } catch (Throwable e) { System.out.println("tx loop ended: " + e); }
                System.out.println("client gone"); System.exit(0);
            });
            Thread t3 = new Thread(() -> {
                short[] pcm = new short[320]; byte[] bytes = new byte[640];
                try { while (true) {
                    ring.pull(pcm, pcm.length);
                    for (int i = 0; i < pcm.length; i++) { bytes[2 * i] = (byte) pcm[i]; bytes[2 * i + 1] = (byte) (pcm[i] >> 8); }
                    tx.write(bytes, 0, bytes.length); // blocks at real time, so this loop is the uplink's clock
                } } catch (Throwable e) { System.out.println("writer ended: " + e); }
            });
            t3.setDaemon(true); t3.start();
            t1.setDaemon(true); t2.setDaemon(true); t1.start(); t2.start(); t2.join();
        } catch (Throwable e) {
            System.out.println("BRIDGE FAILED: " + e); for (StackTraceElement el : e.getStackTrace()) System.out.println("   at " + el);
            if (e.getCause() != null) System.out.println("   cause: " + e.getCause());
            System.exit(1);
        }
    }
}
