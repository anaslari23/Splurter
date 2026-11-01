import AppKit
import CoreImage.CIFilterBuiltins
import CryptoKit
import Network

/// Mac end of the phone link: advertises over Bonjour, accepts encrypted TCP sessions from paired phones,
/// shows a pairing QR on demand, syncs the clipboard.
///
/// Handshake (phone→mac): ephPub(32) | mode(1: 0 = pair with QR token, 1 = reconnect) | staticPub(32).
/// Mac→phone: ephPub(32). Then both derive keys (see Crypto.swift) and exchange [len32 | AEAD] frames.
final class Link: ObservableObject {
    static let shared = Link()
    struct Device: Codable, Identifiable { let id: String; var name: String } // id = base64 static pubkey

    private final class Conn {
        let c: NWConnection; var s: Session; let peer: String; let pairing: Bool
        init(_ c: NWConnection, _ s: Session, _ peer: String, _ pairing: Bool) { self.c = c; self.s = s; self.peer = peer; self.pairing = pairing }
    }

    @Published var qr: NSImage?
    @Published var pairing = false { didSet { if pairing { refreshQR() } } }
    @Published var devices = Store.loadDevices()
    @Published var connectedName: String?
    @Published var phoneHost: String? // the phone's LAN address, used to pick the matching adb device for call audio
    struct Entry: Identifiable { let id = UUID(); let icon: String; let text: String; let time = Date() }
    @Published var activity: [Entry] = []
    struct Call { var state: String; var number: String; var name: String }
    @Published var call: Call?
    @Published var transfer: String?
    private var incoming: [UInt32: (h: FileHandle, url: URL)] = [:]

    private let q = DispatchQueue(label: "link")
    private let identity = Store.identity()
    private var token = Link.newToken()
    private var listener: NWListener?
    private var port: UInt16 = 0
    private var cur: Conn?
    private var trusted: Set<String>
    private var lastChange = NSPasteboard.general.changeCount

    private init() { trusted = Set(Store.loadDevices().map(\.id)) }

    private static func newToken() -> Data { Data((0..<16).map { _ in UInt8.random(in: 0...255) }) }

