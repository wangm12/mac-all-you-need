import XCTest
@testable import Core

final class OrganizerManifestStoreTests: XCTestCase {
    func testSaveAndLoad() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ManifestTest-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try OrganizerManifestStore(directory: dir)
        var m = Manifest()
        m.operations = [ManifestOperation(sourceURL: URL(fileURLWithPath: "/a"), destinationURL: URL(fileURLWithPath: "/b"))]
        try store.save(m)
        let loaded = try store.load(id: m.id)
        XCTAssertEqual(loaded?.operations.count, 1)
    }
    func testAllReturnsNewestFirst() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ManifestAll-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try OrganizerManifestStore(directory: dir)
        let m1 = Manifest(id: UUID().uuidString, createdAt: Date().addingTimeInterval(-10))
        let m2 = Manifest(id: UUID().uuidString, createdAt: Date())
        try store.save(m1)
        try store.save(m2)
        let all = try store.all()
        XCTAssertEqual(all.first?.id, m2.id)
    }
}
