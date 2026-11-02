import AppKit
import SwiftUI

/// "Full phone" mirror, like iPhone Mirroring: runs scrcpy's server on the phone over wireless debugging (the same adb route as call
/// audio), so it works while the phone is locked or showing its always-on display, needs no prompt on the phone, and injects real
/// touch/keys. The window takes the phone's shape (corner radius, camera punch-hole), read from the phone itself.
///
/// Wire format (scrcpy server, forward tunnel): video socket = dummy byte, 64-byte name, 4-byte codec, then packets:
/// a session header [0x80.. u32][w u32][h u32] or a packet [pts|flags u64: 0x40 config, 0x20 key][size u32][H.264 Annex-B].
/// The second connection is the control socket.
final class FullMirror: ObservableObject {
    static let shared = FullMirror()
    enum Phase: Equatable { case idle, working(String), live, failed(String), needsUnlock }
    struct Shape { var w = 1080.0, h = 2424.0, radius = 0.0; var hole: (x: Double, y: Double, r: Double)? }

    /// own: apps run on a second, virtual screen of the phone shown here, so the phone itself stays free (its real screen is untouched).
    /// mirror: shows what the phone's own screen shows (lock screen, always-on display), and blanks the phone while you use it.
    enum Mode: String { case own, mirror }
    @Published var mode = Mode(rawValue: UserDefaults.standard.string(forKey: "phoneMode2") ?? "") ?? .own
    func setMode(_ m: Mode) { guard m != mode else { return }; mode = m; UserDefaults.standard.set(m.rawValue, forKey: "phoneMode2"); stop(); DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.start() } }
    @Published var phase = Phase.idle
    @Published var shape = Shape()
    private let work = DispatchQueue(label: "fullmirror")
    private let ctl = DispatchQueue(label: "fullmirror.control")
    private var gen = 0
    private var serial: String?, forwardPort: Int?, server: Process?
    private var vfd: Int32 = -1, cfd: Int32 = -1
    private var frame = (w: 0, h: 0)
    private var lastInput = Date.distantPast
    private var displayId: Int?
    private var holding = false // the phone was locked: kept awake with its panel off so the virtual screen keeps running

    /// Own-screen mode needs a home screen: Android's launcher only offers a dock on a second display, so the phone app ships its own
    /// (PhoneHomeActivity). Apps open on top of it and Back returns to it, so this display is never empty.
    func home() {
        guard let s = serial, let d = displayId else { return }
        DispatchQueue.global().async { let r = Adb.shared.run(["-s", s, "shell", "am start --display \(d) -n app.splurter/.PhoneHomeActivity"]); self.log("home: \(r.output.suffix(80))") }
    }

    private func set(_ p: Phase) { DispatchQueue.main.async { self.phase = p } }
    private func log(_ s: String) { CallAudio.shared.log("mirror: " + s) }

    func start() {
        guard phase == .idle || phase == .needsUnlock || { if case .failed = phase { return true }; return false }() else { return }
        gen += 1; let g = gen; set(.working("Connecting to your phone…")); Mirror.shared.reset()
        work.async { self.pipeline(g) }
    }

    func stop() { gen += 1; work.async { self.teardown() }; set(.idle) }

    private func pipeline(_ g: Int) {
        let adb = Adb.shared
        guard adb.path != nil else { return set(.failed("adb isn't set up yet. Open “Call audio setup…” once to pair this Mac.")) }
        guard let s = adb.findPhone(log: log, reconnecting: { self.set(.working("Reconnecting to your phone…")) }) else {
            return set(.failed("Your phone isn't reachable for wireless debugging. Turn on Developer options, Wireless debugging (same Wi-Fi), or pair it in “Call audio setup…”."))
        }
        serial = s; frame = (0, 0); holding = false; restoreTimeout(s) // a crash during an earlier lock-hold would have left the screen timeout raised guard g == gen else { return }
        guard let jar = Bundle.main.url(forResource: "scrcpy-server", withExtension: "jar") else { return set(.failed("The app is missing its phone-mirror helper")) }
        let r = adb.run(["-s", s, "push", jar.path, "/data/local/tmp/scrcpy-server.jar"], timeout: 30)
        guard r.status == 0 else { return set(.failed("Could not copy the helper to the phone: \(r.output.prefix(100))")) }
        let sh = readShape(s)
        // Like iPhone Mirroring: ask for one unlock, then connect. After that the phone can be locked again; the Mac keeps its own screen.
        if mode == .own {
            var polls = 0
            while g == gen, Self.asleep(s) || Self.keyguardUp(s) {
                if polls == 0 { adb.run(["-s", s, "shell", "input keyevent KEYCODE_WAKEUP"]) }
                set(.needsUnlock); Thread.sleep(forTimeInterval: 1.5); polls += 1
                if polls > 200 { return set(.failed("Your phone stayed locked. Unlock it and press Try again.")) }
            }
            guard g == gen else { return }
            set(.working("Connecting to your phone…"))
        }
        // A sleeping phone sends no frames: wake it (harmless if awake). If it's PIN-locked the user still has to unlock it once.
        if Self.asleep(s) { set(.working("Waking your phone…")); adb.run(["-s", s, "shell", "input keyevent KEYCODE_WAKEUP"]); Thread.sleep(forTimeInterval: 1.0) }
        // A helper left running by an earlier session (app quit, phone went offline) can hold the phone's video encoder: clear it first.
        adb.run(["-s", s, "shell", "pkill -f com.genymobile.scrcpy"])
        for line in adb.run(["-s", s, "forward", "--list"]).output.split(separator: "\n") {
            let f = line.split(separator: " ").map(String.init)
            if f.count >= 3, f[2].hasPrefix("localabstract:scrcpy_") { adb.run(["-s", s, "forward", "--remove", f[1]]) }
        }

        let scid = String(format: "%08x", Int.random(in: 1..<0x7fff_ffff))
        let fw = adb.run(["-s", s, "forward", "tcp:0", "localabstract:scrcpy_" + scid])
        guard fw.status == 0, let port = Int(fw.output.trimmingCharacters(in: .whitespacesAndNewlines)) else { return set(.failed("adb forward failed")) }
        forwardPort = port

        // The virtual screen is rendered and encoded by the phone, so keep it light: 720 px wide is plenty for a Mac window (~660 px on a
        // Retina display) and renders ~2x cheaper than the phone's full 1080. The dpi is scaled to match, so apps lay out as on the phone.
        let ownW = 720, ownH = Int((720 * sh.h / sh.w).rounded()) / 2 * 2, ownDpi = 280
        let p = Process(); p.executableURL = URL(fileURLWithPath: adb.path!)
        p.arguments = ["-s", s, "shell", "CLASSPATH=/data/local/tmp/scrcpy-server.jar app_process / com.genymobile.scrcpy.Server 5.0.1 scid=\(scid) log_level=info tunnel_forward=true audio=false control=true cleanup=false max_size=1920 video_bit_rate=\(mode == .own ? 8_000_000 : 16_000_000) max_fps=\(mode == .own ? 60 : 120) video_codec_options=i-frame-interval:int=2,bitrate-mode:int=2,latency:int=1,priority:int=0" + (mode == .own ? " new_display=\(ownW)x\(ownH)/\(ownDpi) vd_system_decorations=false" : "")]
        let out = Pipe(); p.standardOutput = out; p.standardError = out
        let up = DispatchSemaphore(value: 0)
        out.fileHandleForReading.readabilityHandler = { h in
            let t = String(data: h.availableData, encoding: .utf8) ?? ""
            if !t.isEmpty { self.log("server: " + t.trimmingCharacters(in: .whitespacesAndNewlines)) }
            if let r = t.range(of: #"\(id=(\d+)\)"#, options: .regularExpression) { self.displayId = Int(t[r].filter(\.isNumber)); if self.mode == .own { self.home() } } // the virtual display's id
            if t.contains("Device:") { up.signal() }
        }
        p.terminationHandler = { _ in up.signal() }
        do { try p.run() } catch { return set(.failed("Could not start the helper")) }
        server = p
        guard up.wait(timeout: .now() + 12) == .success, p.isRunning else { teardown(); return set(.failed("The phone's helper didn't start")) }
        Thread.sleep(forTimeInterval: 0.3)
        vfd = Self.connectLocal(port); guard vfd >= 0 else { teardown(); return set(.failed("Could not connect to the phone")) }
        cfd = Self.connectLocal(port)
        guard g == gen else { return teardown() }
        watchWakefulness(s, g)
        let gotVideo = readVideo(g)
        if g == gen { teardown(); set(gotVideo ? .idle : Self.asleep(s) || Self.keyguardUp(s) ? .needsUnlock : .failed("The phone didn't start its screen in time. It may be short of memory: close some apps or restart the phone, then Try again.")) }
    }

    /// Locking the phone puts it to sleep, and a sleeping phone stops the virtual screen (the Mac window goes black). So the first time
    /// the phone falls asleep during a session we wake it and switch its panel off: it looks locked, but keeps running the Mac's screen.
    /// Pressing the power button again (it falls asleep once more) hands the phone back: panel on, normal behaviour.
    private func watchWakefulness(_ s: String, _ g: Int) {
        DispatchQueue.global().async {
            let adb = Adb.shared; var last = "", quietUntil = Date.distantPast
            while g == self.gen {
                let w = adb.run(["-s", s, "shell", "dumpsys power | grep -m1 mWakefulness="], timeout: 10).output.trimmingCharacters(in: .whitespacesAndNewlines)
                if w != last { self.log("phone \(w)") }
                let asleepNow = !w.isEmpty && !w.contains("Awake")
                if asleepNow, !last.isEmpty, !last.contains("Dozing"), !last.contains("Asleep"), self.mode == .own, Date() > quietUntil {
                    if self.holding { self.release(s) } else { self.hold(s) }
                    quietUntil = Date().addingTimeInterval(2.5)
                }
                last = w
                Thread.sleep(forTimeInterval: 0.7)
            }
        }
    }

    private func hold(_ s: String) {
        log("phone locked: holding it awake, panel off")
        holding = true
        let orig = Adb.shared.run(["-s", s, "shell", "settings get system screen_off_timeout"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        if Int(orig) != nil, Int(orig)! < 1_000_000_000 { UserDefaults.standard.set(orig, forKey: "origScreenTimeout") } // restored on release, session end, or next start
        Adb.shared.run(["-s", s, "shell", "settings put system screen_off_timeout 2147483647; input keyevent KEYCODE_WAKEUP"])
        send([10, 0])
    }

    private func release(_ s: String) {
        log("power button again: giving the phone back")
        holding = false; send([10, 1]); restoreTimeout(s)
        Adb.shared.run(["-s", s, "shell", "input keyevent KEYCODE_WAKEUP"])
    }

    private func restoreTimeout(_ s: String) {
        if let t = UserDefaults.standard.string(forKey: "origScreenTimeout") {
            Adb.shared.run(["-s", s, "shell", "settings put system screen_off_timeout \(t)"]); UserDefaults.standard.removeObject(forKey: "origScreenTimeout")
        }
    }

    private static func asleep(_ s: String) -> Bool { !Adb.shared.run(["-s", s, "shell", "dumpsys power | grep mWakefulness="]).output.contains("Awake") }
    private static func keyguardUp(_ s: String) -> Bool { Adb.shared.run(["-s", s, "shell", "dumpsys window | grep isKeyguardShowing"]).output.contains("isKeyguardShowing=true") }

    private static func connectLocal(_ port: Int) -> Int32 {
        let sock = socket(AF_INET, SOCK_STREAM, 0); guard sock >= 0 else { return -1 }
        var a = sockaddr_in(); a.sin_family = sa_family_t(AF_INET); a.sin_port = UInt16(port).bigEndian; a.sin_addr.s_addr = inet_addr("127.0.0.1")
        let rc = withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        if rc != 0 { close(sock); return -1 }
        var one: Int32 = 1; setsockopt(sock, IPPROTO_TCP, TCP_NODELAY, &one, 4)
        return sock
    }

    private func readExact(_ n: Int) -> [UInt8]? {
        var buf = [UInt8](repeating: 0, count: n); var got = 0
        while got < n { let r = buf.withUnsafeMutableBytes { read(vfd, $0.baseAddress! + got, n - got) }; if r <= 0 { return nil }; got += r }
        return buf
    }

    private func readVideo(_ g: Int) -> Bool {
        // A phone that is out of memory can take a minute to start the helper (or never does): give up after 25 s instead of hanging on black.
        var tv = timeval(tv_sec: 25, tv_usec: 0); setsockopt(vfd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        guard readExact(1 + 64 + 4) != nil else { log("no video header"); return false }
        tv = timeval(tv_sec: 0, tv_usec: 0); setsockopt(vfd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var n = 0, bytes = 0, tick = Date(), last = Date(), maxGap = 0.0, pkts = 0 // per-2 s video stats for the log: lag shows up here
        while g == gen {
            guard let h = readExact(12) else { break }
            let nowT = Date(); maxGap = max(maxGap, nowT.timeIntervalSince(last)); last = nowT
            if nowT.timeIntervalSince(tick) >= 2 {
                log("video: \(pkts / 2) pkt/s, \(bytes / 2048) KB/s, longest wait \(Int(maxGap * 1000)) ms"); tick = nowT; pkts = 0; bytes = 0; maxGap = 0
            }
            if h[0] & 0x80 != 0 { // session header: new frame size (first frame, or the phone rotated)
                let w = Int(h[4]) << 24 | Int(h[5]) << 16 | Int(h[6]) << 8 | Int(h[7]), hh = Int(h[8]) << 24 | Int(h[9]) << 16 | Int(h[10]) << 8 | Int(h[11])
                frame = (w, hh); log("frame size \(w)x\(hh)")
                DispatchQueue.main.async {
                    if hh > 0 { Mirror.shared.aspect = CGFloat(w) / CGFloat(hh) }
                    self.phase = .live
                }
                continue
            }
            let size = Int(h[8]) << 24 | Int(h[9]) << 16 | Int(h[10]) << 8 | Int(h[11])
            guard size > 0, size < 8_000_000, let payload = readExact(size) else { break }
            let kind: UInt8 = h[0] & 0x40 != 0 ? 0 : h[0] & 0x20 != 0 ? 1 : 2
            Mirror.shared.feed(Data([2, kind]) + payload); n += 1; pkts += 1; bytes += size
            if n == 1 { DispatchQueue.main.async { if self.phase != .live { self.phase = .live } } } // a picture is arriving: drop the "connecting" overlay
        }
        log("video ended after \(n) packets")
        return n > 0
    }

    private func teardown() {
        if holding, cfd >= 0 { var on: [UInt8] = [10, 1]; _ = write(cfd, &on, 2); Thread.sleep(forTimeInterval: 0.15) } // panel back on before the helper goes
        if holding || UserDefaults.standard.string(forKey: "origScreenTimeout") != nil, let s = serial { restoreTimeout(s) }
        holding = false
        for f in [vfd, cfd] where f >= 0 { shutdown(f, SHUT_RDWR); close(f) }
        vfd = -1; cfd = -1
        if let p = server, p.isRunning { p.terminate() }; server = nil
        if let s = serial {
            if let port = forwardPort { Adb.shared.run(["-s", s, "forward", "--remove", "tcp:\(port)"]) }
            Adb.shared.run(["-s", s, "shell", "pkill -f com.genymobile.scrcpy"])
        }
        forwardPort = nil
    }

    /// Corner radius and camera hole straight from the phone, so the window matches its shape.
    private func readShape(_ s: String) -> Shape {
        let d = Adb.shared.run(["-s", s, "shell", "dumpsys display; wm size"]).output
        func first(_ pattern: String) -> [String]? {
            guard let re = try? NSRegularExpression(pattern: pattern), let m = re.firstMatch(in: d, range: NSRange(d.startIndex..., in: d)) else { return nil }
            return (1..<m.numberOfRanges).map { String(d[Range(m.range(at: $0), in: d)!]) }
        }
        var sh = Shape()
        if let v = first(#"Physical size: (\d+)x(\d+)"#), let w = Double(v[0]), let h = Double(v[1]) { sh.w = w; sh.h = h }
        if let v = first(#"position=TopLeft, radius=(\d+)"#), let r = Double(v[0]) { sh.radius = r }
        if let v = first(#"cutoutSpec=\{m ([\d.]+),([\d.]+) a ([\d.]+),"#), let x = Double(v[0]), let y = Double(v[1]), let r = Double(v[2]) { sh.hole = (x - r, y, r) }
        log("shape \(sh)")
        DispatchQueue.main.async { self.shape = sh }
        return sh
    }

    // MARK: input (control socket, scrcpy message types)

    /// One message per call, written whole: a short write would desync scrcpy's message stream and freeze all input.
    private func send(_ bytes: [UInt8]) {
        ctl.async {
            var off = 0
            while off < bytes.count, self.cfd >= 0 {
                let n = bytes.withUnsafeBytes { write(self.cfd, $0.baseAddress! + off, bytes.count - off) }
                if n <= 0 { if n < 0, errno == EINTR || errno == EAGAIN { continue }; return }
                off += n
            }
        }
    }
    private static func be(_ v: Int, _ n: Int) -> [UInt8] { (0..<n).map { UInt8(truncatingIfNeeded: v >> (8 * (n - 1 - $0))) } }

    /// action: 0 down, 1 up, 2 move. x/y are 0...1 of the video frame.
    func touch(_ action: UInt8, _ x: Double, _ y: Double) {
        guard cfd >= 0, frame.w > 0, frame.h > 0 else { return } // not connected yet: a click then must not count as "using the phone"
        if action == 0, mode == .mirror { wakeIfIdle() }
        let px = Int(min(max(x, 0), 1) * Double(frame.w - 1)), py = Int(min(max(y, 0), 1) * Double(frame.h - 1))
        // A finger (-2), not the mouse (-1): many apps (anything built with Jetpack Compose, for one) ignore scrcpy's synthetic mouse clicks
        // and don't scroll on a mouse drag. Real touch works everywhere.
        send([2, action] + Self.be(-2, 8) + Self.be(px, 4) + Self.be(py, 4) + Self.be(frame.w, 2) + Self.be(frame.h, 2)
             + Self.be(action == 1 ? 0 : 0xffff, 2) + Self.be(0, 4) + Self.be(0, 4))
    }

    func scroll(_ x: Double, _ y: Double, dy: Double) {
        let px = Int(x * Double(frame.w - 1)), py = Int(y * Double(frame.h - 1))
        send([3] + Self.be(px, 4) + Self.be(py, 4) + Self.be(frame.w, 2) + Self.be(frame.h, 2) + Self.be(0, 2)
             + Self.be(Int(max(-1, min(1, dy / 16)) * 32767), 2) + Self.be(0, 4))
    }

    func key(_ code: Int) { send([0, 0] + Self.be(code, 4) + Self.be(0, 4) + Self.be(0, 4)); send([0, 1] + Self.be(code, 4) + Self.be(0, 4) + Self.be(0, 4)); lastInput = Date() }
    func text(_ s: String) { let b = Array(s.utf8); send([1] + Self.be(b.count, 4) + b); lastInput = Date() }
    static let home = 3, back = 4, recents = 187, power = 26, wakeup = 224, enter = 66, del = 67

    func back() { log("back"); key(Self.back) }

    /// Touching a dozing phone (always-on display) wouldn't wake it; a WAKEUP key first is harmless when it's awake.
    private func wakeIfIdle() { if Date().timeIntervalSince(lastInput) > 10 { key(Self.wakeup) }; lastInput = Date() }
}

// MARK: - Window

struct FullMirrorView: View {
    @ObservedObject var m = FullMirror.shared
    @ObservedObject var mirror = Mirror.shared
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                let land = mirror.aspect > 1 // an app rotated the virtual screen: the camera hole moves to the left edge, like a phone turned sideways
                let k = geo.size.width / (land ? m.shape.h : m.shape.w), r = m.shape.radius * k
                ZStack {
                    Color.black
                    TouchLayer(layer: mirror.layer)
                    if let h = m.shape.hole { Circle().fill(.black).frame(width: h.r * 2 * k, height: h.r * 2 * k).position(x: (land ? h.y : h.x) * k, y: (land ? h.x : h.y) * k).allowsHitTesting(false) }
                    if m.phase != .live { status }
                }
                .clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: r, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 2))
            }
            .aspectRatio(mirror.aspect, contentMode: .fit)
            HStack(spacing: 22) {
                HStack(spacing: 7) { // close / minimise, as on any Mac window
                    windowDot(.red, "xmark", "Close") { NSApp.windows.first { $0.title == "Phone" }?.close() }
                    windowDot(.yellow, "minus", "Minimise") { NSApp.windows.first { $0.title == "Phone" }?.miniaturize(nil) }
                }
                Image(systemName: "line.3.horizontal").foregroundStyle(.secondary).help("Drag to move the window (or hold ⌥ and drag the phone)")
                bar("chevron.left", "Back (Esc)") { m.back() }
                if m.mode == .own {
                    bar("house", "Home") { m.home() }
                } else {
                    bar("circle", "Home") { m.key(FullMirror.home) }
                    bar("square.on.square", "Recent apps") { m.key(FullMirror.recents) }
                    bar("sun.max", "Wake") { m.key(FullMirror.wakeup) }
                    bar("power", "Lock / sleep") { m.key(FullMirror.power) }
                }
            }
            .contextMenu { // rarely needed, so out of the way of the navigation buttons
                Button(m.mode == .own ? "Show the phone's own screen instead" : "Use the phone's apps on this Mac") { m.setMode(m.mode == .own ? .mirror : .own) }
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(DragArea().clipShape(Capsule())) // the bar's empty space drags the window too
            .background(.regularMaterial, in: Capsule())
        }
        .padding(14)
        .background(DragArea()) // margins and the bar's empty space move the window
        .background(RoundedRectangle(cornerRadius: 36, style: .continuous).fill(Color.black.opacity(0.22))) // a faint panel: fully transparent pixels let clicks fall through to the windows behind
        .background(WindowClear())
        .frame(minWidth: 260, minHeight: 260)
        .onChange(of: mirror.aspect) { _, a in fitWindow(a) }
        .onAppear { m.start() }
        .onDisappear { m.stop() }
    }

    /// Keeps the window phone-shaped when an app rotates the virtual screen (portrait <-> landscape).
    private func fitWindow(_ a: CGFloat) {
        guard let w = NSApp.windows.first(where: { $0.title == "Phone" }) else { return }
        let long = max(w.frame.width, w.frame.height - 70), pad: CGFloat = 20, bar: CGFloat = 50
        let size = a > 1 ? NSSize(width: long + pad, height: long / a + pad + bar) : NSSize(width: long * a + pad, height: long + pad + bar)
        var f = w.frame; f.origin.y += f.height - size.height; f.size = size
        w.setFrame(f, display: true, animate: true)
    }

    private func windowDot(_ c: Color, _ icon: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 7, weight: .black)).foregroundStyle(.black.opacity(0.55)).frame(width: 13, height: 13).background(c, in: Circle()) }
            .buttonStyle(.plain).help(help)
    }

    private func bar(_ icon: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon) }.buttonStyle(.plain).help(help).disabled(m.phase != .live)
    }

    @ViewBuilder private var status: some View {
        VStack(spacing: 12) {
            switch m.phase {
            case .needsUnlock:
                Image(systemName: "lock.iphone").font(.system(size: 44)).foregroundStyle(.white.opacity(0.9))
                Text("Unlock your phone").font(.title3.bold()).foregroundStyle(.white)
                Text(m.mode == .own ? "Unlock your phone once to start. It connects by itself, and then you can lock the phone again and keep using it here."
                                                            : "It's locked or asleep, so it can't send its screen yet. Wake and unlock it once, then press Try again.")
                    .font(.callout).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
                if m.mode == .mirror { Button("Try again") { m.start() }.buttonStyle(.borderedProminent).controlSize(.large) }
                else { ProgressView().controlSize(.small) }
                Button("Use basic mirror instead") { basicMirror() }.buttonStyle(.link)
            case .failed(let e):
                Image(systemName: "exclamationmark.triangle").font(.system(size: 36)).foregroundStyle(.yellow)
                Text(e).font(.callout).foregroundStyle(.white).multilineTextAlignment(.center)
                Button("Try again") { m.start() }.buttonStyle(.borderedProminent)
                Button("Use basic mirror instead") { basicMirror() }.buttonStyle(.link) // the older screen-share route: needs a tap on the phone, works without adb
            case .working(let t): ProgressView().controlSize(.large); Text(t).font(.callout).foregroundStyle(.white)
            default: ProgressView().controlSize(.large)
            }
        }.padding(28)
    }

    private func basicMirror() { Mirror.shared.state = "waiting"; openWindow(id: "mirror"); Link.shared.sendMessage(["t": "mirror_start"]) }
}

