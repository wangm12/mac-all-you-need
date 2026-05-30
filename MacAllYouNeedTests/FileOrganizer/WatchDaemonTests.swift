import XCTest
@testable import MacAllYouNeed

final class WatchDaemonTests: XCTestCase {
    func testDaemonStartsAndStops() async {
        let daemon = await WatchDaemon(onNewFiles: { _ in })
        let url = FileManager.default.temporaryDirectory
        await daemon.start(watching: url)
        await daemon.stop()  // should not crash
        XCTAssertTrue(true)
    }
}
