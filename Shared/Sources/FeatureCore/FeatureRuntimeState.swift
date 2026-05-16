import Foundation

public struct FeatureRuntimeState: Equatable, Sendable, Codable {
    public let assetState: AssetState
    public let activationState: ActivationState

    public init(assetState: AssetState, activationState: ActivationState) {
        self.assetState = assetState
        self.activationState = activationState
    }

    public static func initialDefault(assetRequired: Bool) -> FeatureRuntimeState {
        .init(
            assetState: assetRequired ? .notDownloaded : .notRequired,
            activationState: .disabled
        )
    }

    public var canActivate: Bool {
        switch assetState {
        case .notRequired, .present: return true
        case .notDownloaded, .downloading, .downloadFailed: return false
        }
    }
}
