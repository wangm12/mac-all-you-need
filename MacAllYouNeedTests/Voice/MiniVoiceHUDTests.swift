@testable import MacAllYouNeed
import AppKit
import SwiftUI
import XCTest

final class MiniVoiceHUDTests: XCTestCase {
    func testV8UniversalPillSize() {
        XCTAssertEqual(MiniVoiceHUDLayout.pillWidth, 144)
        XCTAssertEqual(MiniVoiceHUDLayout.pillHeight, 32)
        XCTAssertEqual(MiniVoiceHUDLayout.iconSize, 14)
        XCTAssertEqual(MiniVoiceHUDLayout.leftSlotCenter, 20)
        XCTAssertEqual(MiniVoiceHUDLayout.rightSlotCenter, 124)
    }

    func testAllDefaultStatesShareUniversalPillSize() {
        let expected = CGSize(width: 144, height: 32)
        for state in [
            MiniVoiceHUD.State.recording(level: 0.4),
            .transcribing(.asr),
            .transcribing(.cleanup(progress: 0)),
            .cancelled,
            .noSpeech("x"),
            .error("y"),
            .idlePreview
        ] {
            XCTAssertEqual(MiniVoiceHUDLayout.size(for: state), expected,
                           "state \(state) must use universal v8 pill size")
        }
    }

    func testRecordingMapsToListeningWithWaveformAndStopAction() {
        let pill = MiniVoiceHUDPill(state: .recording(level: 0.4))

        XCTAssertEqual(pill.label, "Listening")
        XCTAssertEqual(pill.leading, .waveformBars)
        XCTAssertTrue(pill.isStoppable)
        XCTAssertFalse(pill.isTerminal)
    }

    func testTranscribingPillUsesAISparkleAndIsStoppable() {
        let pill = MiniVoiceHUDPill(state: .transcribing(.asr))

        XCTAssertEqual(pill.label, "Transcribing")
        XCTAssertEqual(pill.leading, .aiSparkle)
        XCTAssertTrue(pill.isStoppable)
        XCTAssertFalse(pill.isTerminal)
    }

    func testTranscribingCleanupPillMatchesAsrChrome() {
        let pill = MiniVoiceHUDPill(state: .transcribing(.cleanup(progress: 0.3)))

        XCTAssertEqual(pill.label, "Transcribing")
        XCTAssertEqual(pill.leading, .aiSparkle)
        XCTAssertTrue(pill.isStoppable)
        XCTAssertFalse(pill.isTerminal)
    }

    func testThinkingTrackIsLighterThanBlackFill() {
        let track = rgbComponents(MiniVoiceHUDPalette.pillThinkingTrack)
        let black = rgbComponents(MiniVoiceHUDPalette.pillBlack)
        XCTAssertGreaterThan(track.r + track.g + track.b, black.r + black.g + black.b)
    }

    func testNoSpeechPillUsesWarningTriangle() {
        let pill = MiniVoiceHUDPill(state: .noSpeech("anything"))

        XCTAssertEqual(pill.label, "No speech")
        XCTAssertEqual(pill.leading, .warningTriangle)
        XCTAssertFalse(pill.isStoppable)
        XCTAssertTrue(pill.isTerminal)
    }

    func testErrorPillMapsToFailedWithWarningTriangle() {
        let pill = MiniVoiceHUDPill(state: .error("some api blew up"))

        XCTAssertEqual(pill.label, "Failed")
        XCTAssertEqual(pill.leading, .warningTriangle)
        XCTAssertFalse(pill.isStoppable)
        XCTAssertTrue(pill.isTerminal)
    }

    func testNoUsableAudioErrorMessageDemotesToNoSpeechPill() {
        let pill = MiniVoiceHUDPill(state: .error("No usable audio captured"))

        XCTAssertEqual(pill.label, "No speech")
        XCTAssertEqual(pill.leading, .warningTriangle)
    }

    func testTranscriptWasEmptyErrorMessageDemotesToNoSpeechPill() {
        let pill = MiniVoiceHUDPill(state: .error("Transcript was empty"))

        XCTAssertEqual(pill.label, "No speech")
        XCTAssertEqual(pill.leading, .warningTriangle)
    }

    func testCancelledPillUsesXInCircleAndOffersUndo() {
        let pill = MiniVoiceHUDPill(state: .cancelled)

        XCTAssertEqual(pill.label, "Cancelled")
        XCTAssertEqual(pill.leading, .xInCircle)
        XCTAssertFalse(pill.isStoppable)
        XCTAssertFalse(pill.isTerminal)
        XCTAssertTrue(pill.isUndoable)
    }

    func testCancelledStateSharesUniversalPillSize() {
        XCTAssertEqual(MiniVoiceHUDLayout.size(for: .cancelled),
                       CGSize(width: 144, height: 32))
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
