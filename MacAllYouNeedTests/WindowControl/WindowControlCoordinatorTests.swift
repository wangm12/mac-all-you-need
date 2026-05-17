import Core
@testable import MacAllYouNeed
import Platform
import XCTest

@MainActor
final class WindowControlCoordinatorTests: XCTestCase {
    func testStartsOnlyWhenEnabledAndAccessibilityTrusted() {
        let tap = FakeWindowControlTap()
        let coordinator = makeCoordinator(settings: .default, axTrusted: false, tap: tap)

        coordinator.start()

        XCTAssertEqual(coordinator.state, .off)
        XCTAssertEqual(tap.startCount, 0)

        var enabled = WindowControlSettings.default
        enabled.enabled = true
        coordinator.applySettings(enabled)
        coordinator.refreshAccessibilityTrust(false)

        XCTAssertEqual(coordinator.state, .needsAccessibility)
        XCTAssertEqual(tap.startCount, 0)

        coordinator.refreshAccessibilityTrust(true)

        XCTAssertEqual(coordinator.state, .active)
        XCTAssertEqual(tap.startCount, 1)
    }

    func testStopsWhenDisabled() {
        let tap = FakeWindowControlTap()
        var settings = WindowControlSettings.default
        settings.enabled = true
        let coordinator = makeCoordinator(settings: settings, axTrusted: true, tap: tap)
        coordinator.start()

        coordinator.applySettings(.default)

        XCTAssertEqual(coordinator.state, .off)
        XCTAssertEqual(tap.stopCount, 1)
    }

    func testSuspendAndResumeForHotkeyRecordingTearDownAndRestartTapIdempotently() {
        let tap = FakeWindowControlTap()
        var settings = WindowControlSettings.default
        settings.enabled = true
        let coordinator = makeCoordinator(settings: settings, axTrusted: true, tap: tap)
        coordinator.start()

        coordinator.suspendForHotkeyRecording()
        coordinator.suspendForHotkeyRecording()

        XCTAssertEqual(coordinator.state, .suspended(.hotkeyRecording))
        XCTAssertEqual(tap.stopCount, 1)

        coordinator.resumeAfterHotkeyRecording()
        coordinator.resumeAfterHotkeyRecording()

        XCTAssertEqual(coordinator.state, .active)
        XCTAssertEqual(tap.startCount, 2)
    }

    func testIgnoredFrontAppSuppressesKeyboardActions() {
        var settings = WindowControlSettings.default
        settings.enabled = true
        settings.ignoredBundleIDs = ["com.example.ignored"]
        let performer = FakeWindowActionPerformer()
        let coordinator = makeCoordinator(
            settings: settings,
            axTrusted: true,
            performer: performer,
            frontmostBundleID: { "com.example.ignored" }
        )
        coordinator.start()

        coordinator.perform(action: .leftHalf)

        XCTAssertEqual(coordinator.state, .suspended(.ignoredApp))
        XCTAssertEqual(performer.actions, [])
    }

    func testKeyboardActionDelegatesToPerformerAndStoresPreviousFrame() {
        var settings = WindowControlSettings.default
        settings.enabled = true
        let identity = WindowIdentity(pid: 123, cgWindowID: 456, titleHash: nil)
        let performer = FakeWindowActionPerformer(
            identity: identity,
            result: WindowMovementResult(
                action: .leftHalf,
                status: .moved,
                originalFrame: CGRect(x: 20, y: 30, width: 800, height: 600),
                proposedFrame: CGRect(x: 0, y: 0, width: 720, height: 900),
                resultingFrame: CGRect(x: 0, y: 0, width: 720, height: 900)
            )
        )
        let history = WindowRestoreHistory()
        let coordinator = makeCoordinator(
            settings: settings,
            axTrusted: true,
            performer: performer,
            restoreHistory: history
        )
        coordinator.start()

        coordinator.perform(action: .leftHalf)

        XCTAssertEqual(performer.actions, [.leftHalf])
        XCTAssertEqual(history.restoreFrame(for: identity), CGRect(x: 20, y: 30, width: 800, height: 600))
        XCTAssertEqual(coordinator.lastAction, .leftHalf)
        XCTAssertEqual(coordinator.lastMovementResult?.status, .moved)
    }

