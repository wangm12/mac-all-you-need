import Core
import FluidAudio
import Foundation

enum VoiceASRLanguageHint: String, CaseIterable, Codable, Equatable, Identifiable {
    case automatic
    case chinese
    case english

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .automatic:
            "Auto-detect"
        case .chinese:
            "Chinese"
        case .english:
            "English"
        }
    }

    var qwen3Language: Qwen3AsrConfig.Language? {
        switch self {
        case .automatic:
            nil
        case .chinese:
            .chinese
        case .english:
            .english
        }
    }
}

enum VoiceASRModelID: String, CaseIterable, Codable, Equatable, Identifiable {
    case qwen3ASR06BF32 = "qwen3-asr-0.6b-f32"
    case qwen3ASR06BInt8 = "qwen3-asr-0.6b-int8"

    var id: String { rawValue }

    init?(storedIdentifier: String?) {
        guard let storedIdentifier else { return nil }
        if let modelID = VoiceASRModelID(rawValue: storedIdentifier) {
            self = modelID
            return
        }
        switch storedIdentifier {
        case "qwen3-asr-0.6b":
            self = .qwen3ASR06BF32
        default:
            return nil
        }
    }

    var title: String {
        switch self {
        case .qwen3ASR06BF32:
            "Qwen3-ASR 0.6B f32"
        case .qwen3ASR06BInt8:
            "Qwen3-ASR 0.6B int8"
        }
    }

    var subtitle: String {
        switch self {
        case .qwen3ASR06BF32:
            "Default mixed Chinese/English model. Best current quality/latency balance in this app."
        case .qwen3ASR06BInt8:
            "Lower-memory Qwen3-ASR build. Good for keeping dictation resident while other tools run."
        }
    }

    var strengths: String {
        switch self {
        case .qwen3ASR06BF32:
            "Strong mixed Chinese/English recognition, fast on Apple Silicon, already benchmarked locally."
        case .qwen3ASR06BInt8:
            "Smaller resident memory footprint with the same Qwen3-ASR language coverage."
        }
    }

    var tradeoffs: String {
        switch self {
        case .qwen3ASR06BF32:
            "Largest current download and memory use; still only one model family."
        case .qwen3ASR06BInt8:
            "May trade some throughput for memory savings; needs the same macOS 15 CoreML path."
        }
    }

    var diskLabel: String {
        switch self {
        case .qwen3ASR06BF32:
            "~1.75 GB"
        case .qwen3ASR06BInt8:
            "~900 MB"
        }
    }

    var variant: Qwen3AsrVariant {
        switch self {
        case .qwen3ASR06BF32:
            .f32
        case .qwen3ASR06BInt8:
            .int8
        }
    }

    var requiresOSLabel: String {
        "macOS 15+"
    }
}

struct VoiceASRModelRowPresentation: Equatable {
    enum StatusKind: Equatable {
        case neutral
        case success
        case warning
        case progress
    }

    let statusText: String?
    let statusKind: StatusKind
    let actionTitle: String?

    static func model(isSelected: Bool, isDownloaded: Bool, isDownloading: Bool) -> VoiceASRModelRowPresentation {
        if isDownloading {
            return VoiceASRModelRowPresentation(
                statusText: "Downloading",
                statusKind: .progress,
                actionTitle: nil
            )
        }
        if isSelected {
            return VoiceASRModelRowPresentation(
                statusText: "Selected",
                statusKind: .success,
                actionTitle: nil
            )
        }
        if isDownloaded {
            return VoiceASRModelRowPresentation(
                statusText: nil,
                statusKind: .neutral,
                actionTitle: "Use"
            )
        }
        return VoiceASRModelRowPresentation(
            statusText: "Not installed",
            statusKind: .warning,
            actionTitle: "Download & Use"
        )
    }

    static func inheritedProfile(isSelected: Bool) -> VoiceASRModelRowPresentation {
        VoiceASRModelRowPresentation(
            statusText: isSelected ? "Selected" : "Inherit",
            statusKind: isSelected ? .success : .neutral,
            actionTitle: isSelected ? nil : "Use"
        )
    }
}

enum VoiceASRModelTitlePresentation {
    static func title(for modelID: VoiceASRModelID) -> String {
        modelID.title
    }

    static func sizeLabel(for modelID: VoiceASRModelID) -> String {
        modelID.diskLabel
    }
}

struct VoiceASRSettings: Codable, Equatable {
    var modelID: VoiceASRModelID
    var languageHint: VoiceASRLanguageHint

    static let `default` = VoiceASRSettings(modelID: .qwen3ASR06BF32, languageHint: .automatic)

    init(modelID: VoiceASRModelID = .qwen3ASR06BF32, languageHint: VoiceASRLanguageHint = .automatic) {
        self.modelID = modelID
        self.languageHint = languageHint
    }

    private enum CodingKeys: String, CodingKey {
        case modelID
        case languageHint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let storedModelID = try container.decodeIfPresent(String.self, forKey: .modelID)
        modelID = VoiceASRModelID(storedIdentifier: storedModelID) ?? VoiceASRSettings.default.modelID
        languageHint = try container.decodeIfPresent(VoiceASRLanguageHint.self, forKey: .languageHint) ?? VoiceASRSettings.default.languageHint
    }

    func resolvedModelID(preferredModelIdentifier: String?) -> VoiceASRModelID {
        guard let profileModelID = VoiceASRModelID(storedIdentifier: preferredModelIdentifier)
        else {
            return modelID
        }
        return profileModelID
    }
}

enum VoiceASRSettingsStore {
    static let key = "voice.asr.settings.v1"

    static func load(from defaults: UserDefaults = AppGroupSettings.defaults) -> VoiceASRSettings {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(VoiceASRSettings.self, from: data)
        else {
            return .default
        }
        return decoded
    }

    static func save(_ settings: VoiceASRSettings, to defaults: UserDefaults = AppGroupSettings.defaults) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
