@testable import Platform
import XCTest

final class FolderEnumeratorTests: XCTestCase {
    var dir: URL!
    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("fe-\(UUID())", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? Data(repeating: 0, count: 1024).write(to: dir.appendingPathComponent("a.txt"))
        try? Data(repeating: 0, count: 2048).write(to: dir.appendingPathComponent("b.png"))
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try? Data(repeating: 0, count: 4096).write(to: dir.appendingPathComponent("sub/c.swift"))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir); super.tearDown()
    }

    func testEnumerateProducesEntries() async throws {
        let inv = try await FolderEnumerator.enumerate(url: dir, maxEntries: 1000)
        XCTAssertGreaterThanOrEqual(inv.entries.count, 3)
        XCTAssertGreaterThanOrEqual(inv.totalSize, Int64(1024 + 2048 + 4096))
    }

    func testBreakdownGroupsByCategory() async throws {
        let inv = try await FolderEnumerator.enumerate(url: dir, maxEntries: 1000)
        XCTAssertGreaterThan(inv.breakdown[.images, default: 0], 0)
        XCTAssertGreaterThan(inv.breakdown[.code, default: 0], 0)
    }

    func testLargestFilesSorted() async throws {
        let inv = try await FolderEnumerator.enumerate(url: dir, maxEntries: 1000)
        let largest = inv.largest.first?.name
        XCTAssertEqual(largest, "c.swift")
    }

    func testCapMarksPartial() async throws {
        let inv = try await FolderEnumerator.enumerate(url: dir, maxEntries: 1)
        XCTAssertTrue(inv.isPartial)
    }

    func testImmediateEnumerationSkipsNestedChildren() async throws {
        let inv = try await FolderEnumerator.enumerateImmediate(url: dir, maxEntries: 1000)
        let names = inv.entries.map(\.name)

        XCTAssertTrue(names.contains("a.txt"))
        XCTAssertTrue(names.contains("b.png"))
        XCTAssertTrue(names.contains("sub"))
        XCTAssertFalse(names.contains("c.swift"))
        XCTAssertEqual(inv.largest.first?.name, "b.png")
        XCTAssertNil(inv.breakdown[.code])
    }

    func testImmediateCapMarksPartial() async throws {
        let inv = try await FolderEnumerator.enumerateImmediate(url: dir, maxEntries: 1)

        XCTAssertEqual(inv.entries.count, 1)
        XCTAssertTrue(inv.isPartial)
    }
}
