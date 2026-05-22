/// Registry that pins the ordered section type names and user-visible headers
/// for the Voice Settings page. Tests import this to pin the decomposition contract.
enum VoiceSettingsSectionRegistry {

    enum Section: Hashable {
        case provider
        case apiKey
        case cleanup
        case dictionary
        case personalization
        case trainingExamples
    }

    static let orderedTypeNames: [String] = [
        "VoiceProviderSection",
        "VoiceAPIKeySection",
        "VoiceCleanupSection",
        "VoiceDictionarySection",
        "VoicePersonalizationSection",
        "VoiceTrainingExamplesSection",
    ]

    static let headers: [Section: String] = [
        .provider: "Recognition",
        .apiKey: "API Key Setup",
        .cleanup: "Cleanup",
        .dictionary: "Dictionary",
        .personalization: "Personalization",
        .trainingExamples: "Training Examples",
    ]
}
