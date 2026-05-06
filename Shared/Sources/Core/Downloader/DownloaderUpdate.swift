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
            0x54, 0x8D, 0x53, 0x66, 0x8C, 0x2E, 0x12, 0xB3,
            0x4F, 0x15, 0xAA, 0x8A, 0x7D, 0x52, 0x90, 0x13,
            0x76, 0x91, 0x4E, 0x06, 0xAB, 0xCE, 0xE9, 0x42,
            0x92, 0xA9, 0x25, 0x73, 0x1F, 0xF1, 0x2A, 0x8E
        ])
        return try Curve25519.Signing.PublicKey(rawRepresentation: raw)
    }
}
