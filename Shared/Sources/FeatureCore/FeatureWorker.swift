import Foundation

/// Background isolation boundary for a modular feature. One instance per `FeatureID`
/// (or shared across related IDs, e.g. clipboard + clipboardSmartText).
///
/// Implementations should be `actor`s or use a private serial queue. UI and AppKit
/// stay on `@MainActor`; workers return `Sendable` value types only.
public protocol FeatureWorker: Sendable {
    func start() async
    func stop() async
}

/// No background work; satisfies registry symmetry for features that are UI-only or
/// delegate to existing actors elsewhere.
public struct NoopFeatureWorker: FeatureWorker {
    public init() {}

    public func start() async {}
    public func stop() async {}
}
