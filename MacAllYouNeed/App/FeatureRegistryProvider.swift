import FeatureCore
import SwiftUI

enum FeatureRegistryProvider {
    static func makeRegistry() -> FeatureRegistry {
        FeatureRegistry(descriptors: [
            ClipboardDescriptor.descriptor(),
            ClipboardSmartTextDescriptor.descriptor(),
            VoiceDescriptor.descriptor(),
            RemindersFeatureDescriptor.descriptor(),
            DownloaderDescriptor.descriptor(),
            FolderPreviewDescriptor.descriptor(),
            FinderHistoryDescriptor.descriptor(),
            FileOrganizerDescriptor.descriptor(),
            WindowLayoutsDescriptor.descriptor(),
            WindowGrabDescriptor.descriptor(),
            WindowHubDescriptor.descriptor(),
        ])
    }
}
