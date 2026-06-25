import FeatureCore
import SwiftUI

enum FeatureOnboardingWizardRegistry {
    @MainActor
    static func augmented(_ descriptor: FeatureDescriptor, controller: AppController) -> FeatureDescriptor {
        if descriptor.featureOnboardingWizardFactory != nil { return descriptor }
        guard let factory = wizardFactory(for: descriptor.id, controller: controller) else {
            return descriptor
        }
        return copy(descriptor, featureOnboardingWizardFactory: factory)
    }

    @MainActor
    private static func wizardFactory(
        for id: FeatureID,
        controller: AppController
    ) -> (@Sendable @MainActor () -> AnyView)? {
        switch id {
        case .clipboard:
            return { AnyView(ClipboardOnboardingWizardView(controller: controller)) }
        case .downloader:
            return { AnyView(DownloaderOnboardingWizardView(controller: controller)) }
        case .windowLayouts:
            return { AnyView(WindowLayoutsOnboardingWizardView()) }
        case .windowGrab:
            return { AnyView(WindowGrabOnboardingWizardView()) }
        case .windowHub:
            return { AnyView(WindowHubOnboardingWizardView()) }
        case .folderPreview:
            return { AnyView(FolderPreviewOnboardingWizardView(controller: controller)) }
        case .folderHistory:
            return { AnyView(FolderHistoryOnboardingSetupView(controller: controller)) }
        case .aiFileOrganizer:
            return { AnyView(FileOrganizerOnboardingWizardView(controller: controller)) }
        case .voiceReminders:
            return { AnyView(VoiceRemindersOnboardingWizardView(controller: controller)) }
        case .voice, .clipboardSmartText:
            return nil
        }
    }

    private static func copy(
        _ descriptor: FeatureDescriptor,
        featureOnboardingWizardFactory: (@Sendable @MainActor () -> AnyView)?
    ) -> FeatureDescriptor {
        FeatureDescriptor(
            id: descriptor.id,
            displayName: descriptor.displayName,
            icon: descriptor.icon,
            summary: descriptor.summary,
            detailDescription: descriptor.detailDescription,
            requiredPermissions: descriptor.requiredPermissions,
            assetPacks: descriptor.assetPacks,
            assetCaches: descriptor.assetCaches,
            hotkeys: descriptor.hotkeys,
            osExtensionPolicy: descriptor.osExtensionPolicy,
            activator: descriptor.activator,
            settingsTabFactory: descriptor.settingsTabFactory,
            onboardingSetupFactory: descriptor.onboardingSetupFactory,
            featureOnboardingWizardFactory: featureOnboardingWizardFactory,
            menuBarItemFactory: descriptor.menuBarItemFactory
        )
    }
}
