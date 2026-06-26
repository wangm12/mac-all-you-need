import Core
import SwiftUI

/// Dark-material palette for the Radial Puck HUD (aligned with `design/window_radial.html` / Loop).
enum RadialPuckVisualTokens {
    private static let previewFill = Color.primary

    static func guideRingOpacity(selectionActive: CGFloat) -> CGFloat {
        0.055 + selectionActive * 0.045
    }

    static func chevronOpacity(fullScreenBlend: CGFloat, isTeaching: Bool) -> CGFloat {
        let base = isTeaching ? 0.22 : 0.14
        return base + fullScreenBlend * 0.55
    }

    static func chevronStrokeOpacity(fullScreenBlend: CGFloat) -> CGFloat {
        fullScreenBlend > 0.3 ? 0.92 : 0.42
    }

    static func rayTipOpacity(fullScreenBlend: CGFloat) -> CGFloat {
        fullScreenBlend > 0.4 ? 0.42 : 0.24
    }

    static func previewFillOpacity(fullScreenBlend: CGFloat) -> CGFloat {
        0.28 + 0.10 * fullScreenBlend
    }

    static func previewStrokeOpacity(fullScreenBlend: CGFloat) -> CGFloat {
        0.88 + 0.30 * fullScreenBlend
    }

    static func previewStrokeWidth(fullScreenBlend: CGFloat) -> CGFloat {
        1.85 + 0.35 * fullScreenBlend
    }

    static func previewCornerRadius(fullScreenBlend: CGFloat) -> CGFloat {
        fullScreenBlend > 0.5 ? 15 : 13
    }

    static func previewShadowOpacity(previewOpacity: CGFloat) -> CGFloat {
        0.38 * previewOpacity
    }

    static var ambientPuckFill: Color {
        Color(red: 38 / 255, green: 38 / 255, blue: 40 / 255).opacity(0.70)
    }

    static var ambientPuckStroke: Color {
        Color.white.opacity(0.105)
    }

    static var ambientPuckShadow: Color {
        Color.black.opacity(0.36)
    }

    static func activePuckFill(fullScreenBlend: CGFloat) -> Color {
        if fullScreenBlend > 0.4 {
            return Color(red: 56 / 255, green: 56 / 255, blue: 58 / 255).opacity(0.86)
        }
        return Color(red: 46 / 255, green: 46 / 255, blue: 48 / 255).opacity(0.82)
    }

    static func activePuckStroke(fullScreenBlend: CGFloat) -> Color {
        fullScreenBlend > 0.4 ? Color.white.opacity(0.24) : Color.white.opacity(0.14)
    }

    static var centerDotFill: Color {
        Color.white.opacity(0.48)
    }

    static var centerSafeRingStroke: Color {
        Color.white.opacity(0.06)
    }

    static var labelPillFill: Color {
        Color(red: 31 / 255, green: 31 / 255, blue: 33 / 255).opacity(0.78)
    }

    static var labelPillStroke: Color {
        Color.white.opacity(0.10)
    }

    static var labelText: Color {
        Color.white.opacity(0.82)
    }

    static var hudInk: Color {
        .white
    }

    static var glyphStroke: Color {
        Color.white.opacity(0.86)
    }

    static var glyphFill: Color {
        Color.white.opacity(0.78)
    }

    static var focusPreviewFill: Color {
        previewFill
    }

    static var focusPreviewStroke: Color {
        previewFill
    }

    /// Settings / onboarding preview chrome.
    static var settingsPreviewBackgroundTop: Color {
        Color(red: 17 / 255, green: 17 / 255, blue: 19 / 255)
    }

    static var settingsPreviewBackgroundMid: Color {
        Color(red: 23 / 255, green: 23 / 255, blue: 25 / 255)
    }

    static var settingsPreviewBackgroundBottom: Color {
        Color(red: 16 / 255, green: 16 / 255, blue: 17 / 255)
    }

    static var settingsPreviewBorder: Color {
        Color.white.opacity(0.08)
    }
}
