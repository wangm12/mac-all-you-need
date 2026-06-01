import CoreGraphics
import Foundation

/// Persisted RGBA for the radial target-window glow border.
public struct RadialHighlightColor: Codable, Equatable, Sendable {
    public var red: CGFloat
    public var green: CGFloat
    public var blue: CGFloat
    public var alpha: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Default accent aligned with the app focus ring (~system accent blue).
    public static let focusRingDefault = RadialHighlightColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)

    public static let presetBlue = RadialHighlightColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
    public static let presetGreen = RadialHighlightColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1.0)
    public static let presetOrange = RadialHighlightColor(red: 1.0, green: 0.58, blue: 0.0, alpha: 1.0)
}
