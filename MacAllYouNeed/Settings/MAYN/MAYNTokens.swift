import AppKit
import QuartzCore
import SwiftUI

enum MAYNTheme {
    static let window = Color(nsColor: .windowBackgroundColor)
    static let panel = Color(nsColor: .controlBackgroundColor)
    static let panelSubtle = Color.primary.opacity(0.035)
    static let elevated = Color(nsColor: .textBackgroundColor)
    static let elevatedHover = Color.primary.opacity(0.045)
    static let elevatedPressed = Color.primary.opacity(0.075)
    static let divider = Color.secondary.opacity(0.16)
    static let selected = Color.primary.opacity(0.08)
    static let hover = Color.primary.opacity(0.05)
    static let muted = Color.secondary
    static let strongBorder = Color.primary.opacity(0.24)
    static let subtleBorder = Color.primary.opacity(0.10)
    static let hairline = Color.primary.opacity(0.08)
    static let focusRing = Color.primary.opacity(0.70)
    static let controlTint = Color.secondary
    /// Monochrome ON tint for custom switch style (replaces system green).
    static let switchTint = Color.primary
    static let tabSelectedFill = Color.primary
    static let tabSelectedForeground = Color(nsColor: .windowBackgroundColor)
    static let tabSelectedBorder = Color.primary.opacity(0.20)
    static let tabSelectedShadow = Color.black.opacity(0.06)
    /// Keyboard focus rows (sidebar, command palette) — not glass.
    static let activeFill = Color.primary
    static let activeText = Color(nsColor: .windowBackgroundColor)
    static let hudBackground = Color.primary
    static let hudForeground = Color(nsColor: .windowBackgroundColor)
    static let overlayScrim = Color.black.opacity(0.42)
    /// Command palette backdrop — dims in-window content only; never reveals desktop.
    static func commandPaletteBackdrop(_ scheme: ColorScheme) -> Color {
        Color.black.opacity(scheme == .dark ? 0.44 : 0.22)
    }

    static func commandPaletteGradient(_ scheme: ColorScheme) -> LinearGradient {
        if scheme == .dark {
            LinearGradient(
                colors: [
                    Color(red: 34 / 255, green: 34 / 255, blue: 34 / 255).opacity(0.78),
                    Color(red: 14 / 255, green: 14 / 255, blue: 14 / 255).opacity(0.72),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.82),
                    Color(red: 248 / 255, green: 248 / 255, blue: 246 / 255).opacity(0.74),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    static func commandPaletteBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.72)
    }

    static func commandPaletteInnerHighlightTop(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.9)
    }

