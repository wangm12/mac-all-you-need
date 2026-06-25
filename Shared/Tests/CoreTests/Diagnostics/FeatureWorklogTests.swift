import XCTest
@testable import Core

final class FeatureWorklogTests: XCTestCase {
    private var tempRoot: URL!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("mayn-worklog-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        AppGroup.containerURLOverride = tempRoot
    }

    override func tearDown() {
        AppGroup.containerURLOverride = nil
        try? FileManager.default.removeItem(at: tempRoot)
        super.tearDown()
    }

    func testWritesStructuredLine() throws {
        FeatureWorklog.log(.windowHub, "test.event", fields: ["pid": 42, "ok": true])
        waitForWorklogFlush()

        let file = FeatureWorklog.latestLogFile(for: .windowHub)
        XCTAssertNotNil(file)
        let text = try String(contentsOf: XCTUnwrap(file), encoding: .utf8)
        XCTAssertTrue(text.contains("test.event"))
        XCTAssertTrue(text.contains("pid=42"))
        XCTAssertTrue(text.contains("ok=true"))
    }

    func testClearRemovesFeatureDirectory() throws {
        FeatureWorklog.log(.windowHub, "before.clear")
        waitForWorklogFlush()

        FeatureWorklog.clear(.windowHub)
        waitForWorklogFlush()

        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: FeatureWorklog.directory(for: .windowHub).path,
            isDirectory: &isDir
        )
        XCTAssertFalse(exists)
    }

    private func waitForWorklogFlush() {
        let exp = expectation(description: "flush")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) { exp.fulfill() }
        wait(for: [exp], timeout: 1)
    }
}
