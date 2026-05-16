import FeatureCore
import SwiftUI

enum FeatureRegistryProvider {
    static func makeRegistry() -> FeatureRegistry {
        FeatureRegistry(descriptors: [
            ClipboardDescriptor.descriptor(),
            FolderPreviewDescriptor.descriptor(),
            DownloaderDescriptor.descriptor(),
            VoiceDescriptor.descriptor(),
        ])
    }
}