    static func commandPaletteInnerShadowBottom(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.5) : Color.black.opacity(0.06)
    }

    static let commandPaletteDivider = Color.primary.opacity(0.07)
    static let commandPaletteRowHover = Color.primary.opacity(0.045)
    static let commandPaletteSectionTitle = Color.primary.opacity(0.36)

    // MARK: Material layers (L0–L1 opaque content — light + dark)

    /// Layer 0 — stable window background.
    static func contentWindow(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 11 / 255, green: 11 / 255, blue: 12 / 255)
            : Color(red: 251 / 255, green: 251 / 255, blue: 248 / 255)
    }

    /// Layer 1 — primary content panels (cards, settings sections).
    static func contentPanel(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 23 / 255, green: 23 / 255, blue: 24 / 255)
            : .white
    }

    /// Layer 1 elevated — cards, inset groups.
    static func contentPanelElevated(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 29 / 255, green: 29 / 255, blue: 31 / 255)
            : Color(red: 243 / 255, green: 243 / 255, blue: 241 / 255)
    }

    /// Layer 1 — dense list panels (clipboard history, downloads).
    static func contentListPanel(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 21 / 255, green: 21 / 255, blue: 22 / 255)
            : .white
    }

    // MARK: Typography contrast (explicit light + dark)

    static func textPrimary(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.92)
            : Color(red: 13 / 255, green: 13 / 255, blue: 13 / 255)
    }

    static func textSecondary(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.66)
            : Color(red: 77 / 255, green: 77 / 255, blue: 73 / 255)
    }

    static func textTertiary(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.42)
            : Color(red: 129 / 255, green: 129 / 255, blue: 123 / 255)
    }

    static func textDisabled(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.28)
            : Color(red: 185 / 255, green: 185 / 255, blue: 179 / 255)
    }

    // MARK: Keyboard selection inversion (sidebar, command palette, lists)

    static func selectionInversionGradient(_ scheme: ColorScheme) -> LinearGradient {
        if scheme == .dark {
            LinearGradient(
                colors: [
                    Color(red: 244 / 255, green: 244 / 255, blue: 244 / 255),
                    Color(red: 230 / 255, green: 230 / 255, blue: 230 / 255),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            LinearGradient(
                colors: [
                    Color(red: 9 / 255, green: 9 / 255, blue: 9 / 255),
                    Color(red: 23 / 255, green: 23 / 255, blue: 23 / 255),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    static func selectionInversionForeground(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 9 / 255, green: 9 / 255, blue: 9 / 255)
            : .white
    }

    static func selectionInversionSubtitle(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.black.opacity(0.58)
            : Color.white.opacity(0.72)
    }

    static func selectionInversionKeycapBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.black.opacity(0.085)
            : Color.white.opacity(0.12)
    }

    static func selectionInversionKeycapBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.black.opacity(0.12)
            : Color.white.opacity(0.18)
    }

    static func selectionInversionKeycapForeground(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.black.opacity(0.78)
            : Color.white.opacity(0.88)
    }

    /// Floating attention badge glass border (single layer).
    static func attentionPillBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.12)
    }

    // Semantic status tag palette — tinted capsule + saturated label (readable in light/dark).
    static let success = Color(red: 0.13, green: 0.58, blue: 0.30)
    static let warning = Color(red: 0.72, green: 0.52, blue: 0.04)
    static let danger = Color(red: 0.82, green: 0.17, blue: 0.15)
    static let progress = Color(red: 0.12, green: 0.44, blue: 0.92)
    static let statusMutedFill = Color.primary.opacity(0.08)
    static let statusMutedForeground = Color.secondary
    static let statusOutline = Color.primary.opacity(0.30)
}

enum MAYNStatusTagPalette {
    struct Colors {
        let background: Color
        let foreground: Color
        let border: Color
    }

