@testable import MacAllYouNeed
import AppKit
import SwiftUI
import XCTest

final class MiniVoiceHUDTests: XCTestCase {
    func testMinimumPillSize() {
        XCTAssertEqual(MiniVoiceHUDLayout.pillWidth, 144)
        XCTAssertEqual(MiniVoiceHUDLayout.pillHeight, 32)
        XCTAssertEqual(MiniVoiceHUDLayout.maxPillWidth, 180)
    }

    func testPillAnchorsBottomCenterAboveDock() {
        let visibleFrame = NSRect(x: 0, y: 100, width: 1440, height: 900)
        let screenFrame = NSRect(x: 0, y: 0, width: 1440, height: 1000)
        let size = CGSize(width: 144, height: 32)
        let origin = MiniVoiceHUDLayout.pillOrigin(
            in: visibleFrame,
            screenFrame: screenFrame,
            size: size
        )

        XCTAssertEqual(origin.x, 648, accuracy: 0.5)
        XCTAssertEqual(
            origin.y,
            visibleFrame.minY + MiniVoiceHUDLayout.bottomInsetAboveDock,
            accuracy: 0.5
        )
        XCTAssertEqual(
            MiniVoiceHUDLayout.defaultPillBottomY(in: visibleFrame, screenFrame: screenFrame),
            origin.y,
            accuracy: 0.5
        )
    }

