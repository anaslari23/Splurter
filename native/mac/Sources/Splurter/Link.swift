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
    @Published var log: [String] = []

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
        if cur === k { cur = nil; DispatchQueue.main.async { self.connectedName = nil } }
    }

    private func send(_ obj: [String: Any]) {
        guard let k = cur, let json = try? JSONSerialization.data(withJSONObject: obj), let ct = try? k.s.seal(json) else { return }
        var len = UInt32(ct.count).bigEndian
        k.c.send(content: Data(bytes: &len, count: 4) + ct, completion: .contentProcessed { _ in })
    }

    // MARK: messages (run on q)

    private func handle(_ data: Data, _ k: Conn) {
        guard let m = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let t = m["t"] as? String else { return }
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
                self.log(" ← \(text.prefix(40))")
            }
        default: break
        }
    }

    private func log(_ s: String) { log = Array((log + [s]).suffix(5)) }

    private func pollPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount
        guard let text = pb.string(forType: .string) else { return }
        q.async { self.send(["t": "clip", "text": text]) }
        log(" → \(text.prefix(40))")
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
