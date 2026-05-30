import XCTest
@testable import MacAllYouNeed

final class DockPreviewCaptureSchedulerTests: XCTestCase {
    func testConcurrentCapApplied() async {
        let scheduler = DockPreviewCaptureScheduler(maxConcurrent: 2)
        await scheduler.acquire()
        await scheduler.acquire()
        // Third acquire would block until a release frees a slot.
        let completed = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await scheduler.release()
                await scheduler.acquire()
                await scheduler.release()
                return true
            }
            return await group.first { $0 == true } ?? false
        }
        XCTAssertTrue(completed)
    }
}
