import Foundation

/// Finds and drives `adb` (Android platform-tools) for the call-audio helper. Nothing here touches the phone
/// unless the user starts call audio or runs the setup screen.
final class Adb {
    static let shared = Adb()

    struct Endpoint: Hashable { let name: String; let host: String; let port: Int; var hostPort: String { "\(host):\(port)" } }

    private let installDir = Store.dir.appendingPathComponent("platform-tools")

    /// An existing adb: ours (downloaded), Android Studio's SDK, or Homebrew's.
    var path: String? {
        [installDir.appendingPathComponent("adb").path, NSHomeDirectory() + "/Library/Android/sdk/platform-tools/adb",
         "/opt/homebrew/bin/adb", "/usr/local/bin/adb"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Runs adb with a timeout and returns stdout+stderr.
    @discardableResult
    func run(_ args: [String], timeout: TimeInterval = 15) -> (status: Int32, output: String) {
        guard let path else { return (-1, "adb not found") }
        let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return (-1, "\(error)") }
        var data = Data(); let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { data = pipe.fileHandleForReading.readDataToEndOfFile(); done.signal() }
        if done.wait(timeout: .now() + timeout) == .timedOut { p.terminate(); _ = done.wait(timeout: .now() + 2); return (-2, "timed out") }
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    /// Wireless-debugging services the phone advertises: the pairing one (only while its dialog is open) and the connect one.
    func services() -> (pairing: [Endpoint], connect: [Endpoint]) {
        var pairing: [Endpoint] = [], connect: [Endpoint] = []
        for line in run(["mdns", "services"]).output.split(separator: "\n") {
            let f = line.split(separator: "\t").map(String.init)
            guard f.count >= 3, let colon = f[2].lastIndex(of: ":"), let port = Int(f[2][f[2].index(after: colon)...]) else { continue }
            let e = Endpoint(name: f[0], host: String(f[2][..<colon]), port: port)
            if f[1].contains("pairing") { pairing.append(e) } else if f[1].contains("connect") { connect.append(e) }
        }
        return (pairing, connect)
    }

    func pair(_ e: Endpoint, code: String) -> (ok: Bool, message: String) {
        let r = run(["pair", e.hostPort, code], timeout: 25)
        return (r.output.contains("Successfully paired"), r.output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func connect(_ e: Endpoint) -> Bool {
        let r = run(["connect", e.hostPort], timeout: 15).output
        return r.contains("connected to") || r.contains("already connected")
    }

    /// ip:port serials that are online. adb also lists the mDNS alias of the same phone; those are skipped.
    func onlineSerials() -> [String] {
        run(["devices"]).output.split(separator: "\n").compactMap { l in
            let f = l.split(separator: "\t").map(String.init)
            return f.count == 2 && f[1] == "device" && f[0].contains(":") && !f[0].hasPrefix("adb-") ? f[0] : nil
        }
    }

    /// adb's background server can keep a dead view of the phone; restarting it is harmless.
    func restartServer() { run(["kill-server"], timeout: 10); run(["start-server"], timeout: 15); Thread.sleep(forTimeInterval: 5) } // mDNS needs a few seconds to rediscover

    /// Google's own platform-tools build, downloaded only when the user asks. ~13 MB.
    func downloadPlatformTools() async throws {
        let url = URL(string: "https://dl.google.com/android/repository/platform-tools-latest-darwin.zip")!
        let (tmp, resp) = try await URLSession.shared.download(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw NSError(domain: "adb", code: 1, userInfo: [NSLocalizedDescriptionKey: "download failed"]) }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-o", "-q", tmp.path, "-d", Store.dir.path]; try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0, path != nil else { throw NSError(domain: "adb", code: 2, userInfo: [NSLocalizedDescriptionKey: "could not unpack platform-tools"]) }
    }
}