    func testPillLiftsAboveClipboardDockObstruction() {
        let visibleFrame = NSRect(x: 0, y: 100, width: 1440, height: 900)
        let screenFrame = NSRect(x: 0, y: 0, width: 1440, height: 1000)
        let size = CGSize(width: 144, height: 32)
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

    func testCaptionStacksAbovePill() {
        let pillBottomY: CGFloat = 200
        let size = CGSize(width: 180, height: MiniVoiceHUDLayout.captionShellHeight)
        let origin = MiniVoiceHUDLayout.captionOrigin(
            pillBottomY: pillBottomY,
            size: size,
            centerX: 400
        )

        XCTAssertEqual(origin.y, pillBottomY + MiniVoiceHUDLayout.pillHeight + MiniVoiceHUDLayout.captionGap, accuracy: 0.5)
        XCTAssertEqual(origin.x, 310, accuracy: 0.5)
    }

    func testTranscribeFailureRoutesMessageToCaptionAbovePill() {
        let message = "Couldn't transcribe"
        let pill = MiniVoiceHUDPill(state: .error(message))

        XCTAssertTrue(VoiceHUDCopy.routesFailureMessageToCaptionAbovePill(message))
        XCTAssertEqual(VoiceHUDCopy.captionMessage(forFailure: message), VoiceHUDCopy.Pill.couldntTranscribe)
        XCTAssertNil(VoiceHUDCopy.blockingAlert(for: message))
        XCTAssertEqual(pill.label, "")
        XCTAssertEqual(pill.leading, .warningTriangle)
    }

    func testAvailabilityFailureRoutesMessageToCaptionAbovePill() {
        let message = "No ASR model installed. Download a model from Voice → Models before dictating."
        let pill = MiniVoiceHUDPill(state: .error(message))

        XCTAssertTrue(VoiceHUDCopy.routesFailureMessageToCaptionAbovePill(message))
        XCTAssertEqual(VoiceHUDCopy.captionMessage(forFailure: message), VoiceHUDCopy.Pill.voiceUnavailable)
        XCTAssertEqual(pill.label, "")
        XCTAssertEqual(pill.leading, .warningTriangle)
    }

    func testVoiceHUDAppearanceFallsBackToGlass() {
        XCTAssertEqual(VoiceHUDAppearance(rawValue: "glass"), .glass)
        XCTAssertEqual(VoiceHUDAppearance(rawValue: "graphite"), .graphite)
        XCTAssertEqual(VoiceHUDAppearance(rawValue: "invalid") ?? .glass, .glass)
    }

    func testVoiceHUDWindowLayeringIsAboveClipboardDock() {
        XCTAssertGreaterThan(
            VoiceHUDWindowLayering.windowLevel.rawValue,
            NSWindow.Level.popUpMenu.rawValue
        )
        XCTAssertGreaterThan(
            VoiceHUDWindowLayering.windowLevel.rawValue,
            FloatingHUDWindowLayering.windowLevel.rawValue
        )
    }

    func testDefaultStatesUseCenteredNativeWidths() {
        let recordingSize = CGSize(width: 144, height: 32)
        XCTAssertEqual(MiniVoiceHUDLayout.size(for: .startingMic), recordingSize)
        XCTAssertEqual(MiniVoiceHUDLayout.size(for: .recording(level: 0.4)), recordingSize)
        XCTAssertEqual(MiniVoiceHUDLayout.size(for: .transcribing(.asr)), CGSize(width: 164, height: 32))
        XCTAssertEqual(MiniVoiceHUDLayout.size(for: .transcribing(.asr, isSlow: true)), CGSize(width: 172, height: 32))
        XCTAssertEqual(MiniVoiceHUDLayout.size(for: .clipboardFallback), recordingSize)
        XCTAssertEqual(MiniVoiceHUDLayout.size(for: .cancelled), CGSize(width: 184, height: 32))
    }

    func testStartingMicMapsToWaveformOnlyWithoutLabel() {
        let pill = MiniVoiceHUDPill(state: .startingMic)

        XCTAssertEqual(pill.label, "")
        XCTAssertEqual(pill.leading, .waveformBars)
        XCTAssertEqual(pill.actionAvailability, .none)
    }

    func testRecordingMapsToWaveformOnlyWithoutCenterLabel() {
        let pill = MiniVoiceHUDPill(state: .recording(level: 0.4))

        XCTAssertEqual(pill.label, "")
        XCTAssertEqual(pill.leading, .waveformBars)
        XCTAssertEqual(pill.actionAvailability, .none)
        XCTAssertEqual(pill.secondaryAction, .none)
    }

    func testToggleRecordingHasNoVisibleFinishChrome() {
        let pill = MiniVoiceHUDPill(
            state: .recording(level: 0.4),
            chrome: .init(activationMode: .toggle)
        )

        XCTAssertEqual(pill.actionAvailability, .none)
        XCTAssertEqual(pill.secondaryAction, .none)
    }

    func testTranscribingPillUsesCenteredTextWithoutSparkle() {
        let pill = MiniVoiceHUDPill(state: .transcribing(.asr))

        XCTAssertEqual(pill.label, VoiceHUDCopy.Pill.transcribing)
        XCTAssertEqual(pill.leading, .none)
        XCTAssertEqual(pill.actionAvailability, .none)
        XCTAssertFalse(pill.isCancellable)
    }

    func testPastingSubphaseStillShowsTranscribingLabel() {
        let pill = MiniVoiceHUDPill(state: .transcribing(.pasting))

        XCTAssertEqual(pill.label, VoiceHUDCopy.Pill.transcribing)
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
        XCTAssertEqual(pill.leading, .none)
        XCTAssertEqual(pill.actionAvailability, .dismissTerminal)
    }

    func testErrorPillUsesSpecificPermissionCopy() {
        let pill = MiniVoiceHUDPill(state: .error("Microphone permission denied"))

        XCTAssertEqual(pill.label, VoiceHUDCopy.Pill.micPermission)
        XCTAssertEqual(pill.leading, .none)
    }

    func testPasteTimeoutUsesTerminalCopyNotStillWorking() {
        let pill = MiniVoiceHUDPill(state: .error("Paste timed out"))
        XCTAssertEqual(pill.label, VoiceHUDCopy.Pill.couldntPaste)
    }

    func testCancelledPillOffersRestore() {
        let pill = MiniVoiceHUDPill(state: .cancelled)

        XCTAssertEqual(pill.label, VoiceHUDCopy.Pill.cancelled)
        XCTAssertEqual(pill.actionAvailability, .restore)
        XCTAssertTrue(pill.isRestorable)
    }

    func testClipboardFallbackUsesCenteredCopy() {
        let pill = MiniVoiceHUDPill(state: .clipboardFallback)
        XCTAssertEqual(pill.label, VoiceHUDCopy.Pill.clipboardFallback)

        let reminderPill = MiniVoiceHUDPill(state: .reminderAdded)
        XCTAssertEqual(reminderPill.label, VoiceHUDCopy.Pill.reminderAdded)
        XCTAssertEqual(reminderPill.leading, .checkInCircle)
        XCTAssertEqual(pill.leading, .none)
    }

    @MainActor
    func testBootCurveReachesFiftyPercentAtOneSecond() {
        let progress = MiniVoiceThinkingProgressBridge.bootProgress(at: 1.0)
        XCTAssertEqual(progress, 0.50, accuracy: 0.02)
    }

    @MainActor
    func testBootCurveCapsNearSixtyThreePercentAtTenSeconds() {
        let progress = MiniVoiceThinkingProgressBridge.bootProgress(at: 10.0)
        XCTAssertEqual(progress, 0.63, accuracy: 0.01)
    }

    @MainActor
    func testThinkingProgressIsMonotonicAndSnapsAtCompletion() {
        let bridge = MiniVoiceThinkingProgressBridge()
        bridge.applyStreamProgress(0.2)
        XCTAssertEqual(bridge.displayWipe, 0.2, accuracy: 0.0001)
        bridge.applyStreamProgress(0.15)
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

    func testVoiceHUDCopyEllipsisPolicy() {
        XCTAssertTrue(VoiceHUDCopy.Pill.stillWorking.hasSuffix("..."))
        XCTAssertFalse(VoiceHUDCopy.Pill.cancelled.hasSuffix("..."))
        XCTAssertFalse(VoiceHUDCopy.Pill.clipboardFallback.hasSuffix("..."))
    }
}

private func rgbComponents(_ color: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
    let ns = NSColor(color)
    guard let rgb = ns.usingColorSpace(.deviceRGB) else { return (0, 0, 0) }
    return (rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
}
