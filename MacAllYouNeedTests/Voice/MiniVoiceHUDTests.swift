@testable import MacAllYouNeed
import AppKit
import SwiftUI
import XCTest

final class MiniVoiceHUDTests: XCTestCase {
    func testV3FixedPillSize() {
        XCTAssertEqual(MiniVoiceHUDLayout.pillWidth, 392)
        XCTAssertEqual(MiniVoiceHUDLayout.pillHeight, 58)
        XCTAssertEqual(MiniVoiceHUDLayout.sideSlotWidth, 64)
        XCTAssertEqual(MiniVoiceHUDLayout.actionButtonSize, 40)
    }

    func testPillAnchorsBottomCenterAboveDock() {
        let visibleFrame = NSRect(x: 0, y: 100, width: 1440, height: 900)
        let screenFrame = NSRect(x: 0, y: 0, width: 1440, height: 1000)
        let size = MiniVoiceHUDLayout.pillSize
        let origin = MiniVoiceHUDLayout.pillOrigin(
            in: visibleFrame,
            screenFrame: screenFrame,
            size: size
        )

        XCTAssertEqual(origin.x, 524, accuracy: 0.5)
        XCTAssertEqual(
            origin.y,
            visibleFrame.minY + MiniVoiceHUDLayout.bottomInsetAboveDock,
            accuracy: 0.5
        )
    }

    func testPillLiftsAboveClipboardDockObstruction() {
        let visibleFrame = NSRect(x: 0, y: 100, width: 1440, height: 900)
        let screenFrame = NSRect(x: 0, y: 0, width: 1440, height: 1000)
        let size = MiniVoiceHUDLayout.pillSize
        let obstruction: CGFloat = 372
        let origin = MiniVoiceHUDLayout.pillOrigin(
            in: visibleFrame,
            screenFrame: screenFrame,
            size: size,
            bottomObstruction: obstruction
        )

        XCTAssertEqual(
            origin.y,
            visibleFrame.minY + MiniVoiceHUDLayout.bottomInsetAboveDock + obstruction,
            accuracy: 0.5
        )
    }

    func testAllVisibleStatesShareIdenticalSize() {
        let expected = CGSize(width: 392, height: 58)
        XCTAssertEqual(MiniVoiceHUDLayout.size(for: .startingMic), expected)
        XCTAssertEqual(MiniVoiceHUDLayout.size(for: .recording(level: 0.4)), expected)
        XCTAssertEqual(MiniVoiceHUDLayout.size(for: .transcribing(.asr)), expected)
        XCTAssertEqual(MiniVoiceHUDLayout.size(for: .transcribing(.asr, isSlow: true)), expected)
        XCTAssertEqual(MiniVoiceHUDLayout.size(for: .inserted), expected)
        XCTAssertEqual(MiniVoiceHUDLayout.size(for: .clipboardFallback), expected)
        XCTAssertEqual(MiniVoiceHUDLayout.size(for: .cancelled), expected)
    }

    func testStartingMicMapsToStartingLabelAndPulsingDot() {
        let pill = MiniVoiceHUDPill(state: .startingMic)

        XCTAssertEqual(pill.label, VoiceHUDCopy.Pill.starting)
        XCTAssertEqual(pill.leading, .bouncingDots)
        XCTAssertEqual(pill.actionAvailability, .none)
    }

    func testRecordingMapsToListeningWithStopAction() {
        let pill = MiniVoiceHUDPill(state: .recording(level: 0.4))

        XCTAssertEqual(pill.label, VoiceHUDCopy.Pill.listening)
        XCTAssertEqual(pill.leading, .waveformBars)
        XCTAssertEqual(pill.actionAvailability, .cancel)
        XCTAssertTrue(pill.isCancellable)
    }

    func testTranscribingPillUsesCenterLabelAndDimWaveform() {
        let pill = MiniVoiceHUDPill(state: .transcribing(.asr))

        XCTAssertEqual(pill.label, VoiceHUDCopy.Pill.transcribing)
        XCTAssertEqual(pill.leading, .waveformBars)
        XCTAssertTrue(pill.dimLeading)
        XCTAssertEqual(pill.actionAvailability, .none)
    }

