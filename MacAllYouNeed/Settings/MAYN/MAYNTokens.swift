import AppKit
import QuartzCore
import SwiftUI

enum MAYNTheme {
    static let window = Color(nsColor: .windowBackgroundColor)
    static let panel = Color(nsColor: .controlBackgroundColor)
    static let elevated = Color(nsColor: .textBackgroundColor)
    static let elevatedHover = Color.primary.opacity(0.045)
    static let elevatedPressed = Color.primary.opacity(0.075)
    static let divider = Color.secondary.opacity(0.16)
    static let selected = Color.primary.opacity(0.08)
    static let hover = Color.primary.opacity(0.05)
    static let muted = Color.secondary
    static let strongBorder = Color.primary.opacity(0.18)
    static let subtleBorder = Color.primary.opacity(0.10)
    static let focusRing = Color.primary.opacity(0.70)
    static let controlTint = Color.secondary
    /// macOS-style green for `Toggle(.switch)` ON state (not overridden by shell `.accentColor(.gray)`).
    static let switchTint = Color.green
    static let tabSelectedFill = Color.primary.opacity(0.14)
    static let tabSelectedBorder = Color.primary.opacity(0.20)
    static let tabSelectedShadow = Color.black.opacity(0.06)
    static let success = Color.green
    static let warning = Color.orange
    static let danger = Color.red
    static let progress = Color.blue
}

enum MAYNMotionDuration {
    static let press: TimeInterval = 0.12
    static let hover: TimeInterval = 0.16
    static let control: TimeInterval = 0.18
    static let tab: TimeInterval = 0.23
    static let panel: TimeInterval = 0.28
    static let instruction: TimeInterval = 0.32
    static let toastIn: TimeInterval = 0.16
    static let toastOut: TimeInterval = 0.22
}

enum MAYNMotionKind {
    case press
    case hover
    case control
    case tab
    case panel
    case instruction
    case toastIn
    case toastOut

    var duration: TimeInterval {
        switch self {
        case .press: MAYNMotionDuration.press
        case .hover: MAYNMotionDuration.hover
        case .control: MAYNMotionDuration.control
        case .tab: MAYNMotionDuration.tab
        case .panel: MAYNMotionDuration.panel
        case .instruction: MAYNMotionDuration.instruction
        case .toastIn: MAYNMotionDuration.toastIn
        case .toastOut: MAYNMotionDuration.toastOut
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
        return .easeOut(duration: kind.duration)
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
        default:
            CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
        }
    }
}

enum MAYNControlMetrics {
    static let controlHeight: CGFloat = 30
    static let inlineTabHeight: CGFloat = controlHeight
    static let dropdownHeight: CGFloat = controlHeight
    static let hotkeyHeight: CGFloat = controlHeight
    static let controlRadius: CGFloat = 7
    static let cardRadius: CGFloat = 8
    static let panelRadius: CGFloat = 8
    static let rowMinHeight: CGFloat = 46
    static let rowHorizontalPadding: CGFloat = 14
    static let rowVerticalPadding: CGFloat = 9
    static let rowControlSpacing: CGFloat = 16
    static let trailingLaneMinWidth: CGFloat = 220
    static let pickerWidth: CGFloat = 180
    static let widePickerWidth: CGFloat = 220
    static let textFieldWidth: CGFloat = 260
    static let wideTextFieldWidth: CGFloat = 300
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
