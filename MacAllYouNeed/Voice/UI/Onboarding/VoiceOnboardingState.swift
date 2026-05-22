import Core
import Foundation

enum VoiceOnboardingStep: String, CaseIterable, Codable, Equatable, Identifiable {
    case welcome
    case microphone
    case accessibility
    case asr
    case llm
    case hotkey
    case languages
    case tryIt
    case done

    static let orderedCases: [VoiceOnboardingStep] = [
        .welcome,
        .microphone,
        .accessibility,
        .asr,
        .llm,
        .hotkey,
        .languages,
        .tryIt,
        .done
    ]

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .welcome:
            "Welcome"
        case .microphone:
            "Microphone"
        case .accessibility:
            "Accessibility"
        case .asr:
            "Recognition engine"
        case .llm:
            "AI cleanup"
        case .hotkey:
            "Shortcut"
        case .languages:
            "Languages"
        case .tryIt:
            "Try it"
        case .done:
            "Done"
        }
    }

    var canSkip: Bool {
        switch self {
        case .welcome, .done:
            false
        case .microphone, .accessibility, .asr, .llm, .hotkey, .languages, .tryIt:
            true
        }
    }

    var next: VoiceOnboardingStep? {
        guard let index = Self.orderedCases.firstIndex(of: self),
              index + 1 < Self.orderedCases.count
        else {
            return nil
        }
        return Self.orderedCases[index + 1]
    }

    var previous: VoiceOnboardingStep? {
        guard let index = Self.orderedCases.firstIndex(of: self),
              index > 0
        else {
            return nil
        }
        return Self.orderedCases[index - 1]
    }
}

struct VoiceOnboardingProgress: Codable, Equatable {
    var currentStep: VoiceOnboardingStep
    var isCompleted: Bool

    static let `default` = VoiceOnboardingProgress(currentStep: .welcome, isCompleted: false)
}

enum VoiceOnboardingLanguage: String, CaseIterable, Codable, Equatable, Identifiable {
    case simplifiedChinese
    case english
    case traditionalChinese
    case cantonese
    case japanese
    case korean
    case more

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .simplifiedChinese:
            "简体中文"
        case .english:
            "English"
        case .traditionalChinese:
            "繁體中文"
        case .cantonese:
            "粤语"
        case .japanese:
            "日本語"
        case .korean:
            "한국어"
        case .more:
            "More languages"
        }
    }
}

struct VoiceOnboardingLanguageSelection: Codable, Equatable {
    var selectedLanguages: [VoiceOnboardingLanguage]
    var autoDetectEverything: Bool

    init(
        selectedLanguages: [VoiceOnboardingLanguage],
        autoDetectEverything: Bool = false
    ) {
        self.selectedLanguages = selectedLanguages
        self.autoDetectEverything = autoDetectEverything
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedLanguages = try container.decode([VoiceOnboardingLanguage].self, forKey: .selectedLanguages)
        autoDetectEverything = try container.decodeIfPresent(Bool.self, forKey: .autoDetectEverything) ?? false
    }

    static let `default` = VoiceOnboardingLanguageSelection(selectedLanguages: [
        .simplifiedChinese,
        .english
    ])

    var asrLanguageHint: VoiceASRLanguageHint {
        if autoDetectEverything { return .automatic }
        let unique = Set(selectedLanguages)
        guard unique.count == 1, let only = unique.first else { return .automatic }
        switch only {
        case .english:
            return .english
        case .simplifiedChinese, .traditionalChinese, .cantonese:
            return .chinese
        case .japanese, .korean, .more:
            return .automatic
        }
    }
}

enum VoiceOnboardingProgressStore {
    static let currentStepKey = "voiceOnboardingCurrentStep"
    static let completedKey = "voiceOnboardingCompleted"
    static let languageSelectionKey = "voice.onboarding.languageSelection.v1"

    static func load(from defaults: UserDefaults = AppGroupSettings.defaults) -> VoiceOnboardingProgress {
        let completed = defaults.bool(forKey: completedKey)
        guard !completed else {
            return VoiceOnboardingProgress(currentStep: .done, isCompleted: true)
        }
        let rawStep = defaults.string(forKey: currentStepKey)
        let step = rawStep.flatMap(VoiceOnboardingStep.init(rawValue:)) ?? .welcome
        return VoiceOnboardingProgress(currentStep: step, isCompleted: false)
    }

    static func saveStep(_ step: VoiceOnboardingStep, to defaults: UserDefaults = AppGroupSettings.defaults) {
        defaults.set(step.rawValue, forKey: currentStepKey)
        if step != .done {
            defaults.set(false, forKey: completedKey)
        }
    }

    static func markCompleted(to defaults: UserDefaults = AppGroupSettings.defaults) {
        defaults.set(VoiceOnboardingStep.done.rawValue, forKey: currentStepKey)
        defaults.set(true, forKey: completedKey)
    }

    static func reset(in defaults: UserDefaults = AppGroupSettings.defaults) {
        defaults.removeObject(forKey: currentStepKey)
        defaults.removeObject(forKey: completedKey)
        defaults.removeObject(forKey: languageSelectionKey)
    }

    static func loadLanguageSelection(
        from defaults: UserDefaults = AppGroupSettings.defaults
    ) -> VoiceOnboardingLanguageSelection {
        guard let data = defaults.data(forKey: languageSelectionKey),
              let decoded = try? JSONDecoder().decode(VoiceOnboardingLanguageSelection.self, from: data)
        else {
            return .default
        }
        return decoded
    }

    static func saveLanguageSelection(
        _ selection: VoiceOnboardingLanguageSelection,
        to defaults: UserDefaults = AppGroupSettings.defaults
    ) {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        defaults.set(data, forKey: languageSelectionKey)
    }
}