    static func colors(for kind: StatusPill.Kind) -> Colors {
        switch tone(for: kind) {
        case .success:
            Colors(
                background: dynamicNSColor(
                    light: NSColor(calibratedRed: 0.84, green: 0.96, blue: 0.87, alpha: 1),
                    dark: NSColor(calibratedRed: 0.10, green: 0.34, blue: 0.18, alpha: 1)
                ),
                foreground: dynamicNSColor(
                    light: NSColor(calibratedRed: 0.10, green: 0.53, blue: 0.24, alpha: 1),
                    dark: NSColor(calibratedRed: 0.62, green: 0.92, blue: 0.68, alpha: 1)
                ),
                border: dynamicNSColor(
                    light: NSColor(calibratedRed: 0.40, green: 0.78, blue: 0.48, alpha: 1),
                    dark: NSColor(calibratedRed: 0.28, green: 0.62, blue: 0.36, alpha: 1)
                )
            )
        case .warning:
            Colors(
                background: dynamicNSColor(
                    light: NSColor(calibratedRed: 1.00, green: 0.95, blue: 0.76, alpha: 1),
                    dark: NSColor(calibratedRed: 0.36, green: 0.28, blue: 0.04, alpha: 1)
                ),
                foreground: dynamicNSColor(
                    light: NSColor(calibratedRed: 0.58, green: 0.42, blue: 0.02, alpha: 1),
                    dark: NSColor(calibratedRed: 0.98, green: 0.84, blue: 0.44, alpha: 1)
                ),
                border: dynamicNSColor(
                    light: NSColor(calibratedRed: 0.90, green: 0.72, blue: 0.18, alpha: 1),
                    dark: NSColor(calibratedRed: 0.72, green: 0.56, blue: 0.12, alpha: 1)
                )
            )
        case .danger:
            Colors(
                background: dynamicNSColor(
                    light: NSColor(calibratedRed: 1.00, green: 0.90, blue: 0.90, alpha: 1),
                    dark: NSColor(calibratedRed: 0.38, green: 0.10, blue: 0.10, alpha: 1)
                ),
                foreground: dynamicNSColor(
                    light: NSColor(calibratedRed: 0.78, green: 0.12, blue: 0.11, alpha: 1),
                    dark: NSColor(calibratedRed: 1.00, green: 0.62, blue: 0.60, alpha: 1)
                ),
                border: dynamicNSColor(
                    light: NSColor(calibratedRed: 0.94, green: 0.48, blue: 0.46, alpha: 1),
                    dark: NSColor(calibratedRed: 0.78, green: 0.24, blue: 0.22, alpha: 1)
                )
            )
        case .progress:
            Colors(
                background: dynamicNSColor(
                    light: NSColor(calibratedRed: 0.88, green: 0.94, blue: 1.00, alpha: 1),
                    dark: NSColor(calibratedRed: 0.08, green: 0.20, blue: 0.38, alpha: 1)
                ),
                foreground: dynamicNSColor(
                    light: NSColor(calibratedRed: 0.08, green: 0.40, blue: 0.88, alpha: 1),
                    dark: NSColor(calibratedRed: 0.62, green: 0.78, blue: 1.00, alpha: 1)
                ),
                border: dynamicNSColor(
                    light: NSColor(calibratedRed: 0.44, green: 0.66, blue: 0.98, alpha: 1),
                    dark: NSColor(calibratedRed: 0.24, green: 0.46, blue: 0.82, alpha: 1)
                )
            )
        case .neutral:
            Colors(
                background: MAYNTheme.statusMutedFill,
                foreground: MAYNTheme.statusMutedForeground,
                border: MAYNTheme.hairline
            )
        }
    }

    private static func tone(for kind: StatusPill.Kind) -> Tone {
        switch kind {
        case .success, .ready, .completed:
            .success
        case .warning, .paused, .needsPermission:
            .warning
        case .danger, .failed:
            .danger
        case .progress, .active, .processing:
            .progress
        case .neutral, .idle:
            .neutral
        }
    }

    private enum Tone {
        case success, warning, danger, progress, neutral
    }

    private static func dynamicNSColor(light: NSColor, dark: NSColor) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            }
        )
    }
}

enum MAYNTypography {
    static let displaySize: CGFloat = 32
    static let displayWeight: Font.Weight = .semibold
    static let pageTitleSize: CGFloat = 28
    static let pageTitleWeight: Font.Weight = .semibold
    static let sectionTitleSize: CGFloat = 15
    static let sectionTitleWeight: Font.Weight = .semibold
    static let cardTitleSize: CGFloat = 14
    static let cardTitleWeight: Font.Weight = .semibold
    static let bodySize: CGFloat = 13
    static let bodyWeight: Font.Weight = .regular
    static let bodyStrongWeight: Font.Weight = .medium
    static let captionSize: CGFloat = 12
    static let microSize: CGFloat = 11
    static let microWeight: Font.Weight = .medium
    static let keycapSize: CGFloat = 11
    static let keycapWeight: Font.Weight = .semibold
    static let sidebarGroupSize: CGFloat = 11
    static let sidebarGroupWeight: Font.Weight = .medium
    static let sidebarGroupTracking: CGFloat = 0.2

