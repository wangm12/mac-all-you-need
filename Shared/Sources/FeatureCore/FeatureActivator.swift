import Foundation

public protocol FeatureActivator: Sendable {
    func activate() async throws
    func deactivate() async throws
}

/// A no-op activator used in tests and as a default for skeleton features.
public struct NoopFeatureActivator: FeatureActivator {
    public init() {}
    public func activate() async throws {}
    public func deactivate() async throws {}
}
