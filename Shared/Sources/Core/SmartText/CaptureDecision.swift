import Foundation

public enum CaptureDecision: Equatable, Sendable {
    case skip(SkipReason)
    case keep(detectedTypeJSON: String, autoCleanedText: String?)
}

public enum SmartCapturePolicy {
    public static func decideText(
        _ text: String,
        windowTitle: String?,
        pasteboardTypes: [String],
        sensitiveEnabled: Bool,
        autoCleanLinks: Bool
    ) -> CaptureDecision {
        if sensitiveEnabled,
           let reason = SensitiveContentFilter.shouldSkip(
               text: text, windowTitle: windowTitle, pasteboardTypes: pasteboardTypes
           )
        {
            return .skip(reason)
        }
        let detection = SmartTextService.analyze(text: text)
        let json = (try? detection.encodedJSON()) ?? #"{"type":{"plain":{}}}"#
        let cleaned: String?
        if autoCleanLinks, case .url = detection.type {
            cleaned = detection.linkClean?.cleaned
        } else {
            cleaned = nil
        }
        return .keep(detectedTypeJSON: json, autoCleanedText: cleaned)
    }
}
