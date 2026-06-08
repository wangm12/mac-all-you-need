@testable import Core
import CryptoKit
import XCTest

final class KeyManagerTests: XCTestCase {
    var manager: KeyManager!

    override func setUp() {
        super.setUp()
        manager = KeyManager(keychain: InMemoryKeychain())
    }

    func testDeviceKeyIsGeneratedOnceAndStable() throws {
        let k1 = try manager.deviceKey()
        let k2 = try manager.deviceKey()
        XCTAssertEqual(k1.withUnsafeBytes { Data($0) }, k2.withUnsafeBytes { Data($0) })
        XCTAssertEqual(k1.bitCount, 256)
    }

    func testConcurrentDeviceKeyCreationConvergesOnOneKey() throws {
        let sharedKeychain = InMemoryKeychain()
        let lock = NSLock()
        var collected: [Data] = []
        let group = DispatchGroup()
        for _ in 0 ..< 8 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                let manager = KeyManager(keychain: sharedKeychain)
                guard let key = try? manager.deviceKey().withUnsafeBytes({ Data($0) }) else { return }
                lock.lock()
                collected.append(key)
                lock.unlock()
            }
        }
        group.wait()
        XCTAssertEqual(collected.count, 8)
        let canonical = try KeyManager(keychain: sharedKeychain).deviceKey().withUnsafeBytes { Data($0) }
        for key in collected {
            XCTAssertEqual(key, canonical)
        }
    }

    func testSyncKeyDerivedFromPassphrase() throws {
        let salt = Data(repeating: 0xAB, count: 16)
        let params = KDFParameters(algorithm: .argon2id, iterations: 1, memoryKB: 256, parallelism: 1, outputLen: 32)
        let k1 = try manager.deriveSyncKey(passphrase: "correct horse", salt: salt, params: params)
        let k2 = try manager.deriveSyncKey(passphrase: "correct horse", salt: salt, params: params)
        XCTAssertEqual(k1.withUnsafeBytes { Data($0) }, k2.withUnsafeBytes { Data($0) })
    }

    func testSyncKeyDiffersWithDifferentPassphrase() throws {
        let salt = Data(repeating: 0x55, count: 16)
        let params = KDFParameters(algorithm: .argon2id, iterations: 1, memoryKB: 256, parallelism: 1, outputLen: 32)
        let a = try manager.deriveSyncKey(passphrase: "alpha", salt: salt, params: params)
        let b = try manager.deriveSyncKey(passphrase: "bravo", salt: salt, params: params)
        XCTAssertNotEqual(a.withUnsafeBytes { Data($0) }, b.withUnsafeBytes { Data($0) })
    }
}
