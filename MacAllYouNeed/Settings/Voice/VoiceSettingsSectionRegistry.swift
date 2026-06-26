/// Registry that pins the ordered section type names and user-visible headers
/// for the Voice Settings page. Tests import this to pin the decomposition contract.
enum VoiceSettingsSectionRegistry {

    enum Section: Hashable {
        case apiKey
        case dictionary
        case personalization
        case trainingExamples
    }

    static let orderedTypeNames: [String] = [
        "VoiceAPIKeySection",
        "VoiceDictionarySection",
        "VoicePersonalizationSection",
        "VoiceTrainingExamplesSection",
    ]

    static let headers: [Section: String] = [
        .apiKey: "API Key Setup",
        .dictionary: "Dictionary",
        .personalization: "Personalization",
        .trainingExamples: "Training Examples",
    ]
}
