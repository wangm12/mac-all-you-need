import Core
import Foundation
@testable import MacAllYouNeed
import XCTest

final class VoiceTranscriptHistoryPresentationTests: XCTestCase {
    func testClockTimeUsesShortTimeForToday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 12))!
        let endedAt = calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 11, minute: 45))!

        let label = VoiceTranscriptHistoryMetadata.clockTime(endedAt, now: now)

        XCTAssertFalse(label.contains("m ago"))
        XCTAssertFalse(label == "11m")
        XCTAssertTrue(label.contains("45") || label.contains("11"))
    }

    func testMetadataLineMapsTypelessImportAndUnknownLanguage() {
        let transcript = VoiceTranscript(
            id: "test-id",
            startedAt: Date(),
            endedAt: Date(),
            durationMs: 90_000,
            rawText: "hello",
            cleanedText: "hello",
            appBundleID: nil,
            language: .unknown,
            modelIdentifier: TypelessLanguageMapper.typelessImportModelIdentifier,
            audioPath: nil
        )

        let line = VoiceTranscriptHistoryMetadata.line(for: transcript)

        XCTAssertTrue(line.contains("Typeless"))
        XCTAssertTrue(line.contains("Auto"))
        XCTAssertFalse(line.contains("unknown"))
        XCTAssertFalse(line.contains("typeless-import"))
    }
}
