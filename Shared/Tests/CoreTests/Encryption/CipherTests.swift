@testable import Core
import CryptoKit
import XCTest

final class CipherTests: XCTestCase {
    func testRoundTrip() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = Data("hello world".utf8)
        let env = try Cipher.seal(plaintext, with: key)
        let decoded = try Cipher.open(env, with: key)
        XCTAssertEqual(decoded, plaintext)
    }

    func testWrongKeyFails() throws {
        let k1 = SymmetricKey(size: .bits256)
        let k2 = SymmetricKey(size: .bits256)
        let env = try Cipher.seal(Data("secret".utf8), with: k1)
        XCTAssertThrowsError(try Cipher.open(env, with: k2))
    }

    func testTamperedCiphertextFails() throws {
        let key = SymmetricKey(size: .bits256)
        let env = try Cipher.seal(Data("payload".utf8), with: key)
        var tampered = env.combined
        tampered[tampered.count / 2] ^= 0xFF
        XCTAssertThrowsError(try Cipher.open(Envelope(combined: tampered), with: key))
    }

    func testCombinedFormatHasNonceAndTag() throws {
        let key = SymmetricKey(size: .bits256)
        let env = try Cipher.seal(Data("x".utf8), with: key)
        XCTAssertEqual(env.combined.count, 12 + 1 + 16)
    }
}