    func testRestoreUsesStoredPreviousFrame() {
        var settings = WindowControlSettings.default
        settings.enabled = true
        let identity = WindowIdentity(pid: 123, cgWindowID: 456, titleHash: nil)
        let history = WindowRestoreHistory()
        let previousFrame = CGRect(x: 20, y: 30, width: 800, height: 600)
        history.store(previousFrame, for: identity)
        let performer = FakeWindowActionPerformer(identity: identity)
        let coordinator = makeCoordinator(
            settings: settings,
            axTrusted: true,
            performer: performer,
            restoreHistory: history
        )
        coordinator.start()

        coordinator.perform(action: .restore)

        XCTAssertEqual(performer.actions, [.restore])
        XCTAssertEqual(performer.restoreFrames, [previousFrame])
    }

    func testRestoreUsesStableFallbackWhenFocusedWindowFrameChanged() {
        var settings = WindowControlSettings.default
        settings.enabled = true
        let history = WindowRestoreHistory()
        let previousFrame = CGRect(x: 20, y: 30, width: 800, height: 600)
        history.store(
            previousFrame,
            for: WindowIdentity(pid: 123, cgWindowID: nil, titleHash: 42, frameFingerprint: 1)
        )
        let performer = FakeWindowActionPerformer(
            identity: WindowIdentity(pid: 123, cgWindowID: nil, titleHash: 42, frameFingerprint: 2)
        )
        let coordinator = makeCoordinator(
            settings: settings,
            axTrusted: true,
            performer: performer,
            restoreHistory: history
        )
        coordinator.start()

        coordinator.perform(action: .restore)

        XCTAssertEqual(performer.actions, [.restore])
        XCTAssertEqual(performer.restoreFrames, [previousFrame])
    }

    func testAccessibilityGrantAfterNeedsPermissionStartsCoordinator() {
        var settings = WindowControlSettings.default
        settings.enabled = true
        let tap = FakeWindowControlTap()
        let coordinator = makeCoordinator(settings: settings, axTrusted: false, tap: tap)
        coordinator.start()

        XCTAssertEqual(coordinator.state, .needsAccessibility)

        coordinator.refreshAccessibilityTrust(true)

        XCTAssertEqual(coordinator.state, .active)
        XCTAssertEqual(tap.startCount, 1)
    }

    func testWindowActionPerformerAvailabilityRequiresEnabledTrustedUnsuspendedCoordinator() {
        var settings = WindowControlSettings.default
        settings.enabled = true
        let performer = FakeWindowActionPerformer()
        let coordinator = makeCoordinator(settings: settings, axTrusted: false, performer: performer)

        coordinator.start()

        XCTAssertFalse(coordinator.windowActionPerformerAvailable)

        coordinator.refreshAccessibilityTrust(true)

        XCTAssertTrue(coordinator.windowActionPerformerAvailable)

        performer.isAvailable = false

        XCTAssertFalse(coordinator.windowActionPerformerAvailable)
    }

    func testKeyboardActionsRemainAvailableWhenEventTapInstallFails() {
        var settings = WindowControlSettings.default
        settings.enabled = true
        let tap = FakeWindowControlTap(startError: TestWindowControlError.tapInstallFailed)
        let performer = FakeWindowActionPerformer()
        let coordinator = makeCoordinator(settings: settings, axTrusted: true, tap: tap, performer: performer)

        coordinator.start()
        coordinator.perform(action: .leftHalf)

        XCTAssertEqual(coordinator.state, .error("tap install failed"))
        XCTAssertTrue(coordinator.windowActionPerformerAvailable)
        XCTAssertEqual(performer.actions, [.leftHalf])
    }

    func testRefreshAccessibilityTrustRequestsHotkeyRegistrationRefreshWhenAvailabilityChanges() {
        var settings = WindowControlSettings.default
        settings.enabled = true
        var refreshCount = 0
        let coordinator = WindowControlCoordinator(
            settings: settings,
            tap: FakeWindowControlTap(),
            actionPerformer: FakeWindowActionPerformer(),
            accessibilityTrust: { false },
            frontmostBundleID: { "com.example.active" },
            onHotkeyRegistrationNeedsRefresh: { refreshCount += 1 }
        )
        coordinator.start()

        coordinator.refreshAccessibilityTrust(true)
        coordinator.refreshAccessibilityTrust(true)
        coordinator.refreshAccessibilityTrust(false)

        XCTAssertEqual(refreshCount, 2)
    }

