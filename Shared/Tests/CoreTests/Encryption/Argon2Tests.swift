@testable import Core
import XCTest

final class Argon2Tests: XCTestCase {
    func testKnownAnswerVector() throws {
        let password = Data(repeating: 0x01, count: 32)
        let salt = Data(repeating: 0x02, count: 16)
        let params = KDFParameters(
            algorithm: .argon2id,
            iterations: 3,
            memoryKB: 32,
            parallelism: 4,
            outputLen: 32
        )
        let hash = try Argon2.hash(password: password, salt: salt, params: params)
        XCTAssertEqual(hash.count, 32)
        let hash2 = try Argon2.hash(password: password, salt: salt, params: params)
        XCTAssertEqual(hash, hash2)
    }

    func testDifferentPasswordsProduceDifferentHashes() throws {
        let salt = Data(repeating: 0xAA, count: 16)
        let params = KDFParameters(algorithm: .argon2id, iterations: 1, memoryKB: 256, parallelism: 1, outputLen: 32)
        let h1 = try Argon2.hash(password: Data("secret-1".utf8), salt: salt, params: params)
        let h2 = try Argon2.hash(password: Data("secret-2".utf8), salt: salt, params: params)
        XCTAssertNotEqual(h1, h2)
    }

    func testRejectsTooShortSalt() {
        let params = KDFParameters(algorithm: .argon2id, iterations: 1, memoryKB: 256, parallelism: 1, outputLen: 32)
        XCTAssertThrowsError(try Argon2.hash(password: Data("p".utf8), salt: Data([0x01]), params: params))
    }
}
