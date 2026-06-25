import AppKit
import Foundation

/// Governs when live ASR partials may replace the pill's **Listening** label.
/// Partials must be stable and wide enough to read; text is truncated by pixel width.
@MainActor
final class VoicePartialDisplayPolicy {
    private var lastPartial = ""
    private var stableSince: Date?
    private let stableDuration: TimeInterval = 0.4
    private let minimumCharacterCount = 3

    func reset() {
        lastPartial = ""
        stableSince = nil
    }

    /// Returns display text for the pill center, or `nil` to keep **Listening**.
    func displayText(
        for partial: String,
        maxLabelWidth: CGFloat,
        fontSize: CGFloat = MiniVoiceHUDLayout.fontSize
    ) -> String? {
        let trimmed = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumCharacterCount else {
            lastPartial = trimmed
            stableSince = nil
            return nil
        }

        if trimmed != lastPartial {
            lastPartial = trimmed
            stableSince = Date()
            return nil
        }

        guard let stableSince,
              Date().timeIntervalSince(stableSince) >= stableDuration
        else {
            return nil
        }

        return Self.truncateToWidth(trimmed, maxWidth: maxLabelWidth, fontSize: fontSize)
    }

    nonisolated static func truncateToWidth(_ text: String, maxWidth: CGFloat, fontSize: CGFloat) -> String {
        guard maxWidth > 0, !text.isEmpty else { return text }
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        if (text as NSString).size(withAttributes: attributes).width <= maxWidth {
            return text
        }
        var low = 0
        var high = text.count
        while low < high {
            let mid = (low + high + 1) / 2
            let candidate = String(text.suffix(mid))
            let width = (candidate as NSString).size(withAttributes: attributes).width
            if width <= maxWidth {
                low = mid
            } else {
                high = mid - 1
            }
        }
        guard low > 0 else { return "…" }
        let tail = String(text.suffix(low))
        return tail.count < text.count ? "…\(tail)" : tail
    }
}
