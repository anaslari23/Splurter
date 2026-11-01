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
    enum Phase: Equatable { case idle, working(String), live, failed(String) }
    struct Shape { var w = 1080.0, h = 2424.0, radius = 0.0; var hole: (x: Double, y: Double, r: Double)? }

    @Published var phase = Phase.idle
    @Published var shape = Shape()
    private let work = DispatchQueue(label: "fullmirror")
    private let ctl = DispatchQueue(label: "fullmirror.control")
    private var gen = 0
    private var serial: String?, forwardPort: Int?, server: Process?
    private var vfd: Int32 = -1, cfd: Int32 = -1
    private var frame = (w: 0, h: 0)
    private var lastInput = Date.distantPast
    private var panelOff = false

    private func set(_ p: Phase) { DispatchQueue.main.async { self.phase = p } }
    private func log(_ s: String) { CallAudio.shared.log("mirror: " + s) }

    func start() {
        guard phase == .idle || { if case .failed = phase { return true }; return false }() else { return }
        gen += 1; let g = gen; set(.working("Connecting to your phone…"))
        work.async { self.pipeline(g) }
    }

    func stop() { gen += 1; work.async { self.teardown() }; set(.idle) }

    private func pipeline(_ g: Int) {
        let adb = Adb.shared
        guard adb.path != nil else { return set(.failed("adb isn't set up yet. Open “Call audio setup…” once to pair this Mac.")) }
        guard let s = adb.findPhone(log: log, reconnecting: { self.set(.working("Reconnecting to your phone…")) }) else {
            return set(.failed("Your phone isn't reachable for wireless debugging. Turn on Developer options, Wireless debugging (same Wi-Fi), or pair it in “Call audio setup…”."))
        }
        serial = s; panelOff = false; frame = (0, 0); guard g == gen else { return }
        guard let jar = Bundle.main.url(forResource: "scrcpy-server", withExtension: "jar") else { return set(.failed("The app is missing its phone-mirror helper")) }
        let r = adb.run(["-s", s, "push", jar.path, "/data/local/tmp/scrcpy-server.jar"], timeout: 30)
        guard r.status == 0 else { return set(.failed("Could not copy the helper to the phone: \(r.output.prefix(100))")) }
        readShape(s)

        let scid = String(format: "%08x", Int.random(in: 1..<0x7fff_ffff))
        let fw = adb.run(["-s", s, "forward", "tcp:0", "localabstract:scrcpy_" + scid])
        guard fw.status == 0, let port = Int(fw.output.trimmingCharacters(in: .whitespacesAndNewlines)) else { return set(.failed("adb forward failed")) }
        forwardPort = port

        let p = Process(); p.executableURL = URL(fileURLWithPath: adb.path!)
        p.arguments = ["-s", s, "shell", "CLASSPATH=/data/local/tmp/scrcpy-server.jar app_process / com.genymobile.scrcpy.Server 5.0.1 scid=\(scid) log_level=info tunnel_forward=true audio=false control=true cleanup=false max_size=1920 video_bit_rate=16000000 max_fps=120"]
        let out = Pipe(); p.standardOutput = out; p.standardError = out
        let up = DispatchSemaphore(value: 0)
        out.fileHandleForReading.readabilityHandler = { h in
            let t = String(data: h.availableData, encoding: .utf8) ?? ""
            if !t.isEmpty { self.log("server: " + t.trimmingCharacters(in: .whitespacesAndNewlines)) }
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
        readVideo(g)
        if g == gen { teardown(); set(.idle) }
    }

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

    private func readVideo(_ g: Int) {
        guard readExact(1 + 64 + 4) != nil else { return log("no video header") }
        var n = 0
        while g == gen {
            guard let h = readExact(12) else { break }
            if h[0] & 0x80 != 0 { // session header: new frame size (first frame, or the phone rotated)
                let w = Int(h[4]) << 24 | Int(h[5]) << 16 | Int(h[6]) << 8 | Int(h[7]), hh = Int(h[8]) << 24 | Int(h[9]) << 16 | Int(h[10]) << 8 | Int(h[11])
                frame = (w, hh); log("frame size \(w)x\(hh)")
                DispatchQueue.main.async { if hh > 0 { Mirror.shared.aspect = CGFloat(w) / CGFloat(hh) }; self.phase = .live }
                continue
            }
            let size = Int(h[8]) << 24 | Int(h[9]) << 16 | Int(h[10]) << 8 | Int(h[11])
            guard size > 0, size < 8_000_000, let payload = readExact(size) else { break }
            let kind: UInt8 = h[0] & 0x40 != 0 ? 0 : h[0] & 0x20 != 0 ? 1 : 2
            Mirror.shared.feed(Data([2, kind]) + payload); n += 1
        }
        log("video ended after \(n) packets")
    }

    private func teardown() {
        if panelOff, cfd >= 0 { var on: [UInt8] = [10, 1]; _ = write(cfd, &on, 2); Thread.sleep(forTimeInterval: 0.15) } // panel back on before the helper goes
        panelOff = false
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
    private func readShape(_ s: String) {
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
        if action == 0 { wakeIfIdle(); blankPanel() }
        let px = Int(min(max(x, 0), 1) * Double(frame.w - 1)), py = Int(min(max(y, 0), 1) * Double(frame.h - 1))
        send([2, action] + Self.be(-1, 8) + Self.be(px, 4) + Self.be(py, 4) + Self.be(frame.w, 2) + Self.be(frame.h, 2)
             + Self.be(action == 1 ? 0 : 0xffff, 2) + Self.be(1, 4) + Self.be(action == 1 ? 0 : 1, 4))
    }

    func scroll(_ x: Double, _ y: Double, dy: Double) {
        let px = Int(x * Double(frame.w - 1)), py = Int(y * Double(frame.h - 1))
        send([3] + Self.be(px, 4) + Self.be(py, 4) + Self.be(frame.w, 2) + Self.be(frame.h, 2) + Self.be(0, 2)
             + Self.be(Int(max(-1, min(1, dy / 16)) * 32767), 2) + Self.be(0, 4))
    }

    func key(_ code: Int) { send([0, 0] + Self.be(code, 4) + Self.be(0, 4) + Self.be(0, 4)); send([0, 1] + Self.be(code, 4) + Self.be(0, 4) + Self.be(0, 4)); lastInput = Date() }
    func text(_ s: String) { let b = Array(s.utf8); send([1] + Self.be(b.count, 4) + b); lastInput = Date() }
    static let home = 3, back = 4, recents = 187, power = 26, wakeup = 224, enter = 66, del = 67

    /// Like iPhone Mirroring, using the phone from the Mac shouldn't light up or scroll the phone itself: once you start interacting,
    /// the phone's panel is switched off (the phone stays awake and keeps being mirrored). It comes back when the window closes.
    private func blankPanel() { guard !panelOff else { return }; panelOff = true; log("phone panel off (cfd \(cfd))"); send([10, 0]) }

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
                let k = geo.size.width / m.shape.w, r = m.shape.radius * k
                ZStack {
                    Color.black
                    TouchLayer(layer: mirror.layer)
                    if let h = m.shape.hole { Circle().fill(.black).frame(width: h.r * 2 * k, height: h.r * 2 * k).position(x: h.x * k, y: h.y * k).allowsHitTesting(false) }
                    if m.phase != .live { status }
                }
                .clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: r, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 2))
            }
            .aspectRatio(mirror.aspect, contentMode: .fit)
            HStack(spacing: 18) {
                bar("chevron.left", "Back") { m.key(FullMirror.back) }
                bar("circle", "Home") { m.key(FullMirror.home) }
                bar("square.on.square", "Recent apps") { m.key(FullMirror.recents) }
                bar("sun.max", "Wake") { m.key(FullMirror.wakeup) }
                bar("power", "Lock / sleep") { m.key(FullMirror.power) }
            }
            .padding(.horizontal, 14).padding(.vertical, 6).background(.regularMaterial, in: Capsule())
        }
        .padding(10)
        .background(WindowClear())
        .frame(minWidth: 260, minHeight: 520)
        .onAppear { m.start() }
        .onDisappear { m.stop() }
    }

    private func bar(_ icon: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon) }.buttonStyle(.plain).help(help).disabled(m.phase != .live)
    }

    @ViewBuilder private var status: some View {
        VStack(spacing: 10) {
            switch m.phase {
            case .failed(let e):
                Text(e).font(.callout).foregroundStyle(.white).multilineTextAlignment(.center)
                Button("Try again") { m.start() }.buttonStyle(.borderedProminent)
                Button("Use basic mirror instead") { // the older screen-share route: needs a tap on the phone, works without adb
                    Mirror.shared.state = "waiting"; openWindow(id: "mirror"); Link.shared.sendMessage(["t": "mirror_start"])
                }.buttonStyle(.link)
            case .working(let t): ProgressView().controlSize(.large); Text(t).font(.callout).foregroundStyle(.white)
            default: ProgressView().controlSize(.large)
            }
        }.padding(24)
    }
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
    override func mouseDown(with e: NSEvent) { let p = norm(e); FullMirror.shared.touch(0, p.0, p.1) }
    override func mouseDragged(with e: NSEvent) { let p = norm(e); FullMirror.shared.touch(2, p.0, p.1) }
    override func mouseUp(with e: NSEvent) { let p = norm(e); FullMirror.shared.touch(1, p.0, p.1) }
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
        case 53: FullMirror.shared.key(FullMirror.back)
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
