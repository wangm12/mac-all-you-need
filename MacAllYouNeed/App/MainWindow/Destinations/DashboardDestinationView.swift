import AppKit
import Core
import FeatureCore
import SwiftUI

struct DashboardDestinationView: View {
    let controller: AppController
    let openDestination: (MainAppDestination) -> Void
    private var statePublisher: FeatureStatePublisher
    @State private var pendingFeatureIDs: Set<FeatureID> = []
    @State private var showingUninstallFor: FeatureDescriptor?

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
        .sheet(
            isPresented: Binding(
                get: { showingUninstallFor != nil },
                set: { isPresented in
                    if !isPresented {
                        showingUninstallFor = nil
                    }
                }
            )
        ) {
            if let descriptor = showingUninstallFor {
                UninstallConfirmationSheet(
                    descriptor: descriptor,
                    onCancel: { showingUninstallFor = nil },
                    onConfirm: { sheet in
                        showingUninstallFor = nil
                        Task { await performUninstall(descriptor: descriptor, sheetState: sheet) }
                    }
                )
            }
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
                    descriptor: descriptor(for: tile),
                    isPending: (tile.proxiesFeatureID ?? tile.featureID).map { pendingFeatureIDs.contains($0) } ?? false,
                    onOpen: { openTile(tile) },
                    onEnable: { Task { await handleAction(.enable, for: tile) } },
                    onDisable: { Task { await handleAction(.disable, for: tile) } },
                    onInstall: { Task { await handleAction(.install, for: tile) } },
                    onCancelDownload: { Task { await handleAction(.cancelDownload, for: tile) } },
                    onRetryInstall: { Task { await handleAction(.retryInstall, for: tile) } },
                    onUninstall: { Task { await handleAction(.uninstall, for: tile) } }
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
        let effectiveID = tile.proxiesFeatureID ?? tile.featureID
        if let effectiveID,
           statePublisher.state(for: effectiveID).activationState != .enabled {
            return
        }
        let route = DashboardToolOpenNavigation.route(for: tile.destination)
        if let tabStorageKey = route.tabStorageKey, let tabRawValue = route.tabRawValue {
            AppGroupSettings.defaults.set(tabRawValue, forKey: tabStorageKey)
        }
        openDestination(route.destination)
    }

    // MARK: Feature helpers

    private func descriptor(for tile: DashboardToolTileItem) -> FeatureDescriptor? {
        guard let featureID = tile.featureID else { return nil }
        return controller.runtime.registry.descriptor(for: featureID)
    }

    private func state(for tile: DashboardToolTileItem) -> FeatureRuntimeState? {
        guard let featureID = tile.featureID else { return nil }
        return statePublisher.state(for: featureID)
    }

    // MARK: Action dispatch

    private enum DashboardFeatureAction {
        case enable, disable, install, cancelDownload, retryInstall, uninstall
    }

    private func handleAction(_ action: DashboardFeatureAction, for tile: DashboardToolTileItem) async {
        guard let targetID = tile.proxiesFeatureID ?? tile.featureID else { return }
        pendingFeatureIDs.insert(targetID)
        defer { pendingFeatureIDs.remove(targetID) }

        switch action {
        case .enable:
            try? await controller.runtime.applyTransition(.enable, for: targetID)
        case .disable:
            try? await controller.runtime.applyTransition(.disable, for: targetID)
        case .install:
            try? await controller.packInstallController.install(featureID: targetID)
            await controller.featureStatePublisher.refresh()
        case .cancelDownload:
            await controller.packInstallController.cancel(featureID: targetID)
            await controller.featureStatePublisher.refresh()
        case .retryInstall:
            try? await controller.packInstallController.install(featureID: targetID)
            await controller.featureStatePublisher.refresh()
        case .uninstall:
            guard let desc = controller.runtime.registry.descriptor(for: targetID) else { return }
            showingUninstallFor = desc
        }
    }

    private func performUninstall(descriptor: FeatureDescriptor, sheetState: UninstallSheetState) async {
        do {
            try FeatureCacheManager().deleteCaches(sheetState.checkedCacheIDs, in: descriptor)
        } catch {
            NSLog("DashboardDestinationView uninstall: cache deletion failed: \(error)")
        }
        try? await controller.runtime.applyTransition(.disable, for: descriptor.id)
        if descriptor.requiresAsset {
            try? await controller.packInstallController.uninstall(featureID: descriptor.id)
        }
        await controller.featureStatePublisher.refresh()
    }

    // MARK: Voice status

    private var voiceStatus: DashboardVoiceStatusPresentation.Status? {
        DashboardVoiceStatusPresentation.footerStatus(for: controller.voiceCoordinator.state)
    }

    private func accent(for destination: MainAppDestination) -> Color {
        switch destination {
        case .clipboard:
            Color(red: 0.10, green: 0.42, blue: 0.92)
        case .voice:
            Color(red: 0.64, green: 0.22, blue: 0.88)
        case .downloads:
            Color(red: 0.02, green: 0.58, blue: 0.42)
        case .folderPreview:
            Color(red: 0.86, green: 0.46, blue: 0.12)
        case .snippets:
            Color(red: 0.82, green: 0.18, blue: 0.36)
        case .windowLayouts:
            Color(red: 0.20, green: 0.48, blue: 0.72)
        case .grabAnywhere:
            Color(red: 0.24, green: 0.46, blue: 0.36)
        case .dockPreviews:
            Color(red: 0.10, green: 0.42, blue: 0.92)
        case .finderHistory:
            Color(red: 0.86, green: 0.46, blue: 0.12)
        case .aiFileOrganizer:
            Color(red: 0.02, green: 0.58, blue: 0.42)
        case .dashboard, .settings, .voiceReminders:
            .secondary
        }
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
