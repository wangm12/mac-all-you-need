import SwiftUI
import FeatureCore

/// A dashboard tool card with feature lifecycle UI aligned to Dock Features toggles.
///
/// Feature-managed tiles use `DashboardFeatureCardShell` with a bottom switch for
/// enable/disable. Install, download, and failure states keep status + action at
/// the bottom instead of a switch.
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
    /// changed to `.downloading` yet). Shows a small spinner overlaid in the
    /// top-right corner of the card; the status badge remains visible.
    let isPending: Bool

    // MARK: Actions

    var onOpen: (() -> Void)?
    var onEnable: (() -> Void)? = nil
    var onDisable: (() -> Void)? = nil
    var onInstall: (() -> Void)? = nil
    var onCancelDownload: (() -> Void)? = nil
    var onRetryInstall: (() -> Void)? = nil

    // MARK: Tool-specific footer

    @ViewBuilder let toolFooter: () -> Footer

    // MARK: Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Body

    var body: some View {
        Group {
            if state != nil {
                featureManagedCard
            } else {
                unmanagedCard
            }
        }
    }

    // MARK: Feature-managed card (Dock Features layout)

    private var featureManagedCard: some View {
        DashboardFeatureCardShell(
            title: title,
            subtitle: subtitle,
            symbolName: symbolName,
            accent: accent,
            fixedHeight: fixedHeight,
            isHighlighted: visualState == .enabled,
            onHeaderTap: cardAction,
            middle: {
                if showFooter {
                    toolFooter()
                }
            },
            bottom: { lifecycleBottom }
        )
        .opacity(cardOpacity)
        .animation(MAYNMotion.controlAnimation(reduceMotion: reduceMotion), value: cardOpacity)
        .overlay(alignment: .topTrailing) {
            if isPending, case .downloading = visualState {} else if isPending {
                ProgressView()
                    .controlSize(.small)
                    .padding(8)
                    .accessibilityLabel("Operation pending for \(title)")
            }
        }
    }

    // MARK: Unmanaged card (no feature runtime)

    private var unmanagedCard: some View {
        MAYNToolCard(
            title: title,
            subtitle: subtitle,
            symbolName: symbolName,
            accent: accent,
            fixedHeight: fixedHeight,
            action: onOpen
        ) {
            toolFooter()
        }
    }

    // MARK: Bottom lifecycle control

    @ViewBuilder
    private var lifecycleBottom: some View {
        switch visualState {
        case .unmanaged:
            EmptyView()
        case .enabled, .disabled:
            Toggle("", isOn: enableBinding)
                .labelsHidden()
                .controlSize(.small)
                .maynSwitchToggleStyle()
                .disabled(isPending)
                .accessibilityLabel("\(title), \(visualState == .enabled ? "enabled" : "disabled")")
        case .notDownloaded:
            HStack(spacing: 8) {
                StatusPill(text: "Not installed", kind: .neutral)
                Spacer(minLength: 0)
                MAYNButton("Install", role: .primary, action: { onInstall?() })
            }
        case .downloading(let progress):
            ProgressView(value: progress, total: 1.0)
                .progressViewStyle(.linear)
                .tint(MAYNTheme.progress)
                .accessibilityLabel("Downloading: \(Int(progress * 100))%")
        case .failed(let reason):
            HStack(spacing: 8) {
                StatusPill(text: "Failed", kind: .danger)
                    .accessibilityLabel("Download failed for \(title): \(reason)")
                Spacer(minLength: 0)
                MAYNButton("Retry", role: .primary, action: { onRetryInstall?() })
            }
        }
    }

    private var enableBinding: Binding<Bool> {
        Binding(
            get: { visualState == .enabled },
            set: { enabled in
                if enabled {
                    onEnable?()
                } else {
                    onDisable?()
                }
            }
        )
    }

    // MARK: Derived properties

    /// The tap action for the card header.
    /// nil disables the built-in header press gesture.
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

    // MARK: Visual state helper

    private enum VisualState: Equatable {
        /// Not feature-managed: no badge, full opacity, tap → onOpen.
        case unmanaged
        /// Feature-managed and enabled.
        case enabled
        case disabled
        case notDownloaded
        case downloading(progress: Double)
        case failed(reason: String)
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
        case .downloadFailed(let reason):
            return .failed(reason: reason)
        }
    }
}
