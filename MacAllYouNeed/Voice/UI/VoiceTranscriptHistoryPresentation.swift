import Core
import Foundation

enum VoiceTranscriptHistoryMetadata {
    static func line(for transcript: VoiceTranscript, now: Date = Date()) -> String {
        detailLine(for: transcript, now: now)
    }

    /// Metadata without the status label — status is shown as a row tag.
    static func detailLine(for transcript: VoiceTranscript, now: Date = Date()) -> String {
        let parts = [
            clockTime(transcript.endedAt, now: now),
            languageLabel(transcript.language),
            modelLabel(transcript.modelIdentifier),
            durationLabel(ms: transcript.durationMs)
        ]
        return parts.joined(separator: " · ")
    }

    static func statusPresentation(for transcript: VoiceTranscript) -> VoiceTranscriptStatusPresentation {
        switch transcript.status {
        case .success:
            return .success
        case .retriedFrom:
            return .retried
        case .failed:
            if transcript.failedStage == .cancelled {
                return .cancelled
            }
            if let stage = transcript.failedStage {
                return .failed(stage: stage.rawValue)
            }
            return .failed(stage: nil)
        }
    }

    /// Wall-clock time for history rows, e.g. `11:45 AM` today or `May 28, 11:45 AM` for older entries.
    static func clockTime(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let time = timeFormatter.string(from: date)

        if calendar.isDateInToday(date) {
            return time
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday \(time)"
        }
        let dayAndTime = DateFormatter()
        dayAndTime.locale = .current
        dayAndTime.timeZone = .current
        dayAndTime.setLocalizedDateFormatFromTemplate("MMMd jmm")
        return dayAndTime.string(from: date)
    }

    static func languageLabel(_ language: VoiceLanguage) -> String {
        switch language {
        case .english: "English"
        case .chinese: "Chinese"
        case .mixed: "Mixed"
        case .unknown: "Auto"
        }
    }

    static func modelLabel(_ modelIdentifier: String) -> String {
        switch modelIdentifier {
        case TypelessLanguageMapper.typelessImportModelIdentifier:
            return "Typeless"
        case "qwen3-asr-0.6b-f32":
            return "Qwen3 ASR"
        case let id where id.hasPrefix("groq-"):
            return "Groq ASR"
        default:
            return modelIdentifier
        }
    }

    static func durationLabel(ms: Int) -> String {
        let seconds = Double(ms) / 1000.0
        if seconds < 60 { return String(format: "%.1f s", seconds) }
        let minutes = Int(seconds / 60)
        let remainder = Int(seconds.truncatingRemainder(dividingBy: 60))
        return "\(minutes)m \(remainder)s"
    }

    static func statusLabel(_ transcript: VoiceTranscript) -> String {
        statusPresentation(for: transcript).label
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

enum VoiceTranscriptStatusPresentation: Equatable {
    case success
    case retried
    case cancelled
    case failed(stage: String?)

    var label: String {
        switch self {
        case .success: return "Success"
        case .retried: return "Retried"
        case .cancelled: return "Cancelled"
        case let .failed(stage):
            if let stage { return "Failed (\(stage))" }
            return "Failed"
        }
    }
}
