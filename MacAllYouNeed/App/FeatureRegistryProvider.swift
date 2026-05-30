import FeatureCore
import SwiftUI

enum FeatureRegistryProvider {
    static func makeRegistry() -> FeatureRegistry {
        FeatureRegistry(descriptors: [
            ClipboardDescriptor.descriptor(),
            ClipboardSmartTextDescriptor.descriptor(),
            FolderPreviewDescriptor.descriptor(),
            DownloaderDescriptor.descriptor(),
            VoiceDescriptor.descriptor(),
            WindowLayoutsDescriptor.descriptor(),
            WindowGrabDescriptor.descriptor(),
        ])
    }
}
