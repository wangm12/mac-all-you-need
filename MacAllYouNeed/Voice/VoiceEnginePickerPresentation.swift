import Foundation

enum VoiceEnginePickerFilter: String, CaseIterable, SegmentedTabDestination {
    case all
    case local
    case cloud

    var title: String {
        switch self {
        case .all:
            "All"
        case .local:
            "Local"
        case .cloud:
            "Cloud"
        }
    }

    var symbolName: String {
        switch self {
        case .all:
            "line.3.horizontal.decrease.circle"
        case .local:
            "internaldrive"
        case .cloud:
            "cloud"
        }
    }
}

enum VoiceEngineGroup: String {
    case local
    case cloud
    case experimental

    var title: String {
        switch self {
        case .local:
            "Local"
        case .cloud:
            "Cloud"
        case .experimental:
            "Experimental"
        }
    }
}

enum VoiceEngineID: Hashable, Identifiable {
    case local(VoiceASRModelID)
    case cloud(VoiceCloudASRModelID)
    case experimental(String)

    var id: String {
        switch self {
        case let .local(modelID):
            "local.\(modelID.rawValue)"
        case let .cloud(modelID):
            "cloud.\(modelID.rawValue)"
        case let .experimental(descriptorID):
            "experimental.\(descriptorID)"
        }
    }

    var group: VoiceEngineGroup {
        switch self {
        case .local:
            .local
        case .cloud:
            .cloud
        case .experimental:
            .experimental
        }
    }

    var pickerIcon: VoicePickerRowIcon {
        switch self {
        case .local:
            VoiceProviderIconPresentation.pickerIcon(for: VoiceModelRuntime.qwenCoreML)
        case let .cloud(modelID):
            VoiceProviderIconPresentation.pickerIcon(for: modelID.providerKind)
        case .experimental:
            VoiceProviderIconPresentation.pickerIcon(for: VoiceModelRuntime.mlxExperimental)
        }
    }
}

struct VoiceEngineListEntry: Identifiable, Hashable {
    let id: VoiceEngineID
    let title: String
    let subtitle: String
    let group: VoiceEngineGroup

    var searchableText: String {
        "\(title) \(subtitle)"
    }
}

enum VoiceEngineCatalogPresentation {
    static func twoPaneEntries(from entries: [VoiceEngineListEntry]) -> [VoiceTwoPanePickerEntry<VoiceEngineID, VoiceEngineGroup>] {
        entries.map { entry in
            VoiceTwoPanePickerEntry(
                id: entry.id,
                title: entry.title,
                subtitle: entry.subtitle,
                icon: entry.id.pickerIcon,
                group: entry.group
            )
        }
    }

    static func matchesFilter(
        _ entry: VoiceTwoPanePickerEntry<VoiceEngineID, VoiceEngineGroup>,
        filter: VoiceEnginePickerFilter
    ) -> Bool {
        matchesFilter(
            VoiceEngineListEntry(id: entry.id, title: entry.title, subtitle: entry.subtitle, group: entry.group),
            filter: filter
        )
    }

    static func currentEngineID(
        providerKind: VoiceASRProviderKind,
        selectedLocalModelID: VoiceASRModelID,
        selectedCloudModelID: VoiceCloudASRModelID
    ) -> VoiceEngineID {
        switch providerKind {
        case .local:
            .local(selectedLocalModelID)
        case .groq, .elevenLabs, .openAITranscribe, .openAIRealtime, .deepgram:
            .cloud(selectedCloudModelID)
        }
    }

    static func pickerEntries() -> [VoiceEngineListEntry] {
        let local = VoiceModelCatalog.localASRModels.map { descriptor -> VoiceEngineListEntry in
            if let modelID = descriptor.localASRModelID {
                return VoiceEngineListEntry(
                    id: .local(modelID),
                    title: descriptor.title,
                    subtitle: descriptor.subtitle,
                    group: .local
                )
            }
            return VoiceEngineListEntry(
                id: .experimental(descriptor.id),
                title: descriptor.title,
                subtitle: descriptor.subtitle,
                group: .experimental
            )
        }

        let cloud = VoiceModelCatalog.cloudASRModels.compactMap { descriptor -> VoiceEngineListEntry? in
            guard let modelID = descriptor.cloudASRModelID else {
                return nil
            }
            return VoiceEngineListEntry(
                id: .cloud(modelID),
                title: descriptor.title,
                subtitle: descriptor.subtitle,
                group: .cloud
            )
        }

        return local + cloud
    }

    static func matchesFilter(_ entry: VoiceEngineListEntry, filter: VoiceEnginePickerFilter) -> Bool {
        switch filter {
        case .all:
            true
        case .local:
            entry.group == .local || entry.group == .experimental
        case .cloud:
            entry.group == .cloud
        }
    }

    static func experimentalDescriptor(for id: String) -> VoiceModelDescriptor? {
        VoiceModelCatalog.localASRModels.first { descriptor in
            descriptor.localASRModelID == nil && descriptor.id == id
        }
    }
}
