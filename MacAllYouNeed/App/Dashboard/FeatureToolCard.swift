import SwiftUI
import FeatureCore

/// A wrapper around `MAYNToolCard` that adds feature lifecycle state UI.
///
/// When `state` is nil the card behaves exactly like a plain `MAYNToolCard`
/// (full opacity, click → `onOpen`). When a `FeatureRuntimeState` is
/// supplied the card overlays a status badge, an inline action button, and
/// adjusts opacity to reflect install / enable state.
///
/// Callers inject tool-specific footer content via the `toolFooter` ViewBuilder.
/// The footer is automatically hidden when the feature is not usable
/// (disabled, not downloaded, downloading, or failed).
struct FeatureToolCard<Footer: View>: View {

    // MARK: Static content

    let title: String
    let subtitle: String
    let symbolName: String
    let accent: Color
    let fixedHeight: CGFloat

    // MARK: Feature state

    /// nil  → not feature-managed; behaves like a plain MAYNToolCard.
    let state: FeatureRuntimeState?

    /// true while an `applyTransition` Task is in flight (but state has not
    /// changed to `.downloading` yet). Shows a small spinner in the badge area.
    let isPending: Bool

    // MARK: Actions

    var onOpen: (() -> Void)?
    var onEnable: () -> Void
    var onDisable: () -> Void
    var onInstall: () -> Void
    var onCancelDownload: () -> Void
    var onRetryInstall: () -> Void
    var onUninstall: () -> Void

    // MARK: Tool-specific footer

    @ViewBuilder let toolFooter: () -> Footer

    // MARK: Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Body

    var body: some View {
        MAYNToolCard(
            title: title,
            subtitle: subtitle,
            symbolName: symbolName,
            accent: accent,
            fixedHeight: fixedHeight,
            action: cardAction
        ) {
            VStack(alignment: .leading, spacing: 8) {
                // Status / action row
                HStack(spacing: 8) {
                    statusBadge
                    Spacer(minLength: 0)
                    inlineButton
                }

                // Tool-specific footer — shown only when the tool is usable
                if showFooter {
                    toolFooter()
                }
            }
        }
        .opacity(cardOpacity)
        .animation(MAYNMotion.controlAnimation(reduceMotion: reduceMotion), value: cardOpacity)
        .contextMenu { contextMenuItems }
    }

    // MARK: Derived properties

    /// The tap action forwarded to MAYNToolCard.
    /// nil disables the built-in card press gesture.
    private var cardAction: (() -> Void)? {
        switch visualState {
        case .unmanaged, .enabled: return onOpen
        case .disabled, .notDownloaded, .downloading, .failed: return nil
        }
    }

    private var cardOpacity: Double {
        switch visualState {
        case .unmanaged, .enabled: 1.0
        case .disabled, .notDownloaded: 0.45
        case .downloading, .failed: 0.65
        }
    }

    private var showFooter: Bool {
        switch visualState {
        case .unmanaged, .enabled: true
        case .disabled, .notDownloaded, .downloading, .failed: false
        }
    }

    // MARK: Status badge

    @ViewBuilder
    private var statusBadge: some View {
        switch visualState {
        case .unmanaged:
            // No badge for non-feature-managed tiles
            EmptyView()
        case .enabled:
            StatusPill(text: "Enabled", kind: .success)
        case .disabled:
            if isPending {
                pendingSpinner
            } else {
                StatusPill(text: "Disabled", kind: .neutral)
            }
        case .notDownloaded:
            if isPending {
                pendingSpinner
            } else {
                StatusPill(text: "Not installed", kind: .neutral)
            }
        case .downloading(let progress):
            ProgressView(value: progress, total: 1.0)
                .progressViewStyle(.linear)
                .frame(maxWidth: 100)
                .tint(MAYNTheme.progress)
                .accessibilityLabel("Downloading: \(Int(progress * 100))%")
        case .failed:
            if isPending {
                pendingSpinner
            } else {
                StatusPill(text: "Failed", kind: .danger)
            }
        }
    }

    /// Small indeterminate spinner shown when a transition is in-flight
    /// and state is not `.downloading` (which has its own progress bar).
    private var pendingSpinner: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .controlSize(.small)
            .accessibilityLabel("In progress")
    }

    // MARK: Inline button

    @ViewBuilder
    private var inlineButton: some View {
        switch visualState {
        case .unmanaged, .enabled:
            EmptyView()
        case .disabled:
            MAYNButton("Enable", role: .primary, action: onEnable)
        case .notDownloaded:
            MAYNButton("Install", role: .primary, action: onInstall)
        case .downloading:
            MAYNButton("Cancel", role: .secondary, action: onCancelDownload)
        case .failed:
            MAYNButton("Retry", role: .primary, action: onRetryInstall)
        }
    }

    // MARK: Context menu

    @ViewBuilder
    private var contextMenuItems: some View {
        // Open — only when the tool is usable
        switch visualState {
        case .unmanaged, .enabled:
            Button("Open \(title)") { onOpen?() }
        case .disabled, .notDownloaded, .downloading, .failed:
            EmptyView()
        }

        // Lifecycle section — only for feature-managed tiles
        switch visualState {
        case .unmanaged:
            EmptyView()
        case .enabled:
            Divider()
            Button("Disable") { onDisable() }
        case .disabled:
            Divider()
            Button("Enable") { onEnable() }
        case .notDownloaded:
            Divider()
            Button("Install…") { onInstall() }
        case .downloading:
            Divider()
            Button("Cancel Download") { onCancelDownload() }
        case .failed:
            Divider()
            Button("Retry Install") { onRetryInstall() }
        }

        // Uninstall — only for asset-backed features that are present
        if showUninstallOption {
            Button("Uninstall…", role: .destructive) { onUninstall() }
        }

        Divider()

        // About — stubbed; will be wired in Task 2
        Button("About \(title)…") {}
    }

    // MARK: Uninstall visibility

    /// Show "Uninstall…" when the feature has an asset pack and it is present.
    private var showUninstallOption: Bool {
        guard let s = state else { return false }
        if case .present = s.assetState { return true }
        return false
    }

    // MARK: Visual state helper

    private enum VisualState: Equatable {
        /// Not feature-managed: no badge, full opacity, tap → onOpen.
        case unmanaged
        /// Feature-managed and enabled.
        case enabled
        case disabled
        case notDownloaded
        case downloading(progress: Double)
        case failed
    }

    private var visualState: VisualState {
        guard let s = state else { return .unmanaged }
        switch s.assetState {
        case .notRequired, .present:
            return s.activationState == .enabled ? .enabled : .disabled
        case .notDownloaded:
            return .notDownloaded
        case .downloading(let progress):
            return .downloading(progress: progress)
        case .downloadFailed:
            return .failed
        }
    }
}