    static func display() -> Font { .system(size: displaySize, weight: displayWeight) }
    static func pageTitle() -> Font { .system(size: pageTitleSize, weight: pageTitleWeight) }
    static func sectionTitle() -> Font { .system(size: sectionTitleSize, weight: sectionTitleWeight) }
    static func cardTitle() -> Font { .system(size: cardTitleSize, weight: cardTitleWeight) }
    static func body(strong: Bool = false) -> Font {
        .system(size: bodySize, weight: strong ? bodyStrongWeight : bodyWeight)
    }
    static func caption() -> Font { .system(size: captionSize) }
    static func micro() -> Font { .system(size: microSize, weight: microWeight) }
    static func keycap() -> Font { .system(size: keycapSize, weight: keycapWeight) }
    static func sidebarGroup() -> Font {
        .system(size: sidebarGroupSize, weight: sidebarGroupWeight)
    }
}

enum MAYNSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 40
    static let pageHorizontal: CGFloat = 32
    static let sectionGap: CGFloat = 24
    static let cardGap: CGFloat = 12
}

enum MAYNMotionDuration {
    static let instant: TimeInterval = 0.08
    static let press: TimeInterval = 0.12
    static let hover: TimeInterval = 0.16
    static let control: TimeInterval = 0.18
    static let tab: TimeInterval = 0.23
    static let panel: TimeInterval = 0.28
    static let instruction: TimeInterval = 0.32
    static let toastIn: TimeInterval = 0.16
    static let toastOut: TimeInterval = 0.22
    static let paletteClose: TimeInterval = 0.12
    static let paletteMorph: TimeInterval = 0.18
    static let sidebarSelection: TimeInterval = 0.14
    static let badgePopoverDelay: TimeInterval = 0.18
    static let hudEnter: TimeInterval = 0.15
    static let hudExit: TimeInterval = 0.12
    static let paletteRowStagger: TimeInterval = 0.008
    static let paletteSelection: TimeInterval = 0.095
    static let paletteRowStaggerCap: TimeInterval = 0.08
    static let rowInsert: TimeInterval = 0.18
}

enum MAYNMotionScale {
    static let hudEnterStart: CGFloat = 0.94
    static let hudExitEnd: CGFloat = 0.985
    static let paletteEnterStart: CGFloat = 0.975
}

enum MAYNMotionKind {
    case instant
    case press
    case hover
    case control
    case tab
    case panel
    case instruction
    case toastIn
    case toastOut
    case paletteClose
    case paletteMorph
    case sidebarSelection
    case hudEnter
    case hudExit
    case paletteSelection
    case rowInsert

    var duration: TimeInterval {
        switch self {
        case .instant: MAYNMotionDuration.instant
        case .press: MAYNMotionDuration.press
        case .hover: MAYNMotionDuration.hover
        case .control: MAYNMotionDuration.control
        case .tab: MAYNMotionDuration.tab
        case .panel: MAYNMotionDuration.panel
        case .instruction: MAYNMotionDuration.instruction
        case .toastIn: MAYNMotionDuration.toastIn
        case .toastOut: MAYNMotionDuration.toastOut
        case .paletteClose: MAYNMotionDuration.paletteClose
        case .paletteMorph: MAYNMotionDuration.paletteMorph
        case .sidebarSelection: MAYNMotionDuration.sidebarSelection
        case .hudEnter: MAYNMotionDuration.hudEnter
        case .hudExit: MAYNMotionDuration.hudExit
        case .paletteSelection: MAYNMotionDuration.paletteSelection
        case .rowInsert: MAYNMotionDuration.rowInsert
        }
    }
}

