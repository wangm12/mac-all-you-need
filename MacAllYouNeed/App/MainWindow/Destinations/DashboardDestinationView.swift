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

    init(controller: AppController, openDestination: @escaping (MainAppDestination) -> Void) {
        self.controller = controller
        self.openDestination = openDestination
        self.statePublisher = controller.featureStatePublisher
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                dashboardHeader
                summaryRail
                setupPrompt
                quickStartStrip
                toolGrid
            }
            .frame(maxWidth: 1040, alignment: .leading)
            .padding(.horizontal, 36)
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
                    .font(.system(size: 26, weight: .semibold))
                    .lineLimit(1)
                Text("Local tools, shortcuts, and current activity.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var summaryRail: some View {
        HStack(alignment: .top, spacing: 12) {
            summaryCard(
                title: "Setup",
                value: nextPendingFeatureTitle(for: nextPendingFeatureID),
                detail: nextPendingFeatureID == nil ? "All feature onboarding complete." : "Continue the next unfinished setup step."
            )

            summaryCard(
                title: "Active tools",
                value: "\(enabledFeatureCount)",
                detail: "Features enabled in this install."
            )

            summaryCard(
                title: "Downloads",
                value: "\(DashboardDownloadSummaryPresentation.activeQueueCount(in: controller.downloaderVM.rows))",
                detail: "Queued or running downloads."
            )
        }
    }

    private func summaryCard(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.headline.weight(.semibold))
                .lineLimit(1)

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(MAYNTheme.panel, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var setupPrompt: some View {
        if let pendingFeatureID = nextPendingFeatureID,
           let pendingTitle = pendingFeatureTitle(for: pendingFeatureID) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        StatusPill(text: "Setup remaining", kind: .warning)
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

    private var quickStartStrip: some View {
        HStack(alignment: .top, spacing: 14) {
            quickStartItem(
                symbol: "1.circle.fill",
                title: "Pick one tool",
                body: "Start with Clipboard, then move to Voice or Downloads. The shortcut chip is the fastest entry point."
            ) { openDestination(.clipboard) }

            quickStartItem(
                symbol: "2.circle.fill",
                title: "Grant permissions",
                body: "When a tool needs Accessibility, Screen Recording, or Reminders, finish setup from its permissions page."
            ) { openPermissions() }

            quickStartItem(
                symbol: "3.circle.fill",
                title: "Use the default path",
                body: "If you are unsure, keep the recommended settings. They are tuned for the fastest first successful run."
            ) { openDestination(.downloads) }
        }
        .padding(14)
        .background(MAYNTheme.panel, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
        )
    }

    private func quickStartItem(
        symbol: String,
        title: String,
        body: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MAYNTheme.progress)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                    Text(body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
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

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if let metric = tile.metric {
                Text(metric)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
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
}
