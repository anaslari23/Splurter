import CryptoKit
import Foundation

/// One direction pair of AEAD keys with implicit counter nonces (12 bytes: 4 zero + 8 BE counter).
struct Session {
    let sendKey: SymmetricKey
    let recvKey: SymmetricKey
    private var sendN: UInt64 = 0
    private var recvN: UInt64 = 0

    /// Mac side. Four DHs bind both sides' static and ephemeral keys; the salt is the single-use
    /// QR token when pairing and empty when reconnecting. Key material: first 32 bytes = phone→mac.
    init(staticKey: Curve25519.KeyAgreement.PrivateKey, ephemeral: Curve25519.KeyAgreement.PrivateKey,
         peerEphemeral: Curve25519.KeyAgreement.PublicKey, peerStatic: Curve25519.KeyAgreement.PublicKey,
         salt: Data) throws {
        var ikm = Data()
        for (k, p) in [(staticKey, peerEphemeral), (ephemeral, peerEphemeral), (staticKey, peerStatic), (ephemeral, peerStatic)] {
            ikm += try k.sharedSecretFromKeyAgreement(with: p).withUnsafeBytes { Data($0) }
        }
        let okm = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: ikm), salt: salt,
                                         info: Data("splurter/v2".utf8), outputByteCount: 64)
        let raw = okm.withUnsafeBytes { Data($0) }
        recvKey = SymmetricKey(data: raw.prefix(32))
        sendKey = SymmetricKey(data: raw.suffix(32))
    }

    private static func nonce(_ c: UInt64) -> ChaChaPoly.Nonce {
        var b = Data(count: 4)
        withUnsafeBytes(of: c.bigEndian) { b.append(contentsOf: $0) }
        return try! ChaChaPoly.Nonce(data: b)
    }

    mutating func seal(_ d: Data) throws -> Data {
        defer { sendN += 1 }
        let box = try ChaChaPoly.seal(d, using: sendKey, nonce: Self.nonce(sendN))
        return box.ciphertext + box.tag
    }

    mutating func open(_ d: Data) throws -> Data {
        guard d.count >= 16 else { throw CryptoKitError.incorrectParameterSize }
        defer { recvN += 1 }
        let box = try ChaChaPoly.SealedBox(nonce: Self.nonce(recvN), ciphertext: d.dropLast(16), tag: d.suffix(16))
        return try ChaChaPoly.open(box, using: recvKey)
    }
}
