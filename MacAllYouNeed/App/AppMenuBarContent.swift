import AppKit
import Core
import FeatureCore
import SwiftUI

struct AppMenuBarContent: View {
    let controller: AppController
    @State private var tab: Tab = .clipboard
    @State private var statusSubtitle = ""
    private var statePublisher: FeatureStatePublisher

    init(controller: AppController) {
        self.controller = controller
        self.statePublisher = controller.featureStatePublisher
    }

    enum Tab: String, CaseIterable, Hashable, SegmentedTabDestination {
        case clipboard = "Clipboard"
        case voice = "Voice"
        case downloads = "Downloads"
        case reminders = "Reminders"

        var title: String { rawValue }

        var symbol: String {
            switch self {
            case .clipboard: "doc.on.clipboard"
            case .voice: "waveform"
            case .downloads: "arrow.down.circle"
            case .reminders: "checklist"
            }
        }

        var symbolName: String { symbol }
    }

    var body: some View {
        let footerModel = CommandCenterFooterPresentation.model(for: tab)

        MAYNLiquidGlassPanel(
            role: .elevated,
            cornerRadius: CommandCenterMetrics.shellRadius,
            showsBorder: true,
            showsShadow: true
        ) {
            VStack(spacing: 0) {
                CommandCenterTopChrome(
                    statusSubtitle: statusSubtitle,
                    onOpenCommandPalette: openCommandPalette,
                    onOpenSettings: {
                        controller.showMainWindow(destination: .settings)
                    }
                )

                CommandCenterTabBar(selection: $tab)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)

                Rectangle()
                    .fill(MAYNTheme.hairline)
                    .frame(height: 1)

                Group {
                    if isTabDisabled(tab) {
                        CommandCenterDisabledPlaceholder(featureName: tab.title)
                    } else {
                        tabContent
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                CommandCenterFooter(
                    model: footerModel,
                    onOpen: openSelectedTabInMainWindow,
                    onPauseCapture: { controller.suspendCaptureFor60Seconds() },
                    onQuit: { NSApp.terminate(nil) }
                )
            }
        }
        .frame(width: CommandCenterMetrics.width, height: CommandCenterMetrics.height)
        .onAppear {
            refreshStatusSubtitle()
            controller.clipboardDock.hide()
            PreviewPanel.dismiss()
            ClipboardSystemQuickLookCoordinator.shared.dismiss()
        }
        .onDisappear {
            PreviewPanel.dismiss()
            ClipboardSystemQuickLookCoordinator.shared.dismiss()
        }
        .onChange(of: tab) { _, _ in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .menuBarPopoverReanchorRequested, object: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .featureRuntimeStateChanged)) { _ in
            refreshStatusSubtitle()
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .clipboard:
            ClipboardPopoverView(
                controller: controller,
                reader: controller.clipboardReader,
                imageLoader: controller.clipboardDeps.imageLoader,
                appIcons: controller.clipboardDeps.appIcons,
                blobs: controller.clipboardDeps.blobs
            )
        case .voice:
            VoicePopoverView(controller: controller)
        case .downloads:
            DownloadsPopoverView(controller: controller)
        case .reminders:
            RemindersPopoverView(controller: controller)
        }
    }

    private func isTabDisabled(_ tab: Tab) -> Bool {
        switch tab {
        case .clipboard:
            return statePublisher.state(for: .clipboard).activationState != .enabled
        case .voice:
            return statePublisher.state(for: .voice).activationState != .enabled
        case .downloads:
            return statePublisher.state(for: .downloader).activationState != .enabled
        case .reminders:
            return statePublisher.state(for: .voiceReminders).activationState != .enabled
                || statePublisher.state(for: .voice).activationState != .enabled
        }
    }

    private func openSelectedTabInMainWindow() {
        switch tab {
        case .clipboard:
            AppGroupSettings.defaults.set(ClipboardFunctionTab.history.rawValue, forKey: ClipboardFunctionTab.storageKey)
            controller.showMainWindow(destination: .clipboard)
        case .voice:
            AppGroupSettings.defaults.set(VoiceFunctionTab.history.rawValue, forKey: VoiceFunctionTab.storageKey)
            controller.showMainWindow(destination: .voice)
        case .downloads:
            AppGroupSettings.defaults.set(DownloadsFunctionTab.downloads.rawValue, forKey: DownloadsFunctionTab.storageKey)
            controller.showMainWindow(destination: .downloads)
        case .reminders:
            controller.showMainWindow(destination: .voice)
        }
    }

    private func openCommandPalette() {
        NotificationCenter.default.post(name: .menuBarPopoverDismissRequested, object: nil)
        controller.showMainWindow(destination: .dashboard)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .commandPaletteOpenRequested, object: nil)
        }
    }

    private func refreshStatusSubtitle() {
        statusSubtitle = CommandCenterStatusPresentation.subtitle(
            registry: controller.runtime.registry,
            stateFor: { statePublisher.state(for: $0) },
            failedDownloadCount: controller.downloaderVM.rows.filter { $0.state == .failed }.count,
            orphanCacheCount: 0
        )
    }
}
