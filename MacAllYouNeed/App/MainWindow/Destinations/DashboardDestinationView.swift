import AppKit
import Core
import FeatureCore
import SwiftUI

struct DashboardDestinationView: View {
    @Bindable var controller: AppController
    let openDestination: (MainAppDestination) -> Void
    private var statePublisher: FeatureStatePublisher
    @State private var pendingFeatureIDs: Set<FeatureID> = []
    @State private var retryingFeatureIDs: Set<FeatureID> = []
    @Environment(\.colorScheme) private var colorScheme

    init(controller: AppController, openDestination: @escaping (MainAppDestination) -> Void) {
        self.controller = controller
        self.openDestination = openDestination
        self.statePublisher = controller.featureStatePublisher
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                dashboardHeader
                statusStrip
                setupPrompt
                recommendedActions
                recentActivityStrip
                toolGrid
            }
            .frame(maxWidth: 1120, alignment: .leading)
            .padding(.horizontal, MAYNSpacing.pageHorizontal)
            .padding(.top, 30)
            .padding(.bottom, 48)
        }
        .contentMargins(.bottom, 12, for: .scrollContent)
        .scrollIndicators(.never)
        .task {
            await controller.downloaderVM.refresh()
        }
    }

    private var dashboardHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Dashboard")
                    .font(MAYNTypography.pageTitle())
                    .lineLimit(1)
                Text("Local tools, shortcuts, and current activity.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusStrip: some View {
        Text(inlineStatusSentence)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var inlineStatusSentence: String {
        var parts: [String] = []
        parts.append(nextPendingFeatureID == nil ? "Ready" : "Setup")
        parts.append("\(enabledFeatureCount) tools active")
        let clipboardCount = controller.clipboardReader.items.count
        parts.append("\(clipboardCount) saved \(clipboardCount == 1 ? "item" : "items")")
        if failedDownloadCount > 0 {
            parts.append("Review \(failedDownloadCount) downloads")
        }
        return parts.joined(separator: " · ")
    }

    private var failedDownloadCount: Int {
        controller.downloaderVM.rows.filter { $0.state == .failed }.count
    }

    @ViewBuilder
    private var recommendedActions: some View {
        let actions = recommendedActionItems
        if !actions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recommended")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MAYNTheme.textPrimary(colorScheme))
                ForEach(actions, id: \.title) { action in
                    MAYNActionCard(
                        title: action.title,
                        subtitle: action.subtitle,
                        action: action.action
                    )
                }
            }
        }
    }

    private struct RecommendedAction {
        let title: String
        let subtitle: String
        let action: () -> Void
    }

    private var recommendedActionItems: [RecommendedAction] {
        var items: [RecommendedAction] = []
        if failedDownloadCount > 0 {
            items.append(
                RecommendedAction(
                    title: "Review \(failedDownloadCount) downloads",
                    subtitle: "Resolve files that need attention.",
                    action: { openDestination(.downloads) }
                )
            )
        }
        if let pendingFeatureID = nextPendingFeatureID,
           let title = pendingFeatureTitle(for: pendingFeatureID) {
            items.append(
                RecommendedAction(
                    title: "Complete \(title) setup",
                    subtitle: "Finish the feature onboarding wizard.",
                    action: { controller.showFeatureOnboarding(pendingFeatureID) }
                )
            )
        }
        return items
    }

    @ViewBuilder
    private var recentActivityStrip: some View {
        let recent = Array(controller.clipboardReader.items.prefix(5))
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Recent activity")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(MAYNTheme.textPrimary(colorScheme))
                    Spacer(minLength: 8)
                    Button("View all") {
                        openDestination(.clipboard)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(MAYNTheme.textSecondary(colorScheme))
                }
                MAYNListPanel(title: "", subtitle: nil) {
                    ForEach(Array(recent.enumerated()), id: \.element.id.rawValue) { index, item in
                        if index > 0 { MAYNDivider() }
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.customLabel ?? item.preview)
                                    .font(.callout)
                                    .foregroundStyle(MAYNTheme.textPrimary(colorScheme))
                                    .lineLimit(1)
                                Text(CompactTimestamp.format(item.modified))
                                    .font(.caption)
                                    .foregroundStyle(MAYNTheme.textTertiary(colorScheme))
                            }
                            Spacer(minLength: 8)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(minHeight: 44)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var setupPrompt: some View {
        if let pendingFeatureID = nextPendingFeatureID,
           let pendingTitle = pendingFeatureTitle(for: pendingFeatureID) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        StatusPill(text: "Setup remaining", kind: .needsPermission)
                        Text("\(completedFeatureCount)/\(enabledFeatureCount) complete")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("Finish \(pendingTitle) setup")
                        .font(.callout.weight(.semibold))

                    Text("This keeps the product on the fastest path: enable the feature, complete its setup wizard, then start using the shortcut immediately.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                MAYNButton("Continue setup", role: .primary) {
                    controller.showFeatureOnboarding(pendingFeatureID)
                }
            }
            .padding(14)
            .background(MAYNTheme.panel, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous)
                    .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
            )
        }
    }

    private var toolGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            alignment: .leading,
            spacing: 12
        ) {
            ForEach(dashboardTiles) { tile in
                FeatureToolCard(
                    title: tile.title,
                    subtitle: tile.detail,
                    symbolName: tile.symbolName,
                    accent: accent(for: tile.destination),
                    fixedHeight: DashboardRenderingPresentation.toolCardHeight,
                    state: state(for: tile),
                    isPending: transitionTargets(for: tile).contains { pendingFeatureIDs.contains($0) },
                    onOpen: { openTile(tile) },
                    onEnable: { Task { await handleAction(.enable, for: tile) } },
                    onDisable: { Task { await handleAction(.disable, for: tile) } },
                    onInstall: { Task { await handleAction(.install, for: tile) } },
                    onCancelDownload: { Task { await handleAction(.cancelDownload, for: tile) } },
                    onRetryInstall: { Task { await handleAction(.retryInstall, for: tile) } }
                ) {
                    DashboardToolCardFooter(
                        tile: tile,
                        voiceStatus: voiceStatus,
                        isRetrying: retryingFeatureIDs.contains(where: { transitionTargets(for: tile).contains($0) })
                    )
                }
            }
        }
    }

    private var dashboardTiles: [DashboardToolTileItem] {
        DashboardToolTilePresentation.dashboardTiles(
            clipboardCount: controller.clipboardReader.items.count,
            downloadsQueueCount: DashboardDownloadSummaryPresentation.activeQueueCount(in: controller.downloaderVM.rows),
            hotkeys: HotkeyMapStore.load(),
            voiceSettings: VoiceActivationSettingsStore.load(),
            windowControlSettings: WindowControlSettingsStore.load(),
            windowControlAXTrusted: AXIsProcessTrusted(),
            windowControlState: controller.windowControl.state,
            windowLayoutsFeatureEnabled: controller.windowControl.windowLayoutsEnabled,
            windowGrabFeatureEnabled: controller.windowControl.windowGrabEnabled
        )
    }

    private var enabledFeatureCount: Int {
        registryOrder.filter { isFeatureEnabled($0) }.count
    }

    private var completedFeatureCount: Int {
        registryOrder.filter { isFeatureEnabled($0) && FeatureOnboardingProgressStore.isCompleted($0) }.count
    }

    private var nextPendingFeatureID: FeatureID? {
        FeatureOnboardingProgressStore.firstPending(
            in: registryOrder,
            enabled: isFeatureEnabled(_:)
        )
    }

    private var registryOrder: [FeatureID] {
        controller.runtime.registry.descriptors.map(\.id)
    }

    private func isFeatureEnabled(_ id: FeatureID) -> Bool {
        statePublisher.state(for: id).activationState == .enabled
    }

    private func nextPendingFeatureTitle(for featureID: FeatureID?) -> String {
        guard let featureID, let title = pendingFeatureTitle(for: featureID) else {
            return "Ready"
        }
        return title
    }

    private func pendingFeatureTitle(for featureID: FeatureID) -> String? {
        controller.runtime.registry.descriptor(for: featureID)?.displayName
    }

    private func openPermissions() {
        AppGroupSettings.defaults.set(SettingsDestination.permissions.rawValue, forKey: DockSettingsNavigation.settingsSelectionKey)
        openDestination(.settings)
    }

    private func openTile(_ tile: DashboardToolTileItem) {
        if !isTileEnabled(tile) {
            handleDisabledTile(tile)
            return
        }
        let route = DashboardToolOpenNavigation.route(for: tile.destination)
        if let tabStorageKey = route.tabStorageKey, let tabRawValue = route.tabRawValue {
            AppGroupSettings.defaults.set(tabRawValue, forKey: tabStorageKey)
        }
        openDestination(route.destination)
    }

    private func handleDisabledTile(_ tile: DashboardToolTileItem) {
        guard let featureID = tile.proxiesFeatureID ?? tile.featureID else { return }
        if let descriptor = controller.runtime.registry.descriptor(for: featureID),
           !descriptor.requiredPermissions.isEmpty {
            openPermissions()
            return
        }
        controller.showFeatureOnboardingIfNeeded(for: featureID)
    }

    private func isTileEnabled(_ tile: DashboardToolTileItem) -> Bool {
        transitionTargets(for: tile).allSatisfy {
            statePublisher.state(for: $0).activationState == .enabled
        }
    }

    private func transitionTargets(for tile: DashboardToolTileItem) -> [FeatureID] {
        guard let featureID = tile.proxiesFeatureID ?? tile.featureID else { return [] }
        var ids = [featureID]
        for coupled in tile.coupledFeatureIDs where coupled != featureID {
            ids.append(coupled)
        }
        return ids
    }

    // MARK: Feature helpers

    private func state(for tile: DashboardToolTileItem) -> FeatureRuntimeState? {
        guard tile.featureID != nil else { return nil }
        let ids = transitionTargets(for: tile)
        let states = ids.map { statePublisher.state(for: $0) }
        guard let primary = states.first else { return nil }
        if states.allSatisfy({ $0.activationState == .enabled }) {
            return primary
        }
        return FeatureRuntimeState(assetState: primary.assetState, activationState: .disabled)
    }

    // MARK: Action dispatch

    private enum DashboardFeatureAction {
        case enable, disable, install, cancelDownload, retryInstall
    }

    private func handleAction(_ action: DashboardFeatureAction, for tile: DashboardToolTileItem) async {
        let targetIDs = transitionTargets(for: tile)
        guard !targetIDs.isEmpty else { return }
        for targetID in targetIDs {
            pendingFeatureIDs.insert(targetID)
        }
        defer {
            for targetID in targetIDs {
                pendingFeatureIDs.remove(targetID)
            }
        }

        switch action {
        case .enable:
            for targetID in targetIDs {
                try? await controller.runtime.applyTransition(.enable, for: targetID)
                controller.showFeatureOnboardingIfNeeded(for: targetID)
            }
        case .disable:
            for targetID in targetIDs {
                try? await controller.runtime.applyTransition(.disable, for: targetID)
            }
        case .install:
            guard let targetID = targetIDs.first else { return }
            try? await controller.packInstallController.install(featureID: targetID)
            await controller.featureStatePublisher.refresh()
        case .cancelDownload:
            guard let targetID = targetIDs.first else { return }
            await controller.packInstallController.cancel(featureID: targetID)
            await controller.featureStatePublisher.refresh()
        case .retryInstall:
            guard let targetID = targetIDs.first else { return }
            retryingFeatureIDs.formUnion(targetIDs)
            defer {
                for targetID in targetIDs {
                    retryingFeatureIDs.remove(targetID)
                }
            }
            try? await controller.packInstallController.install(featureID: targetID)
            await controller.featureStatePublisher.refresh()
        }
    }

    // MARK: Voice status

    private var voiceStatus: DashboardVoiceStatusPresentation.Status? {
        DashboardVoiceStatusPresentation.footerStatus(for: controller.voiceCoordinator.state)
    }

    private func accent(for destination: MainAppDestination) -> Color {
        DashboardToolTilePresentation.accent(for: destination)
    }
}

