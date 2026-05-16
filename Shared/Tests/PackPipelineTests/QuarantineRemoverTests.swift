import XCTest
@testable import PackPipeline

final class QuarantineRemoverTests: XCTestCase {
    private var tmp: URL!
    override func setUp() {
        super.setUp()
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("qr-test-\(UUID()).bin")
        FileManager.default.createFile(atPath: tmp.path, contents: Data("hi".utf8))
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: tmp)
        super.tearDown()
    }

    func testRemovesQuarantineXattr() throws {
        // Set a quarantine xattr first
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        p.arguments = ["-w", "com.apple.quarantine", "0083;00000000;Test;|com.test", tmp.path]
        try p.run(); p.waitUntilExit()

        XCTAssertTrue(QuarantineRemover.hasQuarantine(at: tmp))
        try QuarantineRemover.remove(at: tmp)
        XCTAssertFalse(QuarantineRemover.hasQuarantine(at: tmp))
    }

    func testNoOpWhenAbsent() throws {
        XCTAssertFalse(QuarantineRemover.hasQuarantine(at: tmp))
        XCTAssertNoThrow(try QuarantineRemover.remove(at: tmp))
    }
}