enum MAYNMotion {
    static let press = Animation.easeOut(duration: MAYNMotionDuration.press)
    static let hover = Animation.easeOut(duration: MAYNMotionDuration.hover)
    static let control = Animation.easeOut(duration: MAYNMotionDuration.control)
    static let tab = Animation.easeOut(duration: MAYNMotionDuration.tab)
    static let panel = Animation.easeOut(duration: MAYNMotionDuration.panel)
    static let instruction = Animation.easeOut(duration: MAYNMotionDuration.instruction)
    static let toastIn = Animation.easeOut(duration: MAYNMotionDuration.toastIn)
    static let toastOut = Animation.easeOut(duration: MAYNMotionDuration.toastOut)

    static let paletteMorph = Animation.timingCurve(0.16, 1, 0.3, 1, duration: MAYNMotionDuration.paletteMorph)
    static let hudEnter = Animation.easeOut(duration: MAYNMotionDuration.hudEnter)
    static let hudExit = Animation.easeOut(duration: MAYNMotionDuration.hudExit)

    static let fast = press
    static let normal = control

    static func fastAnimation(reduceMotion: Bool) -> Animation? {
        animation(.press, reduceMotion: reduceMotion)
    }

    static func normalAnimation(reduceMotion: Bool) -> Animation? {
        animation(.control, reduceMotion: reduceMotion)
    }

    static func hoverAnimation(reduceMotion: Bool) -> Animation? {
        animation(.hover, reduceMotion: reduceMotion)
    }

    static func controlAnimation(reduceMotion: Bool) -> Animation? {
        animation(.control, reduceMotion: reduceMotion)
    }

    static func tabAnimation(reduceMotion: Bool) -> Animation? {
        animation(.tab, reduceMotion: reduceMotion)
    }

    static func panelAnimation(reduceMotion: Bool) -> Animation? {
        animation(.panel, reduceMotion: reduceMotion)
    }

    static func instructionAnimation(reduceMotion: Bool) -> Animation? {
        animation(.instruction, reduceMotion: reduceMotion)
    }

    static func animation(_ kind: MAYNMotionKind, reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        switch kind {
        case .paletteClose:
            return .easeIn(duration: kind.duration)
        case .paletteMorph:
            return .timingCurve(0.16, 1, 0.3, 1, duration: kind.duration)
        default:
            return .easeOut(duration: kind.duration)
        }
    }

    static func paletteMorphAnimation(reduceMotion: Bool) -> Animation? {
        animation(.paletteMorph, reduceMotion: reduceMotion)
    }

    static func sidebarSelectionAnimation(reduceMotion: Bool) -> Animation? {
        animation(.sidebarSelection, reduceMotion: reduceMotion)
    }

    static func paletteCloseAnimation(reduceMotion: Bool) -> Animation? {
        animation(.paletteClose, reduceMotion: reduceMotion)
    }

    static func paletteSelectionAnimation(reduceMotion: Bool) -> Animation? {
        animation(.paletteSelection, reduceMotion: reduceMotion)
    }

    static func rowInsertAnimation(reduceMotion: Bool) -> Animation? {
        animation(.rowInsert, reduceMotion: reduceMotion)
    }

    static func paletteRowStaggerDelay(for index: Int) -> TimeInterval {
        min(Double(index) * MAYNMotionDuration.paletteRowStagger, MAYNMotionDuration.paletteRowStaggerCap)
    }
}

enum MAYNMotionBridge {
    static func effectiveDuration(_ kind: MAYNMotionKind, reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0 : kind.duration
    }

