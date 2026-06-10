@testable import Core
@testable import MacAllYouNeed
import XCTest

@MainActor
final class VoiceLiveAudioFeedTests: XCTestCase {
    private final class RecordingLiveSession: VoiceLiveTranscriptionSession, @unchecked Sendable {
        private(set) var chunks: [[Float]] = []
        private(set) var cancelled = false

        func enqueueAudio(samples: [Float], sampleRate _: Double) async throws {
            chunks.append(samples)
        }

        func finish() async throws -> VoiceTranscriptionResult {
            VoiceTranscriptionResult(text: "done", language: .english, modelIdentifier: "stub")
        }

        func cancel() async {
            cancelled = true
        }
    }

    func testDrain_feedsOnlyNewSamplesInOrder() async throws {
        let feed = VoiceLiveAudioFeed()
        let session = RecordingLiveSession()
        await feed.reset()

        try await feed.drain(snapshot: (samples: [0.1, 0.2, 0.3], sampleRate: 48_000), into: session)
        try await feed.drain(snapshot: (samples: [0.1, 0.2, 0.3, 0.4, 0.5], sampleRate: 48_000), into: session)

        XCTAssertEqual(session.chunks.count, 2)
        XCTAssertEqual(session.chunks[0], [0.1, 0.2, 0.3])
        XCTAssertEqual(session.chunks[1], [0.4, 0.5])
    }
}
