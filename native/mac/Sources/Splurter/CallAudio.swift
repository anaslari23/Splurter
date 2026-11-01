import AVFoundation
import Foundation

/// Two-way cellular call audio through the Mac. A helper running as the adb shell user (started over wireless
/// debugging) captures the caller (VOICE_DOWNLINK) and plays our voice into the call uplink (CALL_ASSISTANT usage);
/// this class starts it, connects to it over an adb-forwarded socket, and runs the Mac audio (see native/callbridge).
/// Audio on the wire is PCM16 mono 16 kHz both ways. Headphones are required: there is no echo cancellation.
final class CallAudio: ObservableObject {
    static let shared = CallAudio()

    enum Phase: Equatable { case idle, needsSetup(String), working(String), live, failed(String) }
    @Published var phase: Phase = .idle
    @Published var headphones = true

    private let work = DispatchQueue(label: "callaudio")
    private var helper: Process?
    private var fd: Int32 = -1
    private var forwardPort: Int?
    private var serial: String?
    private var playback: AVAudioEngine?
    private var capture: AVAudioEngine?
    private let jitter = Jitter()
    private var agcGain: Float = 0.4
    private var outSum = 0.0, outCnt = 0 // level we send, for the log
    private var txBytes = 0, rxBytes = 0, statsTimer: Timer?
    private var generation = 0 // bumps on every start/stop so a stale pipeline can't touch a newer one

    var isActive: Bool { if case .idle = phase { return false }; if case .needsSetup = phase { return false }; if case .failed = phase { return false }; return true }

    private func set(_ p: Phase) { log("phase -> \(p)"); DispatchQueue.main.async { self.phase = p } }