private struct DashboardToolCardFooter: View {
    let tile: DashboardToolTileItem
    let voiceStatus: DashboardVoiceStatusPresentation.Status?
    let isRetrying: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if let metric = tile.metric {
                contextualMetricLine(metric: metric)
            } else if isRetrying {
                StatusPill(text: "Retrying", kind: .progress)
            } else if tile.destination == .voice, let voiceStatus {
                StatusPill(text: voiceStatus.text, kind: voiceStatus.kind)
            } else if let statusText = tile.statusText, let statusKind = tile.statusKind {
                StatusPill(text: statusText, kind: statusKind)
            }

            Spacer(minLength: 8)

            if let shortcutDisplay = tile.shortcutDisplay {
                ShortcutChip(text: shortcutDisplay, height: HotkeyChipPresentation.compactHeight)
            }
        }
        .frame(height: 34, alignment: .center)
    }

    @ViewBuilder
    private func contextualMetricLine(metric: String) -> some View {
        let context = DashboardMetricPresentation.contextualLine(
            metric: metric,
            destination: tile.destination
        )
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(context.value)
                .font(MAYNTypography.body(strong: true))
                .monospacedDigit()
                .foregroundStyle(MAYNTheme.textPrimary(colorScheme))
            if !context.unit.isEmpty {
                Text(context.unit)
                    .font(.caption)
                    .foregroundStyle(MAYNTheme.textSecondary(colorScheme))
            }
        }
    }
}

enum DashboardMetricPresentation {
    struct ContextualLine: Equatable {
        let value: String
        let unit: String
    }

    static func contextualLine(metric: String, destination: MainAppDestination) -> ContextualLine {
        switch destination {
        case .clipboard:
            let count = Int(metric) ?? 0
            let unit = count == 1 ? "item saved" : "items saved"
            return ContextualLine(value: metric, unit: unit)
        case .downloads:
            return ContextualLine(value: metric, unit: "in queue")
        default:
            return ContextualLine(value: metric, unit: "")
        }
    }
}
