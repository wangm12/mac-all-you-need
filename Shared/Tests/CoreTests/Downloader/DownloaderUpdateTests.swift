@testable import Core
import CryptoKit
import XCTest

final class DownloaderUpdateTests: XCTestCase {
    func testVerifySignedManifest() throws {
        let priv = Curve25519.Signing.PrivateKey()
        let pub = priv.publicKey
        let manifest = try DownloaderUpdate.Manifest(
            tool: "yt-dlp", version: "2024.99.99",
            sha256: "abcd", url: XCTUnwrap(URL(string: "https://example.com/yt-dlp"))
        )
        let payload = try JSONEncoder().encode(manifest)
        let sig = try priv.signature(for: payload)
        let signed = DownloaderUpdate.Signed(payload: payload, signature: sig)
        let verified = try DownloaderUpdate.verify(signed: signed, publicKey: pub)
        XCTAssertEqual(verified.tool, "yt-dlp")
        XCTAssertEqual(verified.version, "2024.99.99")
    }

    func testRejectsTamperedPayload() throws {
        let priv = Curve25519.Signing.PrivateKey()
        let pub = priv.publicKey
        let manifest = try DownloaderUpdate.Manifest(
            tool: "yt-dlp", version: "v", sha256: "h", url: XCTUnwrap(URL(string: "https://x"))
        )
        let payload = try JSONEncoder().encode(manifest)
        let sig = try priv.signature(for: payload)
        var tampered = payload; tampered[0] ^= 0xFF
        XCTAssertThrowsError(
            try DownloaderUpdate.verify(signed: .init(payload: tampered, signature: sig), publicKey: pub)
        )
    }
}
