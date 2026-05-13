import Core
import Foundation

struct VoicePromptContext: Equatable {
    let language: VoiceLanguage
    let appBundleID: String?
    let dictionaryEntries: [VoiceDictionaryEntry]
    let translationTarget: VoiceLanguage?
    let appInstructions: String?

    init(
        language: VoiceLanguage,
        appBundleID: String?,
        dictionaryEntries: [VoiceDictionaryEntry],
        translationTarget: VoiceLanguage?,
        appInstructions: String? = nil
    ) {
        self.language = language
        self.appBundleID = appBundleID
        self.dictionaryEntries = dictionaryEntries
        self.translationTarget = translationTarget
        self.appInstructions = appInstructions
    }
}

enum VoicePromptBuilder {
    static func systemPrompt(context: VoicePromptContext) -> String {
        var lines = [
            "You clean up dictated text before it is pasted into a macOS app.",
            "Source language: \(label(for: context.language)).",
            "Preserve the user's meaning, code-switching, product names, code terms, and commands.",
            "Remove filler words, duplicated starts, ASR artifacts, and hallucinated markup.",
            "Return only the final cleaned text. Do not explain your edits."
        ]

        if let appBundleID = context.appBundleID {
            lines.append("Target app bundle identifier: \(appBundleID).")
        }

        if let appInstructions = context.appInstructions?.trimmingCharacters(in: .whitespacesAndNewlines),
           !appInstructions.isEmpty
        {
            lines.append("App-specific instructions:")
            lines.append(appInstructions)
        }

        if let translationTarget = context.translationTarget {
            lines
                .append(
                    "If the source language differs from \(label(for: translationTarget)), " +
                        "translate the cleaned text to \(label(for: translationTarget))."
                )
        }

        let replacements = context.dictionaryEntries
            .filter { !$0.phrase.isEmpty }
            .map { "\($0.phrase) -> \($0.replacement)" }
        if !replacements.isEmpty {
            lines.append("User dictionary replacements:")
            lines.append(contentsOf: replacements)
        }

        return lines.joined(separator: "\n")
    }

    static func userPrompt(transcript: String) -> String {
        "<TRANSCRIPT>\(transcript)</TRANSCRIPT>"
    }

    private static func label(for language: VoiceLanguage) -> String {
        switch language {
        case .english: "English"
        case .chinese: "Chinese"
        case .mixed: "zh+en mixed"
        case .unknown: "unknown"
        }
    }
}
