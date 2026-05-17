@testable import Core
import CoreGraphics
import XCTest

final class WindowRestoreHistoryTests: XCTestCase {
    func testStoresAndRestoresFrameByCGWindowID() {
        let history = WindowRestoreHistory()
        let id = WindowIdentity(pid: 123, cgWindowID: 456, titleHash: nil)
        let frame = CGRect(x: 20, y: 20, width: 800, height: 600)

        history.store(frame, for: id)

        XCTAssertEqual(history.restoreFrame(for: id), frame)
        XCTAssertNil(history.restoreFrame(for: WindowIdentity(pid: 123, cgWindowID: 999, titleHash: nil)))
    }

    func testCGWindowIDIsPreferredOverTitleHash() {
        let history = WindowRestoreHistory()
        let frame = CGRect(x: 10, y: 15, width: 500, height: 400)

        history.store(frame, for: WindowIdentity(pid: 123, cgWindowID: 456, titleHash: 1))

        XCTAssertEqual(
            history.restoreFrame(for: WindowIdentity(pid: 123, cgWindowID: 456, titleHash: 999)),
            frame
        )
        XCTAssertNil(history.restoreFrame(for: WindowIdentity(pid: 123, cgWindowID: 999, titleHash: 1)))
    }

    func testFallsBackToTitleHashWhenCGWindowIDIsUnavailable() {
        let history = WindowRestoreHistory()
        let frame = CGRect(x: 30, y: 40, width: 700, height: 500)

        history.store(frame, for: WindowIdentity(pid: 123, cgWindowID: nil, titleHash: 42, frameFingerprint: 7))

        XCTAssertEqual(
            history.restoreFrame(for: WindowIdentity(pid: 123, cgWindowID: nil, titleHash: 42)),
            frame
        )
        XCTAssertNil(history.restoreFrame(for: WindowIdentity(pid: 321, cgWindowID: nil, titleHash: 42)))
    }

    func testTitleHashWithoutFrameFingerprintCreatesStableFallbackIdentity() {
        let history = WindowRestoreHistory()
        let frame = CGRect(x: 30, y: 40, width: 700, height: 500)

        history.store(
            frame,
            for: WindowIdentity(pid: 123, cgWindowID: nil, titleHash: 42)
        )

        XCTAssertEqual(history.restoreFrame(for: WindowIdentity(pid: 123, cgWindowID: nil, titleHash: 42)), frame)
        XCTAssertEqual(history.entryCount, 1)
    }

    func testFallbackIdentitySurvivesFrameFingerprintChangesAfterMove() {
        let history = WindowRestoreHistory()
        let originalIdentity = WindowIdentity(pid: 123, cgWindowID: nil, titleHash: 42, frameFingerprint: 1)
        let movedIdentity = WindowIdentity(pid: 123, cgWindowID: nil, titleHash: 42, frameFingerprint: 2)
        let originalFrame = CGRect(x: 10, y: 10, width: 500, height: 400)

        history.store(originalFrame, for: originalIdentity)

        XCTAssertEqual(history.restoreFrame(for: movedIdentity), originalFrame)
    }

    func testHistoryCapsStoredEntries() {
        let history = WindowRestoreHistory(capacity: 2)

        history.store(CGRect(x: 1, y: 1, width: 100, height: 100), for: WindowIdentity(pid: 1, cgWindowID: 1, titleHash: nil))
        history.store(CGRect(x: 2, y: 2, width: 100, height: 100), for: WindowIdentity(pid: 1, cgWindowID: 2, titleHash: nil))
        history.store(CGRect(x: 3, y: 3, width: 100, height: 100), for: WindowIdentity(pid: 1, cgWindowID: 3, titleHash: nil))

        XCTAssertEqual(history.entryCount, 2)
        XCTAssertNil(history.restoreFrame(for: WindowIdentity(pid: 1, cgWindowID: 1, titleHash: nil)))
        XCTAssertNotNil(history.restoreFrame(for: WindowIdentity(pid: 1, cgWindowID: 2, titleHash: nil)))
        XCTAssertNotNil(history.restoreFrame(for: WindowIdentity(pid: 1, cgWindowID: 3, titleHash: nil)))
    }

    func testUpdatingExistingEntryRefreshesEvictionRecency() {
        let history = WindowRestoreHistory(capacity: 2)
        let idA = WindowIdentity(pid: 1, cgWindowID: 1, titleHash: nil)
        let idB = WindowIdentity(pid: 1, cgWindowID: 2, titleHash: nil)
        let idC = WindowIdentity(pid: 1, cgWindowID: 3, titleHash: nil)
        let refreshedAFrame = CGRect(x: 10, y: 10, width: 100, height: 100)

        history.store(CGRect(x: 1, y: 1, width: 100, height: 100), for: idA)
        history.store(CGRect(x: 2, y: 2, width: 100, height: 100), for: idB)
        history.store(refreshedAFrame, for: idA)
        history.store(CGRect(x: 3, y: 3, width: 100, height: 100), for: idC)

        XCTAssertEqual(history.entryCount, 2)
        XCTAssertEqual(history.restoreFrame(for: idA), refreshedAFrame)
        XCTAssertNil(history.restoreFrame(for: idB))
        XCTAssertNotNil(history.restoreFrame(for: idC))
    }
}
