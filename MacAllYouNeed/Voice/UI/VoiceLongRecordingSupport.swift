import AppKit
import Core
import CoreGraphics
import Foundation

/// Controls whether live partial text may appear in the voice pill.
enum VoicePartialPrivacySettings {
    private static let hidePartialsKey = "voice.partial.hideLivePreview"

    static var hideLivePreview: Bool {
        AppGroupSettings.defaults.bool(forKey: hidePartialsKey)
    }

    /// When screen sharing is active, partials are suppressed for privacy.
    static var shouldSuppressPartials: Bool {
        hideLivePreview || isScreenSharingActive
    }

    private static var isScreenSharingActive: Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return list.contains { info in
                let owner = info[kCGWindowOwnerName as String] as? String ?? ""
                let name = info[kCGWindowName as String] as? String ?? ""
                let combined = "\(owner) \(name)".lowercased()
                return combined.contains("screen") && combined.contains("share")
            }
    }
}

/// Fires soft alerts when a recording runs long.
@MainActor
enum VoiceLongRecordingNotifier {
    private static var task: Task<Void, Never>?

    static func startMonitoring(
        startedAt: Date,
        onMinuteMark: @escaping @MainActor (TimeInterval) -> Void,
        onFinalMinute: @escaping @MainActor (TimeInterval) -> Void
    ) {
        task?.cancel()
        task = Task { @MainActor in
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(startedAt)
                if elapsed >= 60, Int(elapsed) % 30 == 0 {
                    onMinuteMark(elapsed)
                }
                let maxSeconds = VoiceTuning.default.maxRecordingDurationSeconds
                let remaining = maxSeconds - elapsed
                if remaining <= 60, remaining > 0, Int(remaining) % 15 == 0 {
                    onFinalMinute(remaining)
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    static func stop() {
        task?.cancel()
        task = nil
    }
}
