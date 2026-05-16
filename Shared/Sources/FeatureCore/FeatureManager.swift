import Foundation

public actor FeatureManager {
    public let registry: FeatureRegistry
    private let defaults: UserDefaults
    private let darwinNotificationName: String

    public init(
        registry: FeatureRegistry,
        defaults: UserDefaults,
        darwinNotificationName: String = DarwinNotification.featureStateDidChange
    ) {
        self.registry = registry
        self.defaults = defaults
        self.darwinNotificationName = darwinNotificationName
    }

    public func state(for id: FeatureID) -> FeatureRuntimeState {
        if let data = defaults.data(forKey: Self.persistKey(for: id)),
           let decoded = try? JSONDecoder().decode(FeatureRuntimeState.self, from: data) {
            return decoded
        }
        let descriptor = registry.descriptor(for: id)
        return .initialDefault(assetRequired: descriptor?.requiresAsset ?? false)
    }

    public func allStates() -> [FeatureID: FeatureRuntimeState] {
        Dictionary(uniqueKeysWithValues: registry.descriptors.map { ($0.id, state(for: $0.id)) })
    }

    /// Used by Tasks 11+ and tests. Persists and posts the Darwin notification.
    public func setState(_ state: FeatureRuntimeState, for id: FeatureID) throws {
        let data = try JSONEncoder().encode(state)
        defaults.set(data, forKey: Self.persistKey(for: id))
        DarwinNotification.post(darwinNotificationName)
    }

    public static func persistKey(for id: FeatureID) -> String {
        "feature.\(id.rawValue).runtimeState"
    }
}

extension FeatureManager {
    public enum Transition {
        case enable
        case disable
    }

    public enum TransitionError: Error, Equatable {
        case assetNotReady
        case unknownFeature(FeatureID)
    }

    public func transition(_ transition: Transition, for id: FeatureID) throws {
        guard registry.descriptor(for: id) != nil else { throw TransitionError.unknownFeature(id) }
        let current = state(for: id)
        switch transition {
        case .enable:
            guard current.canActivate else { throw TransitionError.assetNotReady }
            if current.activationState == .enabled { return }
            try setState(.init(assetState: current.assetState, activationState: .enabled), for: id)
        case .disable:
            if current.activationState == .disabled { return }
            try setState(.init(assetState: current.assetState, activationState: .disabled), for: id)
        }
    }

    /// Used by the install pipeline (Phase 02) and tests. Forces disable when asset is removed.
    public func markAssetState(_ newAssetState: AssetState, for id: FeatureID) throws {
        guard registry.descriptor(for: id) != nil else { throw TransitionError.unknownFeature(id) }
        let current = state(for: id)
        var newActivation = current.activationState
        switch newAssetState {
        case .notRequired, .present:
            break
        case .notDownloaded, .downloading, .downloadFailed:
            newActivation = .disabled
        }
        try setState(.init(assetState: newAssetState, activationState: newActivation), for: id)
    }
}
