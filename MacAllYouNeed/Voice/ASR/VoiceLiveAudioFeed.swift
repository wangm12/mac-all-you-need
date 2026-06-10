import Core
import Foundation

/// Tracks how much of the capture buffer has been fed into a live ASR session.
/// The coordinator runs one polling task that calls `drain` — never the audio tap.
actor VoiceLiveAudioFeed {
    private var cursor = 0

    func reset() {
        cursor = 0
    }

    func drain(
        snapshot: (samples: [Float], sampleRate: Double),
        into session: any VoiceLiveTranscriptionSession
    ) async throws {
        let samples = snapshot.samples
        guard cursor < samples.count else { return }
        let chunk = Array(samples[cursor..<samples.count])
        cursor = samples.count
        try await session.enqueueAudio(samples: chunk, sampleRate: snapshot.sampleRate)
    }
}
