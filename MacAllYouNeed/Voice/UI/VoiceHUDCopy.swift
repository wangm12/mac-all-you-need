import Foundation

/// Centralized voice HUD copy, timing, and presentation priority.
enum VoiceHUDCopy {
    enum Priority: Int, Comparable {
        case blocking = 0
        case terminal = 1
        case activeRisk = 2
        case sessionInfo = 3
        case education = 4

        static func < (lhs: Priority, rhs: Priority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    // MARK: - Main pill

    enum Pill {
        static let starting = "Starting"
        static let listening = "Listening"
        static let transcribing = "Transcribing"
        static let inserted = "Inserted"
        static let stillWorking = "Still working..."
        static let clipboardFallback = "⌘V to paste"
        static let reminderAdded = "Added to reminder"
        static let cancelled = "Cancelled"
        static let undo = "Undo"
        static let noSpeech = "No speech detected"
        static let micPermission = "Mic permission needed"
        static let micUnavailable = "Mic unavailable"
        static let couldntTranscribe = "Couldn't transcribe"
        static let couldntPaste = "Couldn't paste"
        static let voiceUnavailable = "Voice unavailable"
        static let accessibilityNeeded = "Accessibility needed"
    }

    // MARK: - Caption / helper

    enum Caption {
        static let startingMic = "Starting microphone..."
        static let textCopied = "Text copied to clipboard"
        static let takingLonger = "Taking longer than usual..."
        static let longRecordingSlow = "Long recordings can take a little longer"
        static let previousPending = "Still transcribing your last recording"
        static let inputQuiet = "Input seems quiet"
        static let noInput = "No input detected"
        static let releaseToFinish = "Release to finish"
        static let pressAgainToFinish = "Press Fn again to finish"
        static let pressEscToCancel = "Press Esc to cancel"
        static let usingSelectedMic = "Using selected microphone"
        static let limitReached = "Limit reached. Transcribing captured audio"
        static let connectionSlow = "Connection is slow"
        static let modelLoading = "Loading voice model..."

        static func usingMic(_ name: String) -> String {
            "Using \(truncateMiddle(name, maxLength: 36))"
        }

        static func toApp(_ name: String) -> String {
            "To \(truncateMiddle(name, maxLength: 32))"
        }

        static func recordingDuration(minutes: Int, seconds: Int) -> String {
            String(format: "Recording %d:%02d", minutes, seconds)
        }

        static func recordingWillStop(in seconds: Int) -> String {
            "Recording will stop in \(seconds)s"
        }
    }

    // MARK: - Blocking alerts

    enum Blocking {
        static let micPermissionTitle = "Microphone permission required"
        static let micPermissionBody = "Allow microphone access to use dictation."
        static let accessibilityTitle = "Accessibility permission required"
        static let accessibilityBody = "Allow MAYN to paste into other apps."
        static let micUnavailableTitle = "Couldn't access your microphone"
        static let micUnavailableBody = "Another app may be using it, or the device was disconnected."
        static let pasteFallbackTitle = "Couldn't paste automatically"
        static let pasteFallbackBody =
            "Text was copied to clipboard. Click where you want it, then press ⌘V."
        static let transcribeFailedTitle = "Couldn't transcribe"
        static let transcribeFailedBody = "Something went wrong while transcribing."
        static let previousPendingTitle = "Still transcribing your last recording"
        static let previousPendingBody = "Wait for it to finish before starting another."
        static let secureInputTitle = "Secure input is active"
        static let secureInputBody = "This app may block automatic paste."
    }

    enum Action {
        static let openSettings = "Open Settings"
        static let dismiss = "Dismiss"
        static let retry = "Retry"
        static let keepWaiting = "Keep Waiting"
        static let cancelPrevious = "Cancel Previous"
        static let copyText = "Copy Text"
    }

    // MARK: - Timing (seconds)

    enum Timing {
        static let micWarmupCaptionThreshold: TimeInterval = 0.7
        static let usingMicDuration: TimeInterval = 1.9
        static let targetAppDuration: TimeInterval = 1.7
        static let educationDuration: TimeInterval = 2.0
        static let quietCaptionDuration: TimeInterval = 3.0
        static let slowPillThreshold: TimeInterval = 3.5
        static let slowCaptionThreshold: TimeInterval = 6.0
        static let clipboardFallbackDuration: TimeInterval = 4.0
        static let reminderAddedDuration: TimeInterval = 2.0
        static let insertedDuration: TimeInterval = 0.75
        static let successWipeHold: TimeInterval = 0.30
        static let terminalAutoDismiss: TimeInterval = 3.0
        static let previousPendingThrottle: TimeInterval = 2.0
    }

    // MARK: - Pill label mapping

    /// Failures that read better as a caption chip above the hub pill.
    static func routesFailureMessageToCaptionAbovePill(_ message: String) -> Bool {
        isTranscribeFailure(message) || isAvailabilityFailure(message)
    }

    static func isAvailabilityFailure(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("no asr model")
            || lower.contains("voice unavailable")
            || lower.contains("download a model")
            || (lower.contains("model") && lower.contains("unavailable"))
    }

    static func isTranscribeFailure(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("couldn't transcribe")
            || (lower.contains("asr") && lower.contains("fail"))
    }

    static func captionMessage(forFailure message: String) -> String? {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let pill = pillLabel(for: message)
        if trimmed.caseInsensitiveCompare(pill) == .orderedSame {
            return nil
        }

        // Availability failures use a short pill label; keep the full failure text in the caption.
        if isAvailabilityFailure(message) {
            return trimmed
        }

        // Transcribe failures already read clearly from the pill label alone.
        if isTranscribeFailure(message) {
            return nil
        }

        return nil
    }

    static func pillLabel(for message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("permission") {
            if lower.contains("accessibility") { return Pill.accessibilityNeeded }
            return Pill.micPermission
        }
        if lower.contains("voice unavailable")
            || lower.contains("no asr model")
            || lower.contains("download a model")
            || lower.contains("model") && lower.contains("unavailable") {
            return Pill.voiceUnavailable
        }
        if lower.contains("microphone") || lower.contains("mic unavailable") {
            return Pill.micUnavailable
        }
        if lower.contains("no usable audio") || lower.contains("no speech") || lower.contains("transcript was empty") {
            return Pill.noSpeech
        }
        if lower.contains("couldn't transcribe") || lower.contains("asr") && lower.contains("fail") {
            return Pill.couldntTranscribe
        }
        if lower.contains("paste timed out") || lower.contains("couldn't paste") {
            return Pill.couldntPaste
        }
        if lower.contains("paste") || lower.contains("⌘v") || lower.contains("clipboard") {
            return Pill.clipboardFallback
        }
        if lower.contains("timed out") || lower.contains("timeout") {
            return Pill.stillWorking
        }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 22 { return trimmed }
        return String(trimmed.prefix(20)) + "..."
    }

    static func blockingAlert(for message: String) -> (title: String, body: String)? {
        let lower = message.lowercased()
        if lower.contains("accessibility") && lower.contains("permission") {
            return (Blocking.accessibilityTitle, Blocking.accessibilityBody)
        }
        if lower.contains("permission") {
            return (Blocking.micPermissionTitle, Blocking.micPermissionBody)
        }
        if lower.contains("microphone") || lower.contains("mic unavailable") {
            return (Blocking.micUnavailableTitle, Blocking.micUnavailableBody)
        }
        if lower.contains("paste") && (lower.contains("clipboard") || lower.contains("⌘v")) {
            return (Blocking.pasteFallbackTitle, Blocking.pasteFallbackBody)
        }
        if isTranscribeFailure(message) {
            return nil
        }
        if lower.contains("secure input") {
            return (Blocking.secureInputTitle, Blocking.secureInputBody)
        }
        return nil
    }

    private static func truncateMiddle(_ value: String, maxLength: Int) -> String {
        guard value.count > maxLength else { return value }
        let keep = max(4, (maxLength - 1) / 2)
        let start = value.prefix(keep)
        let end = value.suffix(keep)
        return "\(start)…\(end)"
    }
}
