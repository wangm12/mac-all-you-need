import FeatureCore
import Foundation

/// Display order for first-launch feature picker tiles.
/// Sub-features (e.g. Clipboard Smart Text) are excluded — they appear inside a parent card.
enum OnboardingFeaturePickerOrdering {
    static let featureIDs: [FeatureID] = [
        .clipboard,
        .voice,
        .voiceReminders,
        .downloader,
        .folderPreview,
        .folderHistory,
        .aiFileOrganizer,
        .windowLayouts,
        .windowGrab,
        .windowHub,
    ]

    static func descriptors(in registry: FeatureRegistry) -> [FeatureDescriptor] {
        let byID = Dictionary(uniqueKeysWithValues: registry.descriptors.map { ($0.id, $0) })
        return featureIDs.compactMap { byID[$0] }
    }
}
