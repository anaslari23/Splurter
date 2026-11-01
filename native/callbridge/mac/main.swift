import AVFoundation
import Foundation

// Prototype Mac client for the phone's call-audio helper: plays the caller's voice, sends the Mac mic into the call.
// Wire: raw PCM16 little-endian mono 16 kHz both ways over a TCP socket (adb-forwarded). Logs to /tmp/cbmac.log.
func log(_ s: String) {
    let line = "\(Date().formatted(date: .omitted, time: .standard)) \(s)\n"
    if let h = FileHandle(forWritingAtPath: "/tmp/cbmac.log") { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
    else { try? line.write(toFile: "/tmp/cbmac.log", atomically: false, encoding: .utf8) }
}
try? FileManager.default.removeItem(atPath: "/tmp/cbmac.log")
let port = UInt16(CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "27300") ?? 27300
let sendMic = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] != "nomic" : true

var fd = socket(AF_INET, SOCK_STREAM, 0)
var addr = sockaddr_in(); addr.sin_family = sa_family_t(AF_INET); addr.sin_port = port.bigEndian; addr.sin_addr.s_addr = inet_addr("127.0.0.1")
let rc = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
log("connect rc=\(rc)")
guard rc == 0 else { exit(1) }
var one: Int32 = 1; setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, socklen_t(4))

let play16 = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
let wire16 = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!

// --- playback: the caller's voice, through a jitter buffer
final class Jitter {
    let lock = NSLock(); var ring = [Float](repeating: 0, count: 16000 * 2); var rd = 0, wr = 0, fill = 0
    var started = false; var underruns = 0, skipped = 0, maxFill = 0
    let startAt = 2400, cap = 8000, skipTo = 3200            // start at 150 ms; only if above 500 ms jump to 200 ms
    func push(_ v: [Float]) {
        lock.lock(); defer { lock.unlock() }
        for x in v { ring[wr] = x; wr = (wr + 1) % ring.count; fill += 1 }
        if fill > cap { let drop = fill - skipTo; rd = (rd + drop) % ring.count; fill -= drop; skipped += 1 }
        if fill > maxFill { maxFill = fill }
    }
    func pull(_ out: UnsafeMutablePointer<Float>, _ n: Int) {
        lock.lock(); defer { lock.unlock() }
        if !started { if fill >= startAt { started = true } else { for i in 0..<n { out[i] = 0 }; return } }
        if fill < n { underruns += 1; started = false; for i in 0..<n { out[i] = 0 }; return } // ran dry: rebuffer 100 ms in one go
        for i in 0..<n { out[i] = ring[rd]; rd = (rd + 1) % ring.count }
        fill -= n
    }
}
let jitter = Jitter()
let pe = AVAudioEngine()
let src = AVAudioSourceNode(format: play16) { _, _, frames, abl in
    let list = UnsafeMutableAudioBufferListPointer(abl)
    if let p = list[0].mData?.assumingMemoryBound(to: Float.self) { jitter.pull(p, Int(frames)) }
    return noErr
}
pe.attach(src); pe.connect(src, to: pe.mainMixerNode, format: play16)
try pe.start()
var rxBytes = 0, txBytes = 0
var agcGain: Float = 0.4
// Diagnostics: CB_RECORD=1 saves what the mic gave us (pre) and what we sent (post) to /tmp, for level/clipping analysis.
let recording = ProcessInfo.processInfo.environment["CB_RECORD"] == "1"
if recording { FileManager.default.createFile(atPath: "/tmp/sent_pre.pcm", contents: nil); FileManager.default.createFile(atPath: "/tmp/sent_post.pcm", contents: nil) }
let fPre = recording ? FileHandle(forWritingAtPath: "/tmp/sent_pre.pcm") : nil, fPost = recording ? FileHandle(forWritingAtPath: "/tmp/sent_post.pcm") : nil
var captureEngine: AVAudioEngine? // must outlive the setup closure or the mic stops
var rxSum = 0.0, rxCnt = 0

DispatchQueue.global().async {
    var buf = [UInt8](repeating: 0, count: 4096); var left = Data()
    while true {
        let n = read(fd, &buf, buf.count); if n <= 0 { log("socket closed (read \(n))"); exit(0) }
        left.append(contentsOf: buf[0..<n]); rxBytes += n
        let usable = left.count & ~1
        guard usable > 0 else { continue }
        var v = [Float](repeating: 0, count: usable / 2)
        left.withUnsafeBytes { raw in
            for i in 0..<(usable / 2) { let x = Float(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: i * 2, as: Int16.self))) / 32768; v[i] = x; rxSum += Double(x * x); rxCnt += 1 }
        }
        left.removeFirst(usable)
        jitter.push(v)
    }
}

// --- capture: Mac mic -> call uplink
if sendMic {
    AVCaptureDevice.requestAccess(for: .audio) { ok in
        log("mic permission \(ok)"); guard ok else { return }
        DispatchQueue.main.async {
            captureEngine = AVAudioEngine(); let ce = captureEngine!
            let inFmt = ce.inputNode.outputFormat(forBus: 0)
            guard let conv = AVAudioConverter(from: inFmt, to: wire16) else { log("no converter"); return }
            ce.inputNode.installTap(onBus: 0, bufferSize: 1024, format: inFmt) { buf, _ in
                guard let out = AVAudioPCMBuffer(pcmFormat: wire16, frameCapacity: 4096) else { return }
                var fed = false
                conv.convert(to: out, error: nil) { _, st in if fed { st.pointee = .noDataNow; return nil }; fed = true; st.pointee = .haveData; return buf }
                guard out.frameLength > 0, let p = out.int16ChannelData?[0] else { return }
                let cnt = Int(out.frameLength); let n = cnt * 2
                fPre?.write(Data(bytes: p, count: n)) // what the mic gave us, before gain
                var sum = 0.0; for i in 0..<cnt { let v = Double(p[i]) / 32768; sum += v * v }
                let rms = (sum / Double(cnt)).squareRoot()
                // Level control: aim for healthy speech (RMS ~0.10). Cut fast when loud, recover slowly, ignore silence.
                if rms > 0.004 {
                    let want = Float(min(max(0.10 / rms, 0.05), 3.0))
                    agcGain += (want - agcGain) * (want < agcGain ? 0.5 : 0.03)
                }
                for i in 0..<cnt { let x = Float(p[i]) / 32768 * agcGain; p[i] = Int16(tanh(x * 1.2) / 1.2 * 32000) } // soft limiter, no hard clipping
                fPost?.write(Data(bytes: p, count: n)) // what we send
                _ = write(fd, p, n); txBytes += n
            }
            do { try ce.start(); log("mic capture running, input format \(inFmt)") } catch { log("capture failed: \(error)") }
        }
    }
}

Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
    let rms = rxCnt > 0 ? (rxSum / Double(rxCnt)).squareRoot() : 0; rxSum = 0; rxCnt = 0
    log("rx=\(rxBytes)B tx=\(txBytes)B caller level=\(String(format: "%.3f", rms)) jitter fill max=\(jitter.maxFill * 1000 / 16000)ms underruns=\(jitter.underruns) skips=\(jitter.skipped) gain=\(String(format: "%.1f", agcGain))"); jitter.maxFill = 0
}
log("running (sendMic=\(sendMic))")
RunLoop.main.run()