    func testInsertedPillUsesCheckAndLabel() {
        let pill = MiniVoiceHUDPill(state: .inserted)

        XCTAssertEqual(pill.label, VoiceHUDCopy.Pill.inserted)
        XCTAssertEqual(pill.leading, .checkInCircle)
    }

    func testSlowTranscribingUsesStillWorkingLabel() {
        let pill = MiniVoiceHUDPill(state: .transcribing(.asr, isSlow: true))

        XCTAssertEqual(pill.label, VoiceHUDCopy.Pill.stillWorking)
    }

    func testWipeOverlayIsLighterThanGraphiteBase() {
        let wipe = rgbComponents(MiniVoiceHUDPalette.pillWipeOverlay)
        let graphite = rgbComponents(MiniVoiceHUDPalette.pillGraphite)
        XCTAssertGreaterThan(wipe.r + wipe.g + wipe.b, graphite.r + graphite.g + graphite.b)
    }

    func testNoSpeechPillUsesDetectedCopy() {
        let pill = MiniVoiceHUDPill(state: .noSpeech("anything"))

        XCTAssertEqual(pill.label, VoiceHUDCopy.Pill.noSpeech)
        XCTAssertEqual(pill.leading, .warningTriangle)
        XCTAssertEqual(pill.actionAvailability, .dismissTerminal)
    }

    func testTranscribeFailureShowsInPillWithRetry() {
        let message = "Couldn't transcribe"
        let pill = MiniVoiceHUDPill(state: .error(message))

        XCTAssertEqual(pill.label, VoiceHUDCopy.Pill.couldntTranscribe)
        XCTAssertEqual(pill.leading, .warningTriangle)
        XCTAssertEqual(pill.actionAvailability, .retry)
    }

    func testCancelledPillOffersRestore() {
        let pill = MiniVoiceHUDPill(state: .cancelled)

        XCTAssertEqual(pill.label, VoiceHUDCopy.Pill.cancelled)
        XCTAssertEqual(pill.leading, .xInCircle)
        XCTAssertEqual(pill.actionAvailability, .restore)
        XCTAssertTrue(pill.isRestorable)
    }

    func testClipboardFallbackUsesCenteredCopy() {
        let pill = MiniVoiceHUDPill(state: .clipboardFallback)
        XCTAssertEqual(pill.label, VoiceHUDCopy.Pill.clipboardFallback)
        XCTAssertEqual(pill.leading, .checkInCircle)
    }

    @MainActor
    func testBootCurveReachesFiftyPercentAtOneSecond() {
        let progress = MiniVoiceThinkingProgressBridge.bootProgress(at: 1.0)
        XCTAssertEqual(progress, 0.50, accuracy: 0.02)
    }

    @MainActor
    func testThinkingProgressIsMonotonicAndSnapsAtCompletion() {
        let bridge = MiniVoiceThinkingProgressBridge()
        bridge.applyStreamProgress(0.2)
        XCTAssertEqual(bridge.displayWipe, 0.2, accuracy: 0.0001)
        bridge.applyStreamProgress(0.996)
        XCTAssertEqual(bridge.displayWipe, 1.0, accuracy: 0.0001)
    }

    @MainActor
    func testVisibleLevelUpdatesReuseContentView() {
        let hud = MiniVoiceHUD()
        hud.show(.recording(level: 0.1), onCancel: {}, onPrimary: {})
        let firstContentView = hud.testingContentView

        hud.show(.recording(level: 0.5), onCancel: {}, onPrimary: {})

        XCTAssertTrue(hud.testingContentView === firstContentView)
        hud.dismiss()
    }
}

private func rgbComponents(_ color: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
    let ns = NSColor(color)
    guard let rgb = ns.usingColorSpace(.deviceRGB) else { return (0, 0, 0) }
    return (rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
}