    /// Diagnostics for support: ~/Library/Application Support/Splurter/call-audio.log
    func log(_ s: String) {
        let f = Store.dir.appendingPathComponent("call-audio.log"), line = "\(Date().formatted(date: .omitted, time: .standard)) \(s)\n"
        if let h = try? FileHandle(forWritingTo: f) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() } else { try? line.write(to: f, atomically: false, encoding: .utf8) }
    }

    // MARK: control

    func start() {
        guard !isActive else { return }
        generation += 1; let gen = generation
        log("start requested, adb=\(Adb.shared.path ?? "none"), phoneHost=\(Link.shared.phoneHost ?? "none")")
        set(.working("Looking for your phone…"))
        work.async { self.runPipeline(gen) }
    }

    func stop() {
        generation += 1
        work.async { self.teardown(); self.set(.idle) }
    }

    /// Call from the main thread whenever the call state changes.
    func callChanged(_ state: String?) {
        if state == nil || state == "idle", isActive { stop() }
    }

    // MARK: pipeline

    private func runPipeline(_ gen: Int) {
        func alive() -> Bool { gen == generation }
        let adb = Adb.shared
        guard adb.path != nil else { return set(.needsSetup("adb is not installed")) }

        // 1. Find the phone over wireless debugging (prefer the one Splurter is already talking to).
        func discover() -> [String] {
            var found = adb.onlineSerials()
            if found.isEmpty {
                let svc = adb.services()
                self.log("no adb device online; mdns connect services: \(svc.connect.map(\.hostPort))")
                if let e = svc.connect.first(where: { $0.host == Link.shared.phoneHost }) ?? svc.connect.first, adb.connect(e) { found = adb.onlineSerials() }
            }
            return found
        }
        var serials = discover()
        if serials.isEmpty { // adb's server can go stale after the phone's wireless debugging drops: restart it once and look again
            set(.working("Reconnecting to your phone…")); self.log("restarting the adb server")
            adb.restartServer(); serials = discover()
        }
        guard let s = serials.first(where: { sr in Link.shared.phoneHost.map { sr.hasPrefix($0 + ":") } ?? false }) ?? serials.first else {
            return set(.needsSetup("Your phone isn't reachable for wireless debugging. Turn on Developer options, Wireless debugging, on the phone (same Wi-Fi as this Mac), or pair it in the setup."))
        }
        log("using adb device \(s)")
        serial = s; guard alive() else { return }

        // 2. Push the helper and scrcpy's server jar (the helper reuses scrcpy's shell-audio setup).
        set(.working("Starting the call-audio helper…"))
        guard let dex = Bundle.main.url(forResource: "bridge", withExtension: "dex"), let jar = Bundle.main.url(forResource: "scrcpy-server", withExtension: "jar") else {
            return set(.failed("The app is missing its call-audio helper files"))
        }
        for (src, dst) in [(dex.path, "/data/local/tmp/splurter-bridge.dex"), (jar.path, "/data/local/tmp/scrcpy-server.jar")] {
            let r = adb.run(["-s", s, "push", src, dst], timeout: 30)
            log("push \(src) -> \(dst): status \(r.status) \(r.output.prefix(100))")
            guard r.status == 0 else { return set(.failed("Could not copy the helper to the phone: \(r.output.prefix(120))")) }
        }

        // 3. Random socket name + token per session, so no other app can attach to the call audio.
        let name = "splurter_" + Self.random(8), token = Self.random(24)
        let fw = adb.run(["-s", s, "forward", "tcp:0", "localabstract:" + name])
        guard fw.status == 0, let port = Int(fw.output.trimmingCharacters(in: .whitespacesAndNewlines)) else { return set(.failed("adb forward failed: \(fw.output.prefix(120))")) }
        forwardPort = port; log("forward tcp:\(port) -> \(name)")

        // 4. Run the helper on the phone and wait until it is listening.
        let p = Process(); p.executableURL = URL(fileURLWithPath: adb.path!)
        p.arguments = ["-s", s, "shell", "CLASSPATH=/data/local/tmp/scrcpy-server.jar:/data/local/tmp/splurter-bridge.dex app_process / Bridge name=\(name) token=\(token) mute=1 wait=25"]
        let out = Pipe(); p.standardOutput = out; p.standardError = out
        let ready = DispatchSemaphore(value: 0); var failure: String?
        out.fileHandleForReading.readabilityHandler = { h in
            let text = String(data: h.availableData, encoding: .utf8) ?? ""
            if !text.isEmpty { self.log("helper: \(text.trimmingCharacters(in: .whitespacesAndNewlines))") }
            if text.contains("BRIDGE FAILED") { failure = text.split(separator: "\n").first(where: { $0.contains("FAILED") }).map(String.init) ?? "helper failed"; ready.signal() }
            if text.contains("listening") { ready.signal() }
        }
        p.terminationHandler = { _ in ready.signal() }
        do { try p.run() } catch { return set(.failed("Could not start the helper: \(error.localizedDescription)")) }
        helper = p
        guard ready.wait(timeout: .now() + 12) == .success, failure == nil, p.isRunning else { teardown(); return set(.failed(failure ?? "The helper didn't start. Is a call active?")) }
        guard alive() else { return teardown() }

        // 5. Connect, authenticate with the token, and start the Mac audio.
        guard connectSocket(port: port, token: token) else { teardown(); return set(.failed("Could not connect to the helper")) }
        AVCaptureDevice.requestAccess(for: .audio) { ok in
            self.work.async {
                guard ok else { self.teardown(); return self.set(.failed("Microphone access is off for Splurter (System Settings, Privacy, Microphone)")) }
                guard alive() else { return self.teardown() }
                do { try self.startEngines() } catch { self.teardown(); return self.set(.failed("Audio engine failed: \(error.localizedDescription)")) }
                self.set(.live)
                DispatchQueue.main.async { self.statsTimer?.invalidate(); self.statsTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in self.log("stats: sent \(self.txBytes)B received \(self.rxBytes)B gain=\(String(format: "%.2f", self.agcGain)) sentLevel=\(String(format: "%.3f", self.takeOutLevel())) \(self.jitter.summary())") } }
                self.readLoop(gen)
            }
        }
    }

    private func connectSocket(port: Int, token: String) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0); guard sock >= 0 else { return false }
        var a = sockaddr_in(); a.sin_family = sa_family_t(AF_INET); a.sin_port = UInt16(port).bigEndian; a.sin_addr.s_addr = inet_addr("127.0.0.1")
        let rc = withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard rc == 0 else { close(sock); return false }
        var one: Int32 = 1; setsockopt(sock, IPPROTO_TCP, TCP_NODELAY, &one, 4)
        let t = Array(token.utf8); guard write(sock, t, t.count) == t.count else { close(sock); return false }
        fd = sock; return true
    }

    private func readLoop(_ gen: Int) {
        var buf = [UInt8](repeating: 0, count: 4096); var left = Data()
        while gen == generation {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break } // phone/adb went away, or we closed it
            left.append(contentsOf: buf[0..<n]); rxBytes += n
            let usable = left.count & ~1; guard usable > 0 else { continue }
            var v = [Float](repeating: 0, count: usable / 2)
            left.withUnsafeBytes { raw in for i in 0..<(usable / 2) { v[i] = Float(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: i * 2, as: Int16.self))) / 32768 } }
            left.removeFirst(usable); jitter.push(v)
        }
        if gen == generation { teardown(); set(.idle) }
    }

    // MARK: audio

    private func startEngines() throws {
        let play16 = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let wire16 = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
        jitter.reset()

        let pe = AVAudioEngine()
        let src = AVAudioSourceNode(format: play16) { [jitter] _, _, frames, abl in
            if let p = UnsafeMutableAudioBufferListPointer(abl)[0].mData?.assumingMemoryBound(to: Float.self) { jitter.pull(p, Int(frames)) }
            return noErr
        }
        pe.attach(src); pe.connect(src, to: pe.mainMixerNode, format: play16)
        try pe.start(); playback = pe
        var ready: UInt8 = 1; _ = write(fd, &ready, 1) // tells the helper to start capturing the caller now (before this, nothing queues up)

        // macOS voice processing chopped speech and can't run with playback on macOS 27, so it stays off.
        let ce = AVAudioEngine(); let inFmt = ce.inputNode.outputFormat(forBus: 0)
        guard let conv = AVAudioConverter(from: inFmt, to: wire16) else { throw NSError(domain: "audio", code: 1, userInfo: [NSLocalizedDescriptionKey: "no converter"]) }
        let sock = fd
        ce.inputNode.installTap(onBus: 0, bufferSize: 1024, format: inFmt) { [weak self] buf, _ in
            guard let self, let out = AVAudioPCMBuffer(pcmFormat: wire16, frameCapacity: 4096) else { return }
            var fed = false
            conv.convert(to: out, error: nil) { _, st in if fed { st.pointee = .noDataNow; return nil }; fed = true; st.pointee = .haveData; return buf }
            guard out.frameLength > 0, let p = out.int16ChannelData?[0] else { return }
            let cnt = Int(out.frameLength)
            self.levelControl(p, cnt)
            _ = write(sock, p, cnt * 2); self.txBytes += cnt * 2
        }
        try ce.start(); capture = ce
    }

    /// Aim for healthy speech (RMS ~0.12): cut fast when loud, recover slowly, never boost silence or room noise, and
    /// soft-limit instead of clipping. Up to 12x for quiet mics (a MacBook's built-in mic arrives at ~0.02 RMS);
    /// earbud mics already sit near 0.30 and get cut instead (plain boosting clipped 56% of their speech).
    private func levelControl(_ p: UnsafeMutablePointer<Int16>, _ n: Int) {
        var sum = 0.0; for i in 0..<n { let v = Double(p[i]) / 32768; sum += v * v }
        let rms = (sum / Double(n)).squareRoot()
        if rms > 0.008 { let want = Float(min(max(0.12 / rms, 0.05), 12.0)); agcGain += (want - agcGain) * (want < agcGain ? 0.5 : 0.04) }
        var osum = 0.0
        for i in 0..<n { let o = tanh(Float(p[i]) / 32768 * agcGain * 1.2) / 1.2; p[i] = Int16(o * 32000); osum += Double(o * o) }
        outSum += osum; outCnt += n
    }

    private func takeOutLevel() -> Double { defer { outSum = 0; outCnt = 0 }; return outCnt > 0 ? (outSum / Double(outCnt)).squareRoot() : 0 }

    // MARK: audio route advice

    /// Plain-language hint about the current mic/headphones, since they decide how good a call sounds.
    func routeAdvice() -> String? {
        func dev(_ sel: AudioObjectPropertySelector) -> (name: String, transport: UInt32)? {
            var id = AudioDeviceID(0); var sz = UInt32(MemoryLayout<AudioDeviceID>.size)
            var a = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &sz, &id) == noErr, id != 0 else { return nil }
            var nm: Unmanaged<CFString>?; var s2 = UInt32(MemoryLayout<CFString?>.size)
            var na = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            AudioObjectGetPropertyData(id, &na, 0, nil, &s2, &nm)
            var t = UInt32(0); var s3 = UInt32(4)
            var ta = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            AudioObjectGetPropertyData(id, &ta, 0, nil, &s3, &t)
            return ((nm?.takeRetainedValue() as String?) ?? "?", t)
        }
        guard let i = dev(kAudioHardwarePropertyDefaultInputDevice), let o = dev(kAudioHardwarePropertyDefaultOutputDevice) else { return nil }
        let builtin = kAudioDeviceTransportTypeBuiltIn, bt = kAudioDeviceTransportTypeBluetooth, ble = kAudioDeviceTransportTypeBluetoothLE
        if o.transport == builtin { return "Use headphones: your Mac's speakers would echo back into the call." }
        var tips: [String] = []
        if o.transport == bt || o.transport == ble { tips.append("\(o.name) is Bluetooth, which adds about a quarter second of delay.") }
        if i.transport == builtin { tips.append("Your voice uses the built-in mic, so it will be quieter. Wired earbuds with a mic sound best.") }
        return tips.isEmpty ? nil : tips.joined(separator: " ")
    }

    private func teardown() {
        capture?.inputNode.removeTap(onBus: 0); capture?.stop(); capture = nil
        playback?.stop(); playback = nil
        if fd >= 0 { shutdown(fd, SHUT_RDWR); close(fd); fd = -1 }
        DispatchQueue.main.async { self.statsTimer?.invalidate(); self.statsTimer = nil }
        if let p = helper, p.isRunning { p.terminate() }; helper = nil
        if let s = serial {
            let adb = Adb.shared
            if let port = forwardPort { adb.run(["-s", s, "forward", "--remove", "tcp:\(port)"]) }
            adb.run(["-s", s, "shell", "pkill -f Bridge"]) // makes sure the phone mic is unmuted again (the helper restores on exit)
        }
        forwardPort = nil
    }

    private static func random(_ n: Int) -> String { (0..<n).map { _ in String(format: "%x", Int.random(in: 0..<16)) }.joined() }
}

