import AppKit
import FeatureCore
import SwiftUI

// MARK: - Layout

enum CommandCenterMetrics {
    static let width: CGFloat = 520
    static let height: CGFloat = 600
    static let shellRadius: CGFloat = 28
    static let markSize: CGFloat = 34
    static let markRadius: CGFloat = 12
    static let iconButtonSize: CGFloat = 32
    static let footerHeight: CGFloat = 52
}

// MARK: - Status subtitle

@MainActor
enum CommandCenterStatusPresentation {
    static func subtitle(
        registry: FeatureRegistry,
        stateFor: (FeatureID) -> FeatureRuntimeState,
        failedDownloadCount: Int,
        orphanCacheCount: Int
    ) -> String {
        let activeCount = registry.descriptors.filter {
            stateFor($0.id).activationState == .enabled
        }.count
        let activePart = "\(activeCount) active tool\(activeCount == 1 ? "" : "s")"
        let attention = CommandPaletteAttentionPlanner.snapshot(
            registry: registry,
            stateFor: stateFor,
            failedDownloadCount: failedDownloadCount,
            orphanCacheCount: orphanCacheCount
        )
        if let badge = attention.badgeTitle {
            return "\(activePart) · \(badge)"
        }
        return activePart
    }
}

// MARK: - Footer Model

struct CommandCenterFooterModel: Equatable {
    let shortcutText: String?
    let label: String
    let openButtonTitle: String
    let showsCapturePause: Bool
}

// MARK: - Footer Presentation

enum CommandCenterFooterPresentation {
    static func model(
        for tab: AppMenuBarContent.Tab,
        voiceShortcut: String = VoiceActivationSettingsStore.load().shortcut.display
    ) -> CommandCenterFooterModel {
        switch tab {
        case .clipboard:
            CommandCenterFooterModel(
                shortcutText: "⌘⇧V",
                label: "clipboard dock",
                openButtonTitle: "Open Clipboard",
                showsCapturePause: true
            )
        case .voice:
            CommandCenterFooterModel(
                shortcutText: voiceShortcut,
                label: "voice dictation",
                openButtonTitle: "Open Voice",
                showsCapturePause: false
            )
        case .downloads:
            CommandCenterFooterModel(
                shortcutText: nil,
                label: "downloads",
                openButtonTitle: "Open Downloads",
                showsCapturePause: false
            )
        case .reminders:
            CommandCenterFooterModel(
                shortcutText: VoiceReminderShortcutSettingsStore.load().shortcut.display,
                label: "reminder shortcut",
                openButtonTitle: "Open Voice",
                showsCapturePause: false
            )
        }
    }
}

// MARK: - Tab Bar

struct CommandCenterTabBar: View {
    @Binding var selection: AppMenuBarContent.Tab
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        FunctionSegmentedTabStrip(
            tabs: Array(AppMenuBarContent.Tab.allCases),
            selection: selection,
            fillsAvailableWidth: true,
            size: .header
        ) { next in
            selection = next
        }
        .background {
            // Match main-window pages: glass track over a stable surface, not parent glass.
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(MAYNTheme.contentWindow(colorScheme))
        }
    }
}

// MARK: - Top chrome

struct CommandCenterTopChrome: View {
    let statusSubtitle: String
    let onOpenCommandPalette: () -> Void
    let onOpenSettings: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                productMark
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    CommandCenterIconButton(
                        symbolName: "square.grid.2x2",
                        accessibilityLabel: "Command Palette",
                        action: onOpenCommandPalette
                    )
                    .help("Command Palette")
                    CommandCenterIconButton(
                        symbolName: "gearshape",
                        accessibilityLabel: "Settings",
                        action: onOpenSettings
                    )
                    .help("Settings")
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var productMark: some View {
        HStack(spacing: 10) {
            Group {
                if let icon = NSApplication.shared.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(MAYNTheme.textPrimary(colorScheme))
                }
            }
            .frame(width: CommandCenterMetrics.markSize, height: CommandCenterMetrics.markSize)
            .clipShape(RoundedRectangle(cornerRadius: CommandCenterMetrics.markRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: CommandCenterMetrics.markRadius, style: .continuous)
                    .stroke(MAYNTheme.hairline, lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Mac All You Need")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(MAYNTheme.textPrimary(colorScheme))
                Text(statusSubtitle)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(MAYNTheme.textTertiary(colorScheme))
                    .lineLimit(1)
            }
        }
    }
}

struct CommandCenterIconButton: View {
    let symbolName: String
    let accessibilityLabel: String
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MAYNTheme.textSecondary(colorScheme))
                .frame(width: CommandCenterMetrics.iconButtonSize, height: CommandCenterMetrics.iconButtonSize)
                .maynGlassSurface(
                    .chrome,
                    cornerRadius: CommandCenterMetrics.iconButtonSize / 2,
                    showsBorder: true,
                    showsShadow: false
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Page header

struct CommandCenterPageHeader: View {
    let title: String
    let subtitle: String
    let actionTitle: String
    let onAction: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(MAYNTheme.textPrimary(colorScheme))
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MAYNTheme.textSecondary(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            MAYNButton(actionTitle, role: .primary, height: HotkeyChipPresentation.compactHeight, action: onAction)
                .maynGlassButtonStyle(isProminent: true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
}

// MARK: - Section label

struct CommandCenterSectionLabel: View {
    let title: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .kerning(0.75)
            .foregroundStyle(MAYNTheme.textTertiary(colorScheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 7)
    }
}

// MARK: - Attention strip

struct CommandCenterAttentionStrip: View {
    let title: String
    let detail: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(MAYNTheme.textSecondary(colorScheme))
                .frame(width: 8, height: 8)
                .opacity(0.7)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MAYNTheme.textPrimary(colorScheme))
                Text(detail)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(MAYNTheme.textSecondary(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(MAYNTheme.panelSubtle, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(MAYNTheme.hairline, lineWidth: 1)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }
}

// MARK: - Footer

struct CommandCenterFooter: View {
    let model: CommandCenterFooterModel
    let onOpen: () -> Void
    let onPauseCapture: () -> Void
    let onQuit: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(MAYNTheme.hairline)
                .frame(height: 1)
            HStack(spacing: 10) {
                if let shortcutText = model.shortcutText {
                    ShortcutChip(text: shortcutText, height: HotkeyChipPresentation.compactHeight)
                }
                Text(model.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MAYNTheme.textTertiary(colorScheme))
                    .lineLimit(1)
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    MAYNButton(model.openButtonTitle, role: .secondary, height: HotkeyChipPresentation.compactHeight, action: onOpen)
                        .maynGlassButtonStyle()
                    if model.showsCapturePause {
                        MAYNButton("Pause 60s", role: .secondary, height: HotkeyChipPresentation.compactHeight, action: onPauseCapture)
                            .maynGlassButtonStyle()
                    }
                    MAYNButton("Quit", role: .destructive, height: HotkeyChipPresentation.compactHeight, action: onQuit)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(height: CommandCenterMetrics.footerHeight)
            .background(MAYNTheme.panelSubtle)
        }
    }
}
