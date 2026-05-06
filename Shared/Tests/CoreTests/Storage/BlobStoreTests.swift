@testable import Core
import CryptoKit
import XCTest

final class BlobStoreTests: XCTestCase {
    var dir: URL!
    var store: BlobStore!
    var key: SymmetricKey!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("Blob-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        key = SymmetricKey(size: .bits256)
        store = BlobStore(rootURL: dir, key: key)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testWriteThenReadRoundTrip() throws {
        let data = Data(repeating: 0xAB, count: 4096)
        let id = try store.write(data)
        let read = try store.read(id: id)
        XCTAssertEqual(read, data)
    }

    func testWriteCreatesFileOnDisk() throws {
        let id = try store.write(Data(repeating: 0x01, count: 16))
        let path = dir.appendingPathComponent("\(id).bin")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
    }

    func testReadFailsWithWrongKey() throws {
        let id = try store.write(Data("secret".utf8))
        let other = BlobStore(rootURL: dir, key: SymmetricKey(size: .bits256))
        XCTAssertThrowsError(try other.read(id: id))
    }

    func testDeleteRemovesFile() throws {
        let id = try store.write(Data([0]))
        try store.delete(id: id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(id).bin").path))
    }
}
