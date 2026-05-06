import CryptoKit
import Foundation

public enum DownloaderUpdateError: Error { case signatureInvalid }

public enum DownloaderUpdate {
    public struct Manifest: Codable, Equatable {
        public let tool: String
        public let version: String
        public let sha256: String
        public let url: URL
    }

    public struct Signed: Codable {
        public let payload: Data
        public let signature: Data
        public init(payload: Data, signature: Data) {
            self.payload = payload
            self.signature = signature
        }
    }

    public static func verify(signed: Signed, publicKey: Curve25519.Signing.PublicKey) throws -> Manifest {
        guard publicKey.isValidSignature(signed.signature, for: signed.payload) else {
            throw DownloaderUpdateError.signatureInvalid
        }
        return try JSONDecoder().decode(Manifest.self, from: signed.payload)
    }

    public static func embeddedPublicKey() throws -> Curve25519.Signing.PublicKey {
        let raw = Data([
            0x54, 0x8d, 0x53, 0x66, 0x8c, 0x2e, 0x12, 0xb3,
            0x4f, 0x15, 0xaa, 0x8a, 0x7d, 0x52, 0x90, 0x13,
            0x76, 0x91, 0x4e, 0x06, 0xab, 0xce, 0xe9, 0x42,
            0x92, 0xa9, 0x25, 0x73, 0x1f, 0xf1, 0x2a, 0x8e,
        ])
        return try Curve25519.Signing.PublicKey(rawRepresentation: raw)
    }
}