/// Playback jitter buffer with drift compensation. Wireless adb and Android's capture deliver audio in bursts, and the
/// phone's capture clock runs ~4% fast against ours, so a fixed-rate buffer eventually overflows (gaps) or runs dry.
/// Instead we steer the buffer toward ~150 ms by playing a little faster or slower (linear interpolation, at most
/// +8% / -2%), which is inaudible, and only skip ahead in an emergency.
final class Jitter {
    private let lock = NSLock()
    private var ring = [Float](repeating: 0, count: 16000 * 2); private var rd = 0, wr = 0, fill = 0, started = false
    private var pos = 0.0                                 // fractional read position, in samples past `rd`
    private var underruns = 0, skips = 0, maxFill = 0
    private let startAt = 2400, target = 2400.0, hardCap = 16000
    func reset() { lock.lock(); rd = 0; wr = 0; fill = 0; started = false; pos = 0; underruns = 0; skips = 0; maxFill = 0; lock.unlock() }
    func summary() -> String { lock.lock(); defer { lock.unlock() }; let t = "jitter fill max \(maxFill * 1000 / 16000)ms underruns \(underruns) skips \(skips)"; maxFill = 0; return t }
    func push(_ v: [Float]) {
        lock.lock(); defer { lock.unlock() }
        for x in v { ring[wr] = x; wr = (wr + 1) % ring.count; fill += 1 }
        if fill > hardCap { let drop = fill - Int(target); rd = (rd + drop) % ring.count; fill -= drop; skips += 1 } // emergency only (> 1 s)
        if fill > maxFill { maxFill = fill }
    }
    func pull(_ out: UnsafeMutablePointer<Float>, _ n: Int) {
        lock.lock(); defer { lock.unlock() }
        if !started { if fill >= startAt { started = true; pos = 0 } else { for i in 0..<n { out[i] = 0 }; return } }
        let err = Double(fill) - target                    // + means too full: play faster
        let ratio = 1.0 + min(max(err * 2e-5, -0.02), 0.08)
        let need = Int((Double(n) * ratio).rounded(.up)) + 2
        if fill < need { started = false; underruns += 1; for i in 0..<n { out[i] = 0 }; return }
        for i in 0..<n {
            let k = Int(pos); let f = Float(pos - Double(k))
            let a = ring[(rd + k) % ring.count], b = ring[(rd + k + 1) % ring.count]
            out[i] = a + (b - a) * f
            pos += ratio
        }
        let used = Int(pos); pos -= Double(used); rd = (rd + used) % ring.count; fill -= used
    }
}