    func testUnavailablePerformerDoesNotExecuteAction() {
        var settings = WindowControlSettings.default
        settings.enabled = true
        let performer = FakeWindowActionPerformer()
        performer.isAvailable = false
        let coordinator = makeCoordinator(settings: settings, axTrusted: true, performer: performer)
        coordinator.start()

        coordinator.perform(action: .leftHalf)

        XCTAssertEqual(performer.actions, [])
        XCTAssertNil(coordinator.lastAction)
    }

    func testWindowLayoutsFeatureGateSuppressesKeyboardActions() {
        var settings = WindowControlSettings.default
        settings.enabled = true
        let performer = FakeWindowActionPerformer()
        let coordinator = makeCoordinator(
            settings: settings,
            featureAvailability: WindowControlFeatureAvailability(
                windowLayoutsEnabled: false,
                windowGrabEnabled: true
            ),
            axTrusted: true,
            performer: performer
        )
        coordinator.start()

        coordinator.perform(action: .leftHalf)

        XCTAssertFalse(coordinator.windowActionPerformerAvailable)
        XCTAssertEqual(performer.actions, [])
        XCTAssertNil(coordinator.lastAction)
    }

    func testWindowGrabFeatureCanRunWhenWindowLayoutsFeatureIsOff() {
        var settings = WindowControlSettings.default
        settings.enabled = true
        settings.dragAnywhereEnabled = true
        let tap = FakeWindowControlTap()
        let coordinator = makeCoordinator(
            settings: settings,
            featureAvailability: WindowControlFeatureAvailability(
                windowLayoutsEnabled: false,
                windowGrabEnabled: true
            ),
            axTrusted: true,
            tap: tap
        )

        coordinator.start()

        XCTAssertEqual(coordinator.state, .active)
        XCTAssertEqual(tap.startCount, 1)
        XCTAssertFalse(coordinator.windowActionPerformerAvailable)
    }

    func testDisablingWindowGrabStopsTapWhenWindowLayoutsFeatureIsOff() {
        var settings = WindowControlSettings.default
        settings.enabled = true
        settings.dragAnywhereEnabled = true
        let tap = FakeWindowControlTap()
        let coordinator = makeCoordinator(
            settings: settings,
            featureAvailability: WindowControlFeatureAvailability(
                windowLayoutsEnabled: false,
                windowGrabEnabled: true
            ),
            axTrusted: true,
            tap: tap
        )
        coordinator.start()

        coordinator.applyFeatureAvailability(.disabled)

        XCTAssertEqual(coordinator.state, .off)
        XCTAssertEqual(tap.stopCount, 1)
    }

    private func makeCoordinator(
        settings: WindowControlSettings,
        featureAvailability: WindowControlFeatureAvailability = .enabled,
        axTrusted: Bool,
        tap: FakeWindowControlTap? = nil,
        performer: FakeWindowActionPerformer? = nil,
        restoreHistory: WindowRestoreHistory = WindowRestoreHistory(),
        frontmostBundleID: @escaping () -> String? = { "com.example.active" }
    ) -> WindowControlCoordinator {
        WindowControlCoordinator(
            settings: settings,
            featureAvailability: featureAvailability,
            tap: tap ?? FakeWindowControlTap(),
            actionPerformer: performer ?? FakeWindowActionPerformer(),
            restoreHistory: restoreHistory,
            accessibilityTrust: { axTrusted },
            frontmostBundleID: frontmostBundleID,
            onHotkeyRegistrationNeedsRefresh: {}
        )
    }
}

@MainActor
private final class FakeWindowControlTap: WindowControlTapLifecycle {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var isRunning = false
    private let startError: Error?

    init(startError: Error? = nil) {
        self.startError = startError
    }

    func start() throws {
        startCount += 1
        if let startError {
            throw startError
        }
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        stopCount += 1
        isRunning = false
    }
}

private enum TestWindowControlError: LocalizedError {
    case tapInstallFailed

    var errorDescription: String? {
        "tap install failed"
    }
}

@MainActor
private final class FakeWindowActionPerformer: WindowControlActionPerforming {
    let identity: WindowIdentity?
    let result: WindowMovementResult?
    var isAvailable = true
    private(set) var actions: [WindowAction] = []
    private(set) var restoreFrames: [CGRect?] = []

    init(identity: WindowIdentity? = nil, result: WindowMovementResult? = nil) {
        self.identity = identity
        self.result = result
    }

    var currentIdentity: WindowIdentity? {
        identity
    }

    func perform(_ action: WindowAction, restoreFrame: CGRect?) -> WindowMovementResult? {
        actions.append(action)
        restoreFrames.append(restoreFrame)
        return result
    }
}
