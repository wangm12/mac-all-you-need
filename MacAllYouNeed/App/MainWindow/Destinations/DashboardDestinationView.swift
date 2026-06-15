import AppKit
import Core
import FeatureCore
import SwiftUI

struct DashboardDestinationView: View {
    let controller: AppController
    let openDestination: (MainAppDestination) -> Void
    private var statePublisher: FeatureStatePublisher
    @State private var pendingFeatureIDs: Set<FeatureID> = []

    init(controller: AppController, openDestination: @escaping (MainAppDestination) -> Void) {
        self.controller = controller
        self.openDestination = openDestination
        self.statePublisher = controller.featureStatePublisher
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                dashboardHeader
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
                        voiceStatus: voiceStatus
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
            voiceSettings: VoiceActivationSettingsStore.load()
        )
    }

    private func openTile(_ tile: DashboardToolTileItem) {
        if !isTileEnabled(tile) { return }
        let route = DashboardToolOpenNavigation.route(for: tile.destination)
        if let tabStorageKey = route.tabStorageKey, let tabRawValue = route.tabRawValue {
            AppGroupSettings.defaults.set(tabRawValue, forKey: tabStorageKey)
        }
        openDestination(route.destination)
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
        guard let featureID = tile.featureID else { return nil }
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

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if let metric = tile.metric {
                Text(metric)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
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
