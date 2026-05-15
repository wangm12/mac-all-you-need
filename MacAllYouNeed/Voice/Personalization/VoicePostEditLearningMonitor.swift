import AppKit
import Core
import Foundation
import OSLog

private let log = Logger(subsystem: "com.macallyouneed.voice", category: "learning")

/// Observes the focused AX element after a paste and captures an edit sample
/// if the user modifies the pasted text within 60 seconds.
///
/// Two-phase design:
/// 1. First stable read: confirm the pasted text is present in the document (anchoring).
///    If the document doesn't contain the pasted text, skip — we're not in the right field.
/// 2. Idle detection: once the value has been stable for idleThreshold, capture the
///    final document value as "after". Sample = (pastedText, finalValue).
///
/// The LLM summarizer receives both and can infer what style corrections were made.
/// finalValue is capped at maxByteLength to avoid capturing large documents.
@MainActor
final class VoicePostEditLearningMonitor {
    struct Config {
        var pollInterval: Duration = .milliseconds(200)
        var idleThreshold: Duration = .milliseconds(1500)
        var maxObservationSeconds: Int = 60
        var maxByteLength: Int = 2048
    }

    private let config: Config
    private let isCancelledCheck: () -> Bool
    private let matchesFocused: (AXTargetSnapshot) -> Bool
    private let readCurrentValue: (AXTargetSnapshot) -> String?

    /// Production init — uses real AX reader.
    convenience init(config: Config = Config()) {
        self.init(
            config: config,
            isCancelled: { false },
            matchesFocused: { AXFocusedTextReader.currentFocusedMatches($0) },
            readCurrentValue: { AXFocusedTextReader.readValue(matching: $0) }
        )
    }

    /// Testable init — inject AX operations.
    init(
        config: Config,
        isCancelled: @escaping () -> Bool,
        matchesFocused: @escaping (AXTargetSnapshot) -> Bool,
        readCurrentValue: @escaping (AXTargetSnapshot) -> String?
    ) {
        self.config = config
        self.isCancelledCheck = isCancelled
        self.matchesFocused = matchesFocused
        self.readCurrentValue = readCurrentValue
    }

    func observe(
        pastedText: String,
        transcriptID: String?,
        contextID: String,
        isAutoSubmitContext: Bool,
        snapshot: AXTargetSnapshot
    ) async -> VoicePersonalizationSampleDraft? {
        guard !isAutoSubmitContext else { return nil }
        guard !pastedText.isEmpty, pastedText.utf8.count <= config.maxByteLength else { return nil }

        let deadline = ContinuousClock.now + .seconds(config.maxObservationSeconds)

        // Phase 1: wait for first stable read that confirms the pasted text is present.
        var anchorConfirmed = false
        var lastValue: String? = nil
        var lastChangeTime = ContinuousClock.now

        while ContinuousClock.now < deadline {
            guard !Task.isCancelled, !isCancelledCheck() else { return nil }
            guard matchesFocused(snapshot) else { return nil }

            guard let value = readCurrentValue(snapshot) else {
                try? await Task.sleep(for: config.pollInterval)
                continue
            }

            if value != lastValue {
                lastValue = value
                lastChangeTime = ContinuousClock.now

                // Confirm anchor on first read: pasted text must be visible in the document.
                if !anchorConfirmed {
                    guard value.contains(pastedText) else { return nil }
                    anchorConfirmed = true
                }
            }

            let idle = ContinuousClock.now - lastChangeTime
            if anchorConfirmed, idle >= config.idleThreshold, let finalValue = lastValue {
                return makeDraft(
                    pastedText: pastedText,
                    finalValue: finalValue,
                    transcriptID: transcriptID,
                    contextID: contextID
                )
            }

            try? await Task.sleep(for: config.pollInterval)
        }

        return nil
    }

    // MARK: - Private

    private func makeDraft(
        pastedText: String,
        finalValue: String,
        transcriptID: String?,
        contextID: String
    ) -> VoicePersonalizationSampleDraft? {
        guard finalValue != pastedText else { return nil }
        guard finalValue.utf8.count <= config.maxByteLength else { return nil }

        log.debug(
            "Learning sample: before=\(pastedText.utf8.count, privacy: .public)B after=\(finalValue.utf8.count, privacy: .public)B"
        )

        return VoicePersonalizationSampleDraft(
            contextID: contextID,
            transcriptID: transcriptID,
            before: pastedText,
            after: finalValue,
            diffOffset: 0,
            diffLength: pastedText.count
        )
    }
}
