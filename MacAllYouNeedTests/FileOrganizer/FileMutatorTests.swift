import XCTest
@testable import MacAllYouNeed
@testable import Core

final class FileMutatorTests: XCTestCase {
    var tmpDir: URL!
    override func setUp() {
        tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("MutatorTest-\(UUID())")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: tmpDir) }

    func testApplyMovesFile() throws {
        let src = tmpDir.appendingPathComponent("old.txt")
        let dst = tmpDir.appendingPathComponent("new.txt")
        try "hello".write(to: src, atomically: true, encoding: .utf8)
        let op = ManifestOperation(sourceURL: src, destinationURL: dst)
        var manifest = Manifest(operations: [op])
        let errors = FileMutator().apply(manifest: &manifest, rootURL: tmpDir)
        XCTAssertTrue(errors.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dst.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: src.path))
    }
    func testRollbackRestoresFile() throws {
        let src = tmpDir.appendingPathComponent("old.txt")
        let dst = tmpDir.appendingPathComponent("new.txt")
        try "hello".write(to: src, atomically: true, encoding: .utf8)
        let op = ManifestOperation(sourceURL: src, destinationURL: dst)
        var manifest = Manifest(operations: [op])
        _ = FileMutator().apply(manifest: &manifest, rootURL: tmpDir)
        let errors = FileMutator().rollback(manifest: &manifest)
        XCTAssertTrue(errors.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: src.path))
    }
}
