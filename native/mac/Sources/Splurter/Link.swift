import AppKit
import CoreImage.CIFilterBuiltins
import CryptoKit
import Network

/// Mac end of the phone link: shows a pairing QR, accepts one encrypted TCP session, syncs clipboard.
final class Link: ObservableObject {
    @Published var qr: NSImage?
    @Published var status = "Starting…"
    @Published var log: [String] = []

    private let q = DispatchQueue(label: "link")
    private let staticKey = Curve25519.KeyAgreement.PrivateKey()
    private let token = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
    private var listener: NWListener?
    private var conn: NWConnection?
    private var session: Session?
    private var lastChange = NSPasteboard.general.changeCount

    func start() {
        do { listener = try NWListener(using: .tcp) } catch { status = "listen failed: \(error)"; return }
        listener?.newConnectionHandler = { [weak self] c in self?.accept(c) }
        listener?.stateUpdateHandler = { [weak self] st in
            guard let self, case .ready = st, let port = self.listener?.port?.rawValue else { return }
            self.showQR(port: port)
        }
        listener?.start(queue: q)
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.pollPasteboard() }
    }

    private func showQR(port: UInt16) {
        let payload: [String: Any] = ["v": 1, "host": Self.lanIP(), "port": Int(port),
                                      "key": staticKey.publicKey.rawRepresentation.base64EncodedString(),
                                      "tok": token.base64EncodedString()]
        let s = String(data: try! JSONSerialization.data(withJSONObject: payload), encoding: .utf8)!
        let f = CIFilter.qrCodeGenerator(); f.message = Data(s.utf8); f.correctionLevel = "M"
        let img = f.outputImage!.transformed(by: .init(scaleX: 10, y: 10))
        let rep = NSCIImageRep(ciImage: img); let ns = NSImage(size: rep.size); ns.addRepresentation(rep)
        DispatchQueue.main.async { self.qr = ns; self.status = "Scan with the Splurter app (\(Self.lanIP()):\(port))" }
    }

    // MARK: connection

    private func accept(_ c: NWConnection) {
        conn?.cancel(); conn = c; session = nil
        c.stateUpdateHandler = { [weak self] st in if case .failed = st { self?.drop() } }
        c.start(queue: q)
        // Handshake: phone sends its 32-byte ephemeral pubkey, we answer with ours.
        read(c, 32, framed: false) { [weak self] peer in
            guard let self else { return }
            do {
                let eph = Curve25519.KeyAgreement.PrivateKey()
                let peerKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peer)
                self.session = try Session(staticKey: self.staticKey, ephemeral: eph, peerEphemeral: peerKey, token: self.token)
                c.send(content: eph.publicKey.rawRepresentation, completion: .contentProcessed { _ in })
                self.loop(c)
            } catch { self.drop() }
        }
    }

    private func loop(_ c: NWConnection) {
        read(c, 4, framed: false) { [weak self] hdr in
            guard let self else { return }
            let len = Int(hdr.reduce(0) { $0 << 8 | UInt32($1) })
            guard len >= 16, len <= 1 << 20 else { return self.drop() }
            self.read(c, len, framed: false) { body in
                guard var s = self.session, let plain = try? s.open(body) else { return self.drop() }
                self.session = s
                self.handle(plain); self.loop(c)
            }
        }
    }

    private func read(_ c: NWConnection, _ n: Int, framed: Bool, _ cb: @escaping (Data) -> Void) {
        c.receive(minimumIncompleteLength: n, maximumLength: n) { [weak self] d, _, _, err in
            guard let d, d.count == n else { self?.drop(); return }
            cb(d)
        }
    }

    private func drop() {
        conn?.cancel(); conn = nil; session = nil
        DispatchQueue.main.async { self.status = "Phone disconnected — rescan to pair" }
    }

    private func send(_ obj: [String: Any]) {
        guard let c = conn, var s = session, let json = try? JSONSerialization.data(withJSONObject: obj),
              let ct = try? s.seal(json) else { return }
        session = s
        var len = UInt32(ct.count).bigEndian
        c.send(content: Data(bytes: &len, count: 4) + ct, completion: .contentProcessed { _ in })
    }

    // MARK: messages

    private func handle(_ data: Data) {
        guard let m = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let t = m["t"] as? String else { return }
        DispatchQueue.main.async {
            switch t {
            case "hello":
                self.status = "Connected to \(m["name"] as? String ?? "phone")"; self.log.append("hello from \(m["name"] ?? "?")")
                self.send(["t": "hello", "name": Host.current().localizedName ?? "Mac"])
            case "clip":
                guard let text = m["text"] as? String else { return }
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
                self.lastChange = NSPasteboard.general.changeCount
                self.log.append("← phone: \(text.prefix(60))")
            default: break
            }
        }
    }

    private func pollPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount
        guard let text = pb.string(forType: .string) else { return }
        q.async { self.send(["t": "clip", "text": text]) }
        log.append("→ phone: \(text.prefix(60))")
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
