@testable import Core
import CryptoKit
import XCTest

final class PinboardColorTests: XCTestCase {
    var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PinColor-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testColorRoundTripsThroughEncryptedEnvelope() throws {
        let key = SymmetricKey(size: .bits256)
        let db = try Database(url: dir.appendingPathComponent("p.sqlite"), migrations: PinboardStore.migrations)
        let store = PinboardStore(database: db, deviceKey: key)

        var pinboard = try store.create(name: "Project X")
        pinboard.color = "#FF8800"
        try store.update(pinboard)

        let loaded = try store.list().first(where: { $0.id == pinboard.id })
        XCTAssertEqual(loaded?.color, "#FF8800")
    }

    func testLegacyEnvelopeWithoutColorDecodesToNil() throws {
        let key = SymmetricKey(size: .bits256)
        let db = try Database(url: dir.appendingPathComponent("p.sqlite"), migrations: PinboardStore.migrations)
        let store = PinboardStore(database: db, deviceKey: key)
        let created = try store.create(name: "old")
        let encoded = try JSONEncoder().encode(created)
        var legacyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacyObject.removeValue(forKey: "color")
        let legacyJSON = try JSONSerialization.data(withJSONObject: legacyObject)
        let env = try Cipher.seal(legacyJSON, with: key)
        try db.queue.write { conn in
            try conn.execute(
                sql: """
                UPDATE pinboards
                SET envelope = ?, modified = ?, lamport = 0, device_id = NULL
                WHERE id = ?
                """,
                arguments: [env.combined, created.modified.timeIntervalSince1970, created.id.rawValue]
            )
        }

        let loaded = try store.list().first
        XCTAssertEqual(loaded?.name, "old")
        XCTAssertNil(loaded?.color)
    }
}
