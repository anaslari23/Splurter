import CryptoKit
import Foundation

/// Persistent identity + trusted phones, in ~/Library/Application Support/Splurter.
/// ponytail: plain 0600 files; move the private key to Keychain once the app is properly signed.
enum Store {
    static let dir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Splurter")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    static func identity() -> Curve25519.KeyAgreement.PrivateKey {
        let f = dir.appendingPathComponent("identity.key")
        if let raw = try? Data(contentsOf: f), let k = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw) { return k }
        let k = Curve25519.KeyAgreement.PrivateKey()
        try? k.rawRepresentation.write(to: f)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: f.path)
        return k
    }

    static func loadDevices() -> [Link.Device] {
        var seen = Set<String>() // re-pairing the same phone used to append a duplicate entry
        return ((try? JSONDecoder().decode([Link.Device].self, from: Data(contentsOf: dir.appendingPathComponent("devices.json")))) ?? []).filter { seen.insert($0.id).inserted }
    }

    static func save(_ d: [Link.Device]) {
        try? JSONEncoder().encode(d).write(to: dir.appendingPathComponent("devices.json"))
    }
}
