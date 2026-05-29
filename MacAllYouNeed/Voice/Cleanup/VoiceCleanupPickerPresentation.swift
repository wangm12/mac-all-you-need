import Foundation

enum VoiceCleanupPickerFilter: String, CaseIterable, SegmentedTabDestination {
    case all
    case cloud
    case local
    case custom

    var title: String {
        switch self {
        case .all: "All"
        case .cloud: "Cloud"
        case .local: "Local"
        case .custom: "Custom"
        }
    }

    var symbolName: String {
        switch self {
        case .all: "line.3.horizontal.decrease.circle"
        case .cloud: "cloud"
        case .local: "internaldrive"
        case .custom: "link"
        }
    }
}

enum VoiceCleanupProviderGroup: String, Hashable {
    case cloud
    case local
    case custom

    var title: String {
        switch self {
        case .cloud: "Cloud"
        case .local: "Local"
        case .custom: "Custom"
        }
    }
}

extension VoiceCleanupProviderKind {
    var cleanupPickerGroup: VoiceCleanupProviderGroup {
        switch self {
        case .anthropic, .openAICompatible, .groq, .gemini:
            .cloud
        case .ollama, .omlx:
            .local
        }
    }

    var cleanupPickerIcon: VoicePickerRowIcon {
        VoiceProviderIconPresentation.pickerIcon(for: self)
    }
}

enum VoiceCleanupCatalogPresentation {
    /// Sidebar section order; omits Custom when no provider uses that group.
    static func pickerGroupOrder() -> [VoiceCleanupProviderGroup] {
        var order: [VoiceCleanupProviderGroup] = [.cloud, .local]
        if VoiceCleanupProviderKind.allCases.contains(where: { $0.cleanupPickerGroup == .custom }) {
            order.append(.custom)
        }
        return order
    }

    /// Segmented filters for the picker; hides Custom when that group is empty.
    static func pickerFilters() -> [VoiceCleanupPickerFilter] {
        if VoiceCleanupProviderKind.allCases.contains(where: { $0.cleanupPickerGroup == .custom }) {
            return Array(VoiceCleanupPickerFilter.allCases)
        }
        return VoiceCleanupPickerFilter.allCases.filter { $0 != .custom }
    }

    static func rowTitle(for kind: VoiceCleanupProviderKind) -> String {
        kind.label
    }

    static func rowSubtitle(for kind: VoiceCleanupProviderKind) -> String {
        switch kind {
        case .anthropic:
            "Anthropic Messages API"
        case .openAICompatible:
            "OpenAI API · set base URL and model"
        case .groq:
            "Groq OpenAI-compatible chat"
        case .gemini:
            "Google AI Studio API key"
        case .ollama:
            "Local models via Ollama"
        case .omlx:
            "Local MLX server · confirm port"
        }
    }

    static func pickerEntries() -> [VoiceTwoPanePickerEntry<VoiceCleanupProviderKind, VoiceCleanupProviderGroup>] {
        VoiceCleanupProviderKind.allCases.map { kind in
            VoiceTwoPanePickerEntry(
                id: kind,
                title: rowTitle(for: kind),
                subtitle: rowSubtitle(for: kind),
                icon: kind.cleanupPickerIcon,
                group: kind.cleanupPickerGroup
            )
        }
    }

    static func matchesFilter(
        _ entry: VoiceTwoPanePickerEntry<VoiceCleanupProviderKind, VoiceCleanupProviderGroup>,
        filter: VoiceCleanupPickerFilter
    ) -> Bool {
        switch filter {
        case .all:
            true
        case .cloud:
            entry.group == .cloud
        case .local:
            entry.group == .local
        case .custom:
            entry.group == .custom
        }
    }

    static func currentProvider(from settings: VoiceCleanupSettings) -> VoiceCleanupProviderKind {
        settings.provider
    }
}
