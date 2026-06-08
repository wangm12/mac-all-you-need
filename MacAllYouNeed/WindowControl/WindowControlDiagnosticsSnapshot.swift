import Foundation

/// Main-actor snapshot passed to `WindowControlFeatureWorker` for off-main formatting.
struct WindowControlDiagnosticsSnapshot: Sendable {
    var eventTapDetail: String
    var eventTapStatus: String
    var lastAction: String
    var lastResultDetail: String
    var frontmostBundleID: String?
    var accessibilityTrusted: Bool
}
