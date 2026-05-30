import Foundation
import SwiftUI

public enum Permission: String, Sendable, Codable, Hashable {
    case accessibility
    case fullDiskAccess
    case microphone
    case notifications
    case screenRecording
    case reminders
}

public struct HotkeyDescriptor: Sendable, Equatable {
    public let identifier: String
    public let displayName: String
    public init(identifier: String, displayName: String) {
        self.identifier = identifier
        self.displayName = displayName
    }
}

public enum OSExtensionPolicy: Sendable {
    case none
    case staticBundleExtension(StaticExtensionConfig)
}

public struct StaticExtensionConfig: Sendable {
    public let extensionBundleID: String
    public let runsRegardlessOfFeatureState: Bool
    public let respectsFeatureFlag: Bool
    public init(
        extensionBundleID: String,
        runsRegardlessOfFeatureState: Bool,
        respectsFeatureFlag: Bool
    ) {
        self.extensionBundleID = extensionBundleID
        self.runsRegardlessOfFeatureState = runsRegardlessOfFeatureState
        self.respectsFeatureFlag = respectsFeatureFlag
    }
}

public struct FeatureDescriptor: Sendable {
    public let id: FeatureID
    public let displayName: String
    public let icon: String
    public let summary: String
    public let detailDescription: String
    public let requiredPermissions: [Permission]
    public let assetPacks: [AssetPack]
    public let assetCaches: [AssetCacheDescriptor]
    public let hotkeys: [HotkeyDescriptor]
    public let osExtensionPolicy: OSExtensionPolicy
    public let activator: any FeatureActivator
    public let settingsTabFactory: (@Sendable () -> AnyView)?
    public let onboardingSetupFactory: (@Sendable () -> AnyView)?
    public let menuBarItemFactory: (@Sendable () -> AnyView)?

    public init(
        id: FeatureID,
        displayName: String,
        icon: String,
        summary: String,
        detailDescription: String,
        requiredPermissions: [Permission] = [],
        assetPacks: [AssetPack] = [],
        assetCaches: [AssetCacheDescriptor] = [],
        hotkeys: [HotkeyDescriptor] = [],
        osExtensionPolicy: OSExtensionPolicy = .none,
        activator: any FeatureActivator,
        settingsTabFactory: (@Sendable () -> AnyView)? = nil,
        onboardingSetupFactory: (@Sendable () -> AnyView)? = nil,
        menuBarItemFactory: (@Sendable () -> AnyView)? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.icon = icon
        self.summary = summary
        self.detailDescription = detailDescription
        self.requiredPermissions = requiredPermissions
        self.assetPacks = assetPacks
        self.assetCaches = assetCaches
        self.hotkeys = hotkeys
        self.osExtensionPolicy = osExtensionPolicy
        self.activator = activator
        self.settingsTabFactory = settingsTabFactory
        self.onboardingSetupFactory = onboardingSetupFactory
        self.menuBarItemFactory = menuBarItemFactory
    }

    public var requiresAsset: Bool { !assetPacks.isEmpty }
}
