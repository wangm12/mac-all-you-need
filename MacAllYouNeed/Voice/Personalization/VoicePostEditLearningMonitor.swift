import AppKit
import Core
import Foundation
import OSLog

private let log = Logger(subsystem: "com.macallyouneed.voice", category: "learning")

/// Observes the focused AX element after a paste and captures an edit sample
/// if the user modifies the pasted text within 60 seconds.
///
/// Two-phase design:
/// 1. Anchor: first stable AX value read that contains the pasted text. Records
///    the initial document value so surrounding context can be stripped later.
/// 2. Idle detection: poll until 1.5s of no value change, then extract the edit
///    span via common-prefix/suffix comparison between the initial and final values.
///    Only the changed region is stored — surrounding document content is excluded.
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
        isCancelledCheck = isCancelled
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

        var anchorConfirmed = false
        var initialValue: String? = nil
        var lastValue: String? = nil
        var lastChangeTime = ContinuousClock.now

        while ContinuousClock.now < deadline {
            guard !Task.isCancelled, !isCancelledCheck() else { return nil }
            guard matchesFocused(snapshot) else { return nil }

            guard let value = readCurrentValue(snapshot) else {
                try? await Task.sleep(for: config.pollInterval)
                continue
            }

            if !anchorConfirmed {
                // AX can briefly report the pre-paste document value while the
                // paste is still in flight. Keep polling until the pasted text
                // appears, focus changes, or the deadline expires.
                if value.contains(pastedText) {
                    anchorConfirmed = true
                    initialValue = value
                    lastValue = value
                    lastChangeTime = ContinuousClock.now
                }
                try? await Task.sleep(for: config.pollInterval)
                continue
            }

            if value != lastValue {
                lastValue = value
                lastChangeTime = ContinuousClock.now
            }

            let idle = ContinuousClock.now - lastChangeTime
            if idle >= config.idleThreshold,
               let finalValue = lastValue, let initial = initialValue
            {
                return makeDraft(
                    initial: initial,
                    final: finalValue,
                    pastedText: pastedText,
                    transcriptID: transcriptID,
                    contextID: contextID
                )
            }

            try? await Task.sleep(for: config.pollInterval)
        }

        return nil
    }

    // MARK: - Private

    /// Extracts only the changed region between `initial` and `final` using
    /// common-prefix / common-suffix trimming. This prevents surrounding document
    /// content (text before or after the dictation) from leaking into the sample.
    private func makeDraft(
        initial: String,
        final finalValue: String,
        pastedText: String,
        transcriptID: String?,
        contextID: String
    ) -> VoicePersonalizationSampleDraft? {
        guard let (before, after) = Self.extractEditSpan(initial: initial, final: finalValue) else { return nil }
        guard !before.isEmpty || !after.isEmpty else { return nil }
        guard before != after else { return nil }
        guard before.utf8.count <= config.maxByteLength,
              after.utf8.count <= config.maxByteLength else { return nil }

        log.debug(
            "Learning sample: before=\(before.utf8.count, privacy: .public)B after=\(after.utf8.count, privacy: .public)B"
        )

        let finalText = Self.extractEditedPastedText(initial: initial, final: finalValue, pastedText: pastedText)

        return VoicePersonalizationSampleDraft(
            contextID: contextID,
            transcriptID: transcriptID,
            before: before,
            after: after,
            finalText: finalText,
            quality: finalText == nil ? .medium : .high,
            qualityReason: finalText == nil
                ? "edit_observed_without_final_text"
                : "post_edit_final_text_observed",
            diffOffset: 0,
            diffLength: before.count
        )
    }

    /// Returns the substring of `initial` and `final` that differs, by stripping
    /// the longest common prefix and longest common suffix. Both strings are compared
    /// character-by-character to find the exact changed region.
    static func extractEditSpan(initial: String, final finalValue: String) -> (before: String, after: String)? {
        let ic = Array(initial.unicodeScalars)
        let fc = Array(finalValue.unicodeScalars)

        var prefixLen = 0
        let minLen = min(ic.count, fc.count)
        while prefixLen < minLen && ic[prefixLen] == fc[prefixLen] {
            prefixLen += 1
        }

        var suffixLen = 0
        let maxSuffix = min(ic.count - prefixLen, fc.count - prefixLen)
        while suffixLen < maxSuffix
            && ic[ic.count - 1 - suffixLen] == fc[fc.count - 1 - suffixLen]
        {
            suffixLen += 1
        }

        let beforeStart = initial.unicodeScalars.index(
            initial.unicodeScalars.startIndex, offsetBy: prefixLen
        )
        let beforeEnd = suffixLen == 0
            ? initial.unicodeScalars.endIndex
            : initial.unicodeScalars.index(initial.unicodeScalars.endIndex, offsetBy: -suffixLen)
        let before = String(initial.unicodeScalars[beforeStart ..< beforeEnd])

        let afterStart = finalValue.unicodeScalars.index(
            finalValue.unicodeScalars.startIndex, offsetBy: prefixLen
        )
        let afterEnd = suffixLen == 0
            ? finalValue.unicodeScalars.endIndex
            : finalValue.unicodeScalars.index(finalValue.unicodeScalars.endIndex, offsetBy: -suffixLen)
        let after = String(finalValue.unicodeScalars[afterStart ..< afterEnd])

        return (before, after)
    }

    static func extractEditedPastedText(initial: String, final finalValue: String, pastedText: String) -> String? {
        guard !pastedText.isEmpty,
              let pastedRange = initial.range(of: pastedText)
        else {
            return nil
        }

        let initialScalars = Array(initial.unicodeScalars)
        let finalScalars = Array(finalValue.unicodeScalars)
        let pastedScalars = Array(pastedText.unicodeScalars)
        let pastedStart = initial.unicodeScalars.distance(
            from: initial.unicodeScalars.startIndex,
            to: pastedRange.lowerBound
        )
        let pastedEnd = initial.unicodeScalars.distance(
            from: initial.unicodeScalars.startIndex,
            to: pastedRange.upperBound
        )

        var prefixLen = 0
        let minLen = min(initialScalars.count, finalScalars.count)
        while prefixLen < minLen, initialScalars[prefixLen] == finalScalars[prefixLen] {
            prefixLen += 1
        }

        var suffixLen = 0
        let maxSuffix = min(initialScalars.count - prefixLen, finalScalars.count - prefixLen)
        while suffixLen < maxSuffix,
              initialScalars[initialScalars.count - 1 - suffixLen] == finalScalars[finalScalars.count - 1 - suffixLen]
        {
            suffixLen += 1
        }

        let changedStart = prefixLen
        let changedEnd = initialScalars.count - suffixLen
        guard changedStart >= pastedStart, changedEnd <= pastedEnd else { return nil }

        let replacementStart = prefixLen
        let replacementEnd = finalScalars.count - suffixLen
        let pastedReplacementStart = changedStart - pastedStart
        let pastedReplacementEnd = changedEnd - pastedStart

        var editedScalars: [Unicode.Scalar] = []
        editedScalars.append(contentsOf: pastedScalars[..<pastedReplacementStart])
        editedScalars.append(contentsOf: finalScalars[replacementStart ..< replacementEnd])
        editedScalars.append(contentsOf: pastedScalars[pastedReplacementEnd...])
        return String(String.UnicodeScalarView(editedScalars))
    }
}
