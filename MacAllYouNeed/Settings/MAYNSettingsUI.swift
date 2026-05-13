import AppKit
import SwiftUI

enum MAYNTheme {
    static let window = Color(nsColor: .windowBackgroundColor)
    static let panel = Color(nsColor: .controlBackgroundColor)
    static let elevated = Color(nsColor: .textBackgroundColor)
    static let divider = Color.secondary.opacity(0.16)
    static let selected = Color.primary.opacity(0.08)
    static let hover = Color.primary.opacity(0.05)
    static let muted = Color.secondary
    static let strongBorder = Color.primary.opacity(0.18)
    static let subtleBorder = Color.primary.opacity(0.10)
    static let focusRing = Color.primary.opacity(0.70)
    static let controlTint = Color.secondary
    static let success = Color.green
    static let warning = Color.orange
    static let danger = Color.red
    static let progress = Color.blue
}

enum MAYNMotion {
    static let fast = Animation.easeOut(duration: 0.12)
    static let normal = Animation.easeOut(duration: 0.18)
    static let panel = Animation.easeOut(duration: 0.24)
    static let instruction = Animation.easeOut(duration: 0.32)

    static func fastAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : fast
    }

    static func normalAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : normal
    }

    static func panelAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : panel
    }

    static func instructionAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : instruction
    }
}

struct MAYNSettingsShell<Sidebar: View, Detail: View>: View {
    @ViewBuilder let sidebar: Sidebar
    @ViewBuilder let detail: Detail

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .tint(MAYNTheme.controlTint)
        .accentColor(.gray)
        .frame(minWidth: 760, idealWidth: 900, minHeight: 520, idealHeight: 640)
        .background(SettingsWindowConfig())
    }
}

struct MAYNSettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 24, weight: .semibold))
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                content
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
        }
        .background(MAYNTheme.window)
    }
}

struct MAYNSection<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 0) {
                content
            }
            .background(MAYNTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
            )
        }
    }
}

struct MAYNSettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var minHeight: CGFloat = 46
    @ViewBuilder let trailing: Trailing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(minHeight: minHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovering ? MAYNTheme.hover : Color.clear)
        .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: isHovering)
        .onHover { isHovering = $0 }
    }
}

struct MAYNDivider: View {
    var body: some View {
        Rectangle()
            .fill(MAYNTheme.divider)
            .frame(height: 1)
            .padding(.leading, 14)
    }
}

struct MAYNNumericStepper: View {
    let text: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1

    var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 58, alignment: .trailing)
            Stepper("", value: $value, in: range, step: step)
                .labelsHidden()
                .frame(width: 34)
        }
        .fixedSize()
    }
}

struct ShortcutChip: View {
    let text: String

    var body: some View {
        Text(text.isEmpty ? "Not set" : text)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
            )
    }
}

struct StatusPill: View {
    enum Kind {
        case neutral
        case success
        case warning
        case danger
        case progress
    }

    let text: String
    var kind: Kind = .neutral

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.caption)
        }
        .foregroundStyle(kind == .neutral ? .secondary : .primary)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(color.opacity(kind == .neutral ? 0.08 : 0.14), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(kind == .neutral ? 0.14 : 0.30), lineWidth: 1))
    }

    private var color: Color {
        switch kind {
        case .neutral: Color.secondary
        case .success: MAYNTheme.success
        case .warning: MAYNTheme.warning
        case .danger: MAYNTheme.danger
        case .progress: MAYNTheme.progress
        }
    }
}

struct PermissionCard: View {
    enum StateKind {
        case granted
        case needed
        case denied
        case optional
    }

    let title: String
    let reason: String
    let state: StateKind
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.callout.weight(.medium))
                    StatusPill(text: stateText, kind: pillKind)
                }
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button(actionTitle, action: action)
                .disabled(state == .granted)
        }
        .padding(14)
        .background(MAYNTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
        )
    }

    private var symbol: String {
        switch state {
        case .granted: "checkmark.circle.fill"
        case .needed: "circle"
        case .denied: "exclamationmark.triangle.fill"
        case .optional: "circle.dashed"
        }
    }

    private var color: Color {
        switch state {
        case .granted: MAYNTheme.success
        case .needed: MAYNTheme.progress
        case .denied: MAYNTheme.warning
        case .optional: Color.secondary
        }
    }

    private var stateText: String {
        switch state {
        case .granted: "Granted"
        case .needed: "Needs setup"
        case .denied: "Blocked"
        case .optional: "Optional"
        }
    }

    private var pillKind: StatusPill.Kind {
        switch state {
        case .granted: .success
        case .needed: .progress
        case .denied: .warning
        case .optional: .neutral
        }
    }
}

struct InstructionStrip: View {
    let text: String
    var appName: String = "MacAllYouNeed"
    var symbol: String = "arrow.up"

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(text)
                    .font(.callout)
                Text(appName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(MAYNTheme.strongBorder, lineWidth: 1)
        )
    }
}

struct MAYNToastContent: View {
    let message: String
    let symbol: String
    var isDestructive = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
            Text(message)
                .font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(isDestructive ? .white : Color(nsColor: .controlBackgroundColor))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isDestructive ? Color.red : Color.primary, in: Capsule())
        .shadow(color: .black.opacity(0.20), radius: 14, y: 5)
    }
}

struct MAYNToast: View {
    let message: String
    var symbol = "checkmark.circle.fill"
    var isDestructive = false

    var body: some View {
        MAYNToastContent(message: message, symbol: symbol, isDestructive: isDestructive)
    }
}
