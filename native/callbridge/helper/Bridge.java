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
 * Usage: Bridge <port> [mute=0|1] [vol=0|1]   (mute: mute the phone's own mic; vol: drop the local call volume)
 */
public class Bridge {
    static final int RATE = 16000;
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
            int port = Integer.parseInt(a[0]);
            boolean mute = false, vol = false;
            for (int i = 1; i < a.length; i++) { if (a[i].equals("mute=1")) mute = true; if (a[i].equals("vol=1")) vol = true; }
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
            rx.startRecording(); tx.play();
            System.out.println("capture state=" + rx.getRecordingState() + " track state=" + tx.getState() + " playState=" + tx.getPlayState());

            // Abstract unix socket (like scrcpy): adbd can reach it, unlike a TCP loopback port owned by the shell user.
            android.net.LocalServerSocket ss = new android.net.LocalServerSocket("splurter_bridge_" + port);
            System.out.println("listening on abstract socket splurter_bridge_" + port);
            android.net.LocalSocket s = ss.accept();
            System.out.println("client connected");
            if (mute) { amc.getMethod("setMicrophoneMute", boolean.class).invoke(am, true); System.out.println("phone mic muted -> " + amc.getMethod("isMicrophoneMute").invoke(am)); }
            if (vol) { amc.getMethod("setStreamVolume", int.class, int.class, int.class).invoke(am, 0, 1, 0); System.out.println("voice volume -> " + amc.getMethod("getStreamVolume", int.class).invoke(am, 0)); }

            final OutputStream out = s.getOutputStream(); final InputStream in = s.getInputStream();
            final AudioRecord rxf = rx;
            final java.util.concurrent.LinkedBlockingQueue<byte[]> outq = new java.util.concurrent.LinkedBlockingQueue<>();
            final int[] stat = new int[4]; // reads, dropped-on-send, max read gap ms, max send queue
            Thread t1 = new Thread(() -> { // capture the caller's voice (never blocks on the network)
                byte[] buf = new byte[640]; long last = System.nanoTime();
                try { while (true) { int n = rxf.read(buf, 0, buf.length); if (n <= 0) continue;
                    long now = System.nanoTime(); int gap = (int) ((now - last) / 1000000); last = now; if (gap > stat[2]) stat[2] = gap; stat[0]++;
                    outq.offer(java.util.Arrays.copyOf(buf, n)); while (outq.size() > 50) { outq.poll(); stat[1]++; } if (outq.size() > stat[3]) stat[3] = outq.size(); } }
                catch (Throwable e) { System.out.println("rx loop ended: " + e); }
            });
            Thread t1b = new Thread(() -> { // send to the client
                try { while (true) { byte[] c2 = outq.take(); out.write(c2, 0, c2.length); } } catch (Throwable e) { System.out.println("send loop ended: " + e); }
            });
            t1b.setDaemon(true); t1b.start();
            Thread ts = new Thread(() -> { try { while (true) { Thread.sleep(2000);
                System.out.println("stats: reads=" + stat[0] + " droppedOnSend=" + stat[1] + " maxReadGapMs=" + stat[2] + " maxSendQueue=" + stat[3]); stat[2] = 0; stat[3] = 0; } } catch (Throwable e) {} });
            ts.setDaemon(true); ts.start();
            // client -> call uplink, through a jitter buffer: absorb bursty arrivals, fill gaps with silence, cap latency.
            final java.util.concurrent.LinkedBlockingQueue<byte[]> q = new java.util.concurrent.LinkedBlockingQueue<>();
            Thread t2 = new Thread(() -> {
                byte[] buf = new byte[1280];
                try { int n; while ((n = in.read(buf)) > 0) { q.offer(java.util.Arrays.copyOf(buf, n)); while (q.size() > 24) q.poll(); } } catch (Throwable e) { System.out.println("tx loop ended: " + e); }
                System.out.println("client gone"); System.exit(0);
            });
            Thread t3 = new Thread(() -> {
                try {
                    while (q.size() < 5) Thread.sleep(10); // prebuffer ~100 ms
                    int under = 0;
                    while (true) {
                        byte[] chunk = q.poll(30, java.util.concurrent.TimeUnit.MILLISECONDS);
                        if (chunk == null) { chunk = new byte[640]; under++; if (under % 50 == 1) System.out.println("underruns=" + under); }
                        tx.write(chunk, 0, chunk.length);
                    }
                } catch (Throwable e) { System.out.println("writer ended: " + e); }
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
