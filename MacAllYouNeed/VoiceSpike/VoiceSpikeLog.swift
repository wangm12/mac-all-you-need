import Foundation
import OSLog

/// Logger and feature flag for the Voice technical spike.
/// Throwaway: deleted when Plan 8a starts.
enum VoiceSpikeLog {
    static let logger = Logger(subsystem: "com.macallyouneed.spike", category: "voice")
    static let signposter = OSSignposter(subsystem: "com.macallyouneed.spike", category: "voice")

    static func isSpikeEnabled(arguments: [String] = CommandLine.arguments) -> Bool {
        arguments.contains("--voice-spike")
    }
}
