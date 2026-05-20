@testable import MacAllYouNeed
import XCTest

final class VoiceLoggingPrivacyTests: XCTestCase {
    func testVoiceOperationalLogsDoNotPubliclyIncludeTranscriptContent() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let checkedFiles = [
            "MacAllYouNeed/Voice/VoiceCoordinator.swift",
            "MacAllYouNeed/Voice/Cleanup/VoiceCleanupPipeline.swift"
        ]

        for relativePath in checkedFiles {
            let source = try String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
            XCTAssertFalse(source.contains(" privacy: .public) text:"), relativePath)
            XCTAssertFalse(source.contains("output: \\("), relativePath)
            XCTAssertFalse(source.contains("cleanedText.prefix"), relativePath)
            XCTAssertFalse(source.contains("result.text.prefix"), relativePath)
        }
    }
}
