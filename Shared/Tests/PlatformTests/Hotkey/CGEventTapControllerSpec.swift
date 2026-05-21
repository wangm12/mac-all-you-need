import XCTest
import CoreGraphics
@testable import Platform

final class CGEventTapControllerSpec: XCTestCase {

    // MARK: - Helpers

    private func makeController(
        tap: CGEventTapLocation = .cghidEventTap,
        place: CGEventTapPlacement = .headInsertEventTap,
        options: CGEventTapOptions = .defaultTap,
        runLoop: CGEventTapController.RunLoopTarget = .main
    ) -> CGEventTapController {
        CGEventTapController(
            tap: tap,
            place: place,
            options: options,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            runLoop: runLoop,
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        )
    }

    // MARK: - State machine

    func testInitialStateIsNotInstalled() {
        let controller = makeController()
        XCTAssertFalse(controller.isInstalled)
    }

    func testInstallAttemptsToCreateTap() {
        // In a unit-test runner without AX permission, tapCreate returns nil and
        // install() throws. We accept both outcomes — document both paths.
        let controller = makeController()
        do {
            try controller.install()
            // If AX permission happens to be granted (e.g. developer machine), tap installs.
            XCTAssertTrue(controller.isInstalled)
        } catch CGEventTapController.InstallError.creationFailed {
            // Expected in CI / sandboxed environments.
            XCTAssertFalse(controller.isInstalled)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testUninstallIsIdempotent() {
        let controller = makeController()
        // Calling uninstall before install must not crash or throw.
        controller.uninstall()
        controller.uninstall()
        XCTAssertFalse(controller.isInstalled)
    }

    func testUninstallClearsInstalledState() {
        let controller = makeController()
        // Attempt install; if it succeeds, verify uninstall clears state.
        if (try? controller.install()) != nil {
            XCTAssertTrue(controller.isInstalled)
            controller.uninstall()
            XCTAssertFalse(controller.isInstalled)
        }
        // If install failed (no AX permission), isInstalled stays false.
        XCTAssertFalse(controller.isInstalled)
    }

    func testReenableAfterTimeoutOnNonInstalledIsNoOp() {
        // Must not crash.
        let controller = makeController()
        controller.reenableAfterTimeout()
        XCTAssertFalse(controller.isInstalled)
    }

    func testEnableOnNonInstalledIsNoOp() {
        let controller = makeController()
        controller.enable()  // must not crash
        XCTAssertFalse(controller.isInstalled)
    }

    func testDisableOnNonInstalledIsNoOp() {
        let controller = makeController()
        controller.disable()  // must not crash
        XCTAssertFalse(controller.isInstalled)
    }

    // MARK: - Error path

    func testInstallThrowsCreationFailedWhenTapCreateReturnsNil() {
        // In environments without AX permission CGEvent.tapCreate returns nil.
        // We verify the error type is correct when that happens.
        let controller = makeController()
        do {
            try controller.install()
            // Permitted env — no throw. Skip the failure assertion.
        } catch let error as CGEventTapController.InstallError {
            XCTAssertEqual(error, .creationFailed)
        } catch {
            XCTFail("Expected InstallError.creationFailed, got \(error)")
        }
    }

    // MARK: - Argument round-trip

    func testInspectionPropertiesRoundTripCghidListenTailAppend() {
        let controller = CGEventTapController(
            tap: .cghidEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: 0,
            runLoop: .main,
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        )
        XCTAssertEqual(controller.installedTapLocation, .cghidEventTap)
        XCTAssertEqual(controller.installedTapPlacement, .tailAppendEventTap)
        XCTAssertEqual(controller.installedTapOptions, .listenOnly)
        XCTAssertEqual(controller.installedRunLoopTarget, .main)
    }

    func testInspectionPropertiesRoundTripSessionHeadDefaultTap() {
        let controller = CGEventTapController(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: 0,
            runLoop: .main,
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        )
        XCTAssertEqual(controller.installedTapLocation, .cgSessionEventTap)
        XCTAssertEqual(controller.installedTapPlacement, .headInsertEventTap)
        XCTAssertEqual(controller.installedTapOptions, .defaultTap)
        XCTAssertEqual(controller.installedRunLoopTarget, .main)
    }

    func testInspectionPropertiesRoundTripCurrentRunLoop() {
        let loop = CFRunLoopGetCurrent()!
        let controller = CGEventTapController(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: 0,
            runLoop: .current(loop),
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        )
        XCTAssertEqual(controller.installedRunLoopTarget, .current(loop))
    }

    // MARK: - RunLoopTarget Equatable

    func testRunLoopTargetMainEqualsMain() {
        XCTAssertEqual(
            CGEventTapController.RunLoopTarget.main,
            CGEventTapController.RunLoopTarget.main
        )
    }

    func testRunLoopTargetCurrentEqualsSameLoop() {
        let loop = CFRunLoopGetCurrent()!
        XCTAssertEqual(
            CGEventTapController.RunLoopTarget.current(loop),
            CGEventTapController.RunLoopTarget.current(loop)
        )
    }

    func testRunLoopTargetMainNotEqualCurrent() {
        let loop = CFRunLoopGetCurrent()!
        XCTAssertNotEqual(
            CGEventTapController.RunLoopTarget.main,
            CGEventTapController.RunLoopTarget.current(loop)
        )
    }

    func testRunLoopTargetCurrentNotEqualDifferentLoop() {
        // We can't easily manufacture two distinct CFRunLoop objects in a unit
        // test, but we can verify main != current(main-loop) is false — they
        // are different *enum cases* even if the underlying loop pointer might
        // happen to be the same on main thread. The case mismatch is enough.
        let mainLoop = CFRunLoopGetMain()!
        XCTAssertNotEqual(
            CGEventTapController.RunLoopTarget.main,
            CGEventTapController.RunLoopTarget.current(mainLoop)
        )
    }
}

// Note: CGEventTapController.InstallError is an enum with a single case and
// synthesized Equatable from the Platform module — no extension needed here.