    static func effectiveDuration(_ kind: MAYNMotionKind) -> TimeInterval {
        effectiveDuration(kind, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    static func translation(_ value: CGFloat, reduceMotion: Bool) -> CGFloat {
        reduceMotion ? 0 : value
    }

    static func timingFunction(_ kind: MAYNMotionKind) -> CAMediaTimingFunction {
        switch kind {
        case .toastOut:
            CAMediaTimingFunction(name: .easeIn)
        case .paletteClose:
            CAMediaTimingFunction(name: .easeIn)
        default:
            CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
        }
    }
}

enum MAYNControlMetrics {
    static let controlHeight: CGFloat = 36
    static let inlineTabHeight: CGFloat = 36
    static let dropdownHeight: CGFloat = 36
    static let hotkeyHeight: CGFloat = 22
    /// Command palette / list row keycaps (design §7.8).
    static let keycapHeight: CGFloat = 24
    static let searchFieldHeight: CGFloat = 36
    static let toolbarHeight: CGFloat = 56
    static let sidebarItemHeight: CGFloat = 40
    static let sidebarWidth: CGFloat = 260
    static let controlRadius: CGFloat = 10
    static let keycapRadius: CGFloat = 7
    static let cardRadius: CGFloat = 16
    static let panelRadius: CGFloat = 16
    static let hudRadius: CGFloat = 22
    static let sidebarItemRadius: CGFloat = 12
    static let rowMinHeight: CGFloat = 52
    static let rowHorizontalPadding: CGFloat = 14
    static let rowVerticalPadding: CGFloat = 10
    static let rowControlSpacing: CGFloat = 16
    static let trailingLaneMinWidth: CGFloat = 220
    static let pickerWidth: CGFloat = 180
    static let widePickerWidth: CGFloat = 220
    static let textFieldWidth: CGFloat = 260
    static let wideTextFieldWidth: CGFloat = 300
    static let attentionPillHeight: CGFloat = 36
    static let statusPillHeight: CGFloat = 20
    static let statusPillHorizontalPadding: CGFloat = 7
    static let statusTagFontSize: CGFloat = 10
    static let toastHeight: CGFloat = 36
}

enum MAYNNotificationPillPresentation {
    static let hasOuterShadow = false
    static let hasIconBackground = false
    static let hasCapsuleStroke = false
    static let iconSize = 14
    static let titleFontSize = 14
    static let detailFontSize = 12
    static let iconFrameSize = 16
    static let horizontalPadding = 14
    static let verticalPadding = 10
    static let copyPanelHeight: CGFloat = 50
    static let minimumCopyPanelWidth: CGFloat = 116
    static let iconTextSpacing: CGFloat = 10

    static func copyPanelSize(message: String) -> CGSize {
        let font = NSFont.systemFont(ofSize: CGFloat(titleFontSize), weight: .semibold)
        let textWidth = ceil((message as NSString).size(withAttributes: [.font: font]).width)
        let width = max(
            minimumCopyPanelWidth,
            textWidth + CGFloat(iconFrameSize) + iconTextSpacing + CGFloat(horizontalPadding * 2)
        )
        return CGSize(width: width, height: copyPanelHeight)
    }
}

/// Liquid-glass surface roles (DESIGN.md §3.6). On macOS 26+ prefer `glassEffect` via `maynGlassSurface`.
/// Navigation chrome (sidebar, toolbar) should use `NavigationSplitView` / `.toolbar` without custom backgrounds.
enum MAYNMaterial {
    /// Sidebar, toolbar, titlebar-adjacent chrome.
    case chrome
    /// Settings sections, grouped cards, inset fields.
    case panel
    /// Command palette, sheets, popovers.
    case elevated
    /// Window Hub, Clipboard Dock over arbitrary desktops.
    case overlay

    var material: Material {
        switch self {
        case .chrome: .bar
        case .panel: .thinMaterial
        case .elevated: .regularMaterial
        case .overlay: .ultraThinMaterial
        }
    }

    var borderColor: Color {
        switch self {
        case .chrome: MAYNTheme.hairline
        case .panel, .elevated: MAYNTheme.subtleBorder
        case .overlay: MAYNTheme.hairline
        }
    }

    var shadowOpacity: Double {
        switch self {
        case .chrome, .panel: 0
        case .elevated: 0.12
        case .overlay: 0.08
        }
    }

    var shadowRadius: CGFloat {
        switch self {
        case .chrome, .panel: 0
        case .elevated: 16
        case .overlay: 12
        }
    }
}