    func start() {
        let tcp = NWProtocolTCP.Options(); tcp.enableKeepalive = true; tcp.keepaliveIdle = 10
        guard let l = try? NWListener(using: NWParameters(tls: nil, tcp: tcp)) else { return }
        let fp = SHA256.hash(data: identity.publicKey.rawRepresentation).prefix(8).map { String(format: "%02x", $0) }.joined()
        l.service = NWListener.Service(type: "_splurter._tcp", txtRecord: NWTXTRecord(["id": fp]))
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        l.stateUpdateHandler = { [weak self] st in
            if case .ready = st { self?.port = l.port?.rawValue ?? 0; DispatchQueue.main.async { if self?.pairing == true { self?.refreshQR() } } }
        }
        l.start(queue: q); listener = l
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.pollPasteboard() }
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.q.async { self?.send(["t": "ping"]) } }
    }

    func sendMessage(_ o: [String: Any]) { q.async { self.send(o) } }

    func forget(_ id: String) {
        devices.removeAll { $0.id == id }; Store.save(devices)
        q.async { self.trusted.remove(id); if self.cur?.peer == id { self.drop(self.cur!) } }
    }

    // MARK: QR

    func refreshQR() {
        let payload: [String: Any] = ["v": 2, "host": Self.lanIP(), "port": Int(port),
                                      "key": identity.publicKey.rawRepresentation.base64EncodedString(),
                                      "tok": token.base64EncodedString()]
        let s = String(data: try! JSONSerialization.data(withJSONObject: payload), encoding: .utf8)!
        let f = CIFilter.qrCodeGenerator(); f.message = Data(s.utf8); f.correctionLevel = "M"
        let img = f.outputImage!.transformed(by: .init(scaleX: 10, y: 10))
        let rep = NSCIImageRep(ciImage: img); let ns = NSImage(size: rep.size); ns.addRepresentation(rep)
        qr = ns
    }

    // MARK: connection

    private func accept(_ c: NWConnection) {
        c.start(queue: q)
        if case .hostPort(let host, _) = c.endpoint { let h = "\(host)".split(separator: "%").first.map(String.init); DispatchQueue.main.async { self.phoneHost = h } }
        read(c, 65) { [weak self] hs in
            guard let self else { return }
            let hs = Data(hs)
            let mode = hs[32], peer = hs.suffix(32).base64EncodedString()
            guard mode == 0 || self.trusted.contains(peer) else { return c.cancel() } // unknown phone must present the QR token
            do {
                let eph = Curve25519.KeyAgreement.PrivateKey()
                let s = try Session(staticKey: self.identity, ephemeral: eph,
                                    peerEphemeral: try .init(rawRepresentation: hs.prefix(32)),
                                    peerStatic: try .init(rawRepresentation: hs.suffix(32)),
                                    salt: mode == 0 ? self.token : Data())
                let conn = Conn(c, s, peer, mode == 0)
                if let old = self.cur { old.c.cancel() }
                self.cur = conn
                c.send(content: eph.publicKey.rawRepresentation, completion: .contentProcessed { _ in })
                self.loop(conn)
            } catch { c.cancel() }
        }
    }

    private func loop(_ k: Conn) {
        read(k.c, 4) { [weak self] hdr in
            guard let self else { return }
            let len = Int(hdr.reduce(0) { $0 << 8 | UInt32($1) })
            guard len >= 16, len <= 1 << 20 else { return self.drop(k) }
            self.read(k.c, len) { body in
                guard let plain = try? k.s.open(body) else { return self.drop(k) }
                self.handle(plain, k); self.loop(k)
            }
        }
    }

    private func read(_ c: NWConnection, _ n: Int, _ cb: @escaping (Data) -> Void) {
        c.receive(minimumIncompleteLength: n, maximumLength: n) { d, _, _, _ in
            if let d, d.count == n { cb(d) } else { c.cancel(); self.q.async { if self.cur?.c === c { self.drop(self.cur!) } } }
        }
    }

    private func drop(_ k: Conn) {
        k.c.cancel()
        if cur === k {
            incoming.values.forEach { try? $0.h.close() }; incoming = [:]; cur = nil
            // A dropped link can swallow the phone's "call ended", so never keep showing a call across a disconnect.
            DispatchQueue.main.async { self.connectedName = nil; self.call = nil; CallPanel.shared.update(nil) }
        }
    }

    /// Frame type byte: 0 = JSON message, 1 = file chunk ([1][id:4 BE][data]). Must run on q (nonce order).
    private func sendFrame(_ plain: Data, done: (() -> Void)? = nil) {
        guard let k = cur, let ct = try? k.s.seal(plain) else { done?(); return }
        var len = UInt32(ct.count).bigEndian
        k.c.send(content: Data(bytes: &len, count: 4) + ct, completion: .contentProcessed { _ in done?() })
    }

    private func send(_ obj: [String: Any]) {
        guard let json = try? JSONSerialization.data(withJSONObject: obj) else { return }
        sendFrame(Data([0]) + json)
    }

    /// Streams a file to the phone in 192 KB chunks, waiting on each write so other messages interleave.
    /// ponytail: no progress bar / cancel; add when transfers of big files matter.
    func sendFile(_ url: URL) {
        DispatchQueue.global().async {
            guard self.q.sync(execute: { self.cur != nil }), let h = try? FileHandle(forReadingFrom: url) else { return }
            defer { try? h.close() }
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            let id = UInt32.random(in: 1...UInt32.max)
            DispatchQueue.main.async { self.transfer = "Sending \(url.lastPathComponent)…" }
            self.q.sync { self.send(["t": "file", "id": Int(id), "name": url.lastPathComponent, "size": size]) }
            let sem = DispatchSemaphore(value: 0)
            var hdr = Data([1]); hdr += withUnsafeBytes(of: id.bigEndian) { Data($0) }
            while let chunk = try? h.read(upToCount: 192 * 1024), !chunk.isEmpty {
                self.q.sync { self.sendFrame(hdr + chunk) { sem.signal() } }
                sem.wait()
            }
            self.q.sync { self.send(["t": "file_end", "id": Int(id)]) }
            DispatchQueue.main.async { self.transfer = nil; self.log("arrow.up.doc", "Sent \(url.lastPathComponent)") }
        }
    }

    private func receive(_ m: [String: Any], _ t: String) {
        guard let id = (m["id"] as? Int).map(UInt32.init(truncatingIfNeeded:)) else { return }
        if t == "file" {
            var name = URL(fileURLWithPath: m["name"] as? String ?? "file").lastPathComponent // strip any path from the peer's name
            if name.isEmpty || name == ".." { name = "file" }
            let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            var url = dir.appendingPathComponent(name), n = 1
            while FileManager.default.fileExists(atPath: url.path) {
                let u = URL(fileURLWithPath: name); n += 1
                url = dir.appendingPathComponent("\(u.deletingPathExtension().lastPathComponent) \(n)" + (u.pathExtension.isEmpty ? "" : ".\(u.pathExtension)"))
            }
            FileManager.default.createFile(atPath: url.path, contents: nil)
            if let h = try? FileHandle(forWritingTo: url) { incoming[id] = (h, url) }
            DispatchQueue.main.async { self.transfer = "Receiving \(url.lastPathComponent)…" }
        } else if let f = incoming.removeValue(forKey: id) {
            try? f.h.close()
            DispatchQueue.main.async { self.transfer = nil; Notifier.shared.received(f.url); self.log("arrow.down.doc", "Received \(f.url.lastPathComponent)") }
        }
    }

    // MARK: messages (run on q)

    private func handle(_ plain: Data, _ k: Conn) {
        let plain = Data(plain)
        if plain.first == 2 { Mirror.shared.feed(plain); return } // video frame
        if plain.first == 1 { // file chunk
            let id = plain[1..<5].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            try? incoming[id]?.h.write(contentsOf: plain.dropFirst(5)); return
        }
        guard let m = try? JSONSerialization.jsonObject(with: plain.dropFirst()) as? [String: Any], let t = m["t"] as? String else { return }
        switch t {
        case "hello":
            let name = m["name"] as? String ?? "Phone"
            if k.pairing { trusted.insert(k.peer); token = Self.newToken() } // first authenticated frame: remember this phone
            DispatchQueue.main.async {
                if k.pairing { self.devices.append(Device(id: k.peer, name: name)); Store.save(self.devices); self.pairing = false }
                self.connectedName = name
            }
            send(["t": "hello", "name": Host.current().localizedName ?? "Mac"])
        case "clip":
            guard let text = m["text"] as? String else { return }
            DispatchQueue.main.async {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
                self.lastChange = NSPasteboard.general.changeCount
                self.log("doc.on.clipboard", "Clipboard from phone: \(text.prefix(40))")
            }
        case "call":
            let c = Call(state: m["state"] as? String ?? "idle", number: m["number"] as? String ?? "", name: m["name"] as? String ?? "")
            DispatchQueue.main.async {
                if c.state == "ringing", self.call?.state != "ringing" { self.log("phone.arrow.down.left", "Incoming call \(c.name.isEmpty ? c.number : c.name)") }
                self.call = c.state == "idle" ? nil : c
                CallPanel.shared.update(self.call)
                CallAudio.shared.callChanged(c.state)
                Notifier.shared.call(c)
            }
        case "sms_sent": DispatchQueue.main.async { self.log("message.fill", "Text sent to \(m["to"] ?? "?")") }
        case "mirror_info":
            if let w = m["w"] as? Double, let h = m["h"] as? Double, h > 0 { DispatchQueue.main.async { Mirror.shared.aspect = w / h } }
        case "mirror_state": DispatchQueue.main.async { Mirror.shared.state = m["state"] as? String ?? "idle" }
        case "file", "file_end": receive(m, t)
        case "app_icon":
            if let pkg = m["pkg"] as? String, pkg.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" }), // it becomes a file name
               let png = (m["png"] as? String).flatMap({ Data(base64Encoded: $0) }) { try? png.write(to: Notifier.iconURL(pkg)) }
        case "notif": DispatchQueue.main.async { Notifier.shared.show(m) }
        case "notif_gone": if let id = m["id"] as? String { DispatchQueue.main.async { Notifier.shared.remove(id) } }
        default: break
        }
    }

    private func log(_ icon: String, _ text: String) { activity = Array((activity + [Entry(icon: icon, text: text)]).suffix(20)) }

    private func pollPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount
        guard let text = pb.string(forType: .string) else { return }
        q.async { self.send(["t": "clip", "text": text]) }
        log("doc.on.clipboard", "Clipboard sent to phone: \(text.prefix(40))")
    }

    static func lanIP() -> String {
        var ifa: UnsafeMutablePointer<ifaddrs>?; getifaddrs(&ifa); defer { freeifaddrs(ifa) }
        for p in sequence(first: ifa, next: { $0?.pointee.ifa_next }) {
            guard let i = p?.pointee, i.ifa_addr.pointee.sa_family == UInt8(AF_INET),
                  String(cString: i.ifa_name).hasPrefix("en") else { continue }
            var h = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(i.ifa_addr, socklen_t(i.ifa_addr.pointee.sa_len), &h, socklen_t(h.count), nil, 0, NI_NUMERICHOST)
            return String(cString: h)
        }
        return "127.0.0.1"
    }
}
