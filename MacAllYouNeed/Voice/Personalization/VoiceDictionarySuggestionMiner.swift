import Core
import Foundation
import OSLog

private let log = Logger(subsystem: "com.macallyouneed.voice", category: "dict-miner")

/// Mines post-edit personalization samples for recurring ASR misrecognitions and
/// records them as pending suggestions in VoiceDictionarySuggestionStore.
///
/// Single-flight: concurrent triggers are dropped while one run is in progress.
/// Gate: only runs when learnFromEditsEnabled is true.
actor VoiceDictionarySuggestionMiner {
    private let samplesStore: VoicePersonalizationStore
    private let suggestionStore: VoiceDictionarySuggestionStore
    private let dictionary: VoiceDictionaryStore
    private let transcripts: VoiceTranscriptStore
    private let settings: () -> VoicePersonalizationSettings
    private var inFlight = false

    init(
        samplesStore: VoicePersonalizationStore,
        suggestionStore: VoiceDictionarySuggestionStore,
        dictionary: VoiceDictionaryStore,
        transcripts: VoiceTranscriptStore,
        settings: @escaping () -> VoicePersonalizationSettings
    ) {
        self.samplesStore = samplesStore
        self.suggestionStore = suggestionStore
        self.dictionary = dictionary
        self.transcripts = transcripts
        self.settings = settings
    }

    func maybeRun(contextID: String) async {
        guard !inFlight else { return }
        guard settings().learnFromEditsEnabled else { return }
        inFlight = true
        defer { inFlight = false }
        do {
            try mine(contextID: contextID)
        } catch {
            log.error("dict miner failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Private

    private func mine(contextID: String) throws {
        let existing = try dictionary.list()
        let existingPhrases = Set(existing.map { $0.phrase.lowercased() })

        let samples = try samplesStore.listRecentSamples(contextID: contextID, limit: 50)

        for sample in samples {
            guard let transcriptID = sample.transcriptID else { continue }
            guard let transcript = try transcripts.fetch(id: transcriptID) else { continue }
            let cleanedText = transcript.cleanedText
            guard !cleanedText.isEmpty else { continue }
            guard !sample.before.isEmpty else { continue }

            // Find sample.before in cleanedText — skip if not found or ambiguous
            guard let foundRange = cleanedText.range(of: sample.before),
                  cleanedText.range(of: sample.before, range: cleanedText.index(after: foundRange.lowerBound)..<cleanedText.endIndex) == nil
            else { continue }

            let wrongToken = expandToTokenBoundary(in: cleanedText, range: foundRange)
            let correctToken = sample.after.trimmingCharacters(in: .whitespacesAndNewlines)

            // Multi-token guards
            guard !wrongToken.contains(" "), !wrongToken.contains("\t") else { continue }
            guard !correctToken.isEmpty else { continue }
            guard !correctToken.contains(" "), !correctToken.contains("\t") else { continue }

            // Safety filters
            guard wrongToken != correctToken else { continue }
            guard wrongToken.lowercased() != correctToken.lowercased() else { continue }

            // Skip punctuation-only diff
            let wrongAlnum = wrongToken.unicodeScalars.filter { isAlphanumericScalar($0) }
            let correctAlnum = correctToken.unicodeScalars.filter { isAlphanumericScalar($0) }
            guard String(String.UnicodeScalarView(wrongAlnum)) != String(String.UnicodeScalarView(correctAlnum)) else { continue }

            // Already in dictionary
            guard !existingPhrases.contains(wrongToken.lowercased()) else { continue }

            // Length limits
            let hasCJK = wrongToken.unicodeScalars.contains(where: isCJKScalar)
            if hasCJK {
                guard wrongToken.unicodeScalars.filter(isCJKScalar).count >= 2 else { continue }
            } else {
                guard wrongToken.count >= 3 else { continue }
            }
            guard wrongToken.count <= 40, correctToken.count <= 40 else { continue }

            // Stop words
            guard !stopWords.contains(wrongToken.lowercased()) else { continue }

            // Purely numeric
            guard !wrongToken.allSatisfy({ $0.isNumber }) else { continue }

            // Skip if a non-pending suggestion already exists for this phrase
            let normKey = VoiceDictionarySuggestionStore.makeNormKey(phrase: wrongToken)
            guard !(try suggestionStore.existsNonPending(normKey: normKey)) else { continue }

            try suggestionStore.recordCandidate(phrase: wrongToken, replacement: correctToken, sampleID: sample.id, now: Date())
            log.debug("dict miner: candidate '\(wrongToken, privacy: .private)' -> '\(correctToken, privacy: .private)'")
        }
    }

    // MARK: - Token boundary expansion

    private func expandToTokenBoundary(in text: String, range: Range<String.Index>) -> String {
        var lower = range.lowerBound
        var upper = range.upperBound

        // Extend left
        while lower > text.startIndex {
            let prev = text.index(before: lower)
            let scalar = text.unicodeScalars[prev]
            if isTokenContinuation(scalar) {
                lower = prev
            } else {
                break
            }
        }

        // Extend right
        while upper < text.endIndex {
            let scalar = text.unicodeScalars[upper]
            if isTokenContinuation(scalar) {
                upper = text.index(after: upper)
            } else {
                break
            }
        }

        return String(text[lower..<upper])
    }

    private func isTokenContinuation(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x30...0x39, // 0-9
             0x41...0x5A, // A-Z
             0x61...0x7A, // a-z
             0x5F:        // _
            return true
        default:
            return isCJKScalar(s)
        }
    }

    private func isCJKScalar(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x4E00...0x9FFF,
             0x3400...0x4DBF,
             0xF900...0xFAFF,
             0x20000...0x2A6DF,
             0x2A700...0x2B73F:
            return true
        default:
            return false
        }
    }

    private func isAlphanumericScalar(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A:
            return true
        default:
            return false
        }
    }

    // MARK: - Stop words

    private let stopWords: Set<String> = [
        "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
        "have", "has", "had", "do", "does", "did", "will", "would", "could",
        "should", "may", "might", "shall", "can", "of", "in", "on", "at",
        "to", "for", "with", "by", "from", "up", "about", "into", "through",
        "this", "that", "these", "those", "and", "or", "but", "if", "as",
        "not", "so"
    ]
}