/// Dragging here moves the window (the window is transparent and borderless, so it has no title bar to grab).
struct DragArea: NSViewRepresentable {
    final class V: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with e: NSEvent) { window?.performDrag(with: e) }
    }
    func makeNSView(context: Context) -> V { V() }
    func updateNSView(_ v: V, context: Context) {}
}

/// Makes the hosting window transparent and borderless-looking so only the phone shape and its bar show.
struct WindowClear: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.isOpaque = false; w.backgroundColor = .clear; w.titlebarAppearsTransparent = true; w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true; w.hasShadow = false // only the phone shape and its bar; ⌘W closes
            for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { w.standardWindowButton(b)?.isHidden = true }
        }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {}
}

/// Hosts the video layer; mouse becomes touch (down/move/up), wheel becomes scroll, typing becomes text.
final class TouchView: NSView {
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false } // else dragging on the phone drags the window (the window is movable by its background)
    override func viewDidMoveToWindow() { window?.makeFirstResponder(self) }
    private func norm(_ e: NSEvent) -> (Double, Double) {
        let p = convert(e.locationInWindow, from: nil)
        return (min(max(Double(p.x / bounds.width), 0), 1), min(max(Double(1 - p.y / bounds.height), 0), 1))
    }
    private var movingWindow = false
    override func mouseDown(with e: NSEvent) {
        if e.modifierFlags.contains(.option) { movingWindow = true; window?.performDrag(with: e); return } // ⌥-drag moves the window
        movingWindow = false; let p = norm(e); FullMirror.shared.touch(0, p.0, p.1)
    }
    override func mouseDragged(with e: NSEvent) { guard !movingWindow else { return }; let p = norm(e); FullMirror.shared.touch(2, p.0, p.1) }
    override func mouseUp(with e: NSEvent) { if movingWindow { movingWindow = false; return }; let p = norm(e); FullMirror.shared.touch(1, p.0, p.1) }
    /// Trackpad scrolling becomes a real finger drag (down, moves, up), so the phone's own fling and 120 Hz smoothness apply.
    /// Mouse wheels (no gesture phases) still use discrete wheel events.
    private var finger: (x: Double, y: Double)?
    override func scrollWheel(with e: NSEvent) {
        guard e.hasPreciseScrollingDeltas, e.phase != [] || e.momentumPhase != [] else {
            let p = norm(e); FullMirror.shared.scroll(p.0, p.1, dy: Double(e.scrollingDeltaY) / (e.hasPreciseScrollingDeltas ? 8 : 1)); return
        }
        if e.momentumPhase != [] { return } // the phone continues the fling itself after the finger lifts
        let dy = Double(e.scrollingDeltaY / bounds.height), dx = Double(e.scrollingDeltaX / bounds.width)
        if e.phase.contains(.began) || (finger == nil && e.phase.contains(.changed)) { let p = norm(e); finger = p; FullMirror.shared.touch(0, p.0, p.1) }
        if var f = finger {
            f.x = min(max(f.x + dx, 0), 1); f.y = min(max(f.y + dy, 0), 1); finger = f
            if !e.phase.contains(.began) { FullMirror.shared.touch(2, f.x, f.y) }
        }
        if e.phase.contains(.ended) || e.phase.contains(.cancelled), let f = finger { FullMirror.shared.touch(1, f.x, f.y); finger = nil }
    }
    override func keyDown(with e: NSEvent) {
        switch e.keyCode {
        case 51: FullMirror.shared.key(FullMirror.del)
        case 36: FullMirror.shared.key(FullMirror.enter)
        case 53: FullMirror.shared.back()
        default:
            if !e.modifierFlags.contains(.command), let s = e.characters, !s.isEmpty, s.unicodeScalars.allSatisfy({ $0.value >= 32 }) { FullMirror.shared.text(s) }
        }
    }
}

struct TouchLayer: NSViewRepresentable {
    let layer: CALayer
    func makeNSView(context: Context) -> TouchView { let v = TouchView(); v.layer = layer; v.wantsLayer = true; return v }
    func updateNSView(_ v: TouchView, context: Context) {}
}
