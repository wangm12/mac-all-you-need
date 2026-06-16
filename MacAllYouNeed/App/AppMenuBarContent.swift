import AppKit
import Core
import FeatureCore
import SwiftUI

struct AppMenuBarContent: View {
    let controller: AppController
    @State private var tab: Tab = .clipboard
    private var statePublisher: FeatureStatePublisher

    init(controller: AppController) {
        self.controller = controller
        self.statePublisher = controller.featureStatePublisher
    }

    enum Tab: String, CaseIterable, Hashable, SegmentedTabDestination {
        case clipboard = "Clipboard"
        case voice = "Voice"
        case downloads = "Downloads"
        case layouts = "Layouts"
        case reminders = "Reminders"

        var title: String { rawValue }

        var symbol: String {
            switch self {
            case .clipboard: "doc.on.clipboard"
            case .voice: "waveform"
            case .downloads: "arrow.down.circle"
            case .layouts: "rectangle.3.group"
            case .reminders: "checklist"
            }
        }

        var symbolName: String { symbol }
    }

    var body: some View {
        let footerModel = CommandCenterFooterPresentation.model(for: tab)

        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button {
                    controller.showMainWindow(destination: .settings)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 8)

            CommandCenterTabBar(selection: $tab)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)

            Divider().overlay(Color.primary.opacity(0.12))

            Group {
                if isTabDisabled(tab) {
                    CommandCenterDisabledPlaceholder(featureName: tab.title)
                } else {
                    tabContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack {
                if let shortcutText = footerModel.shortcutText {
                    ShortcutChip(text: shortcutText, height: HotkeyChipPresentation.compactHeight)
                }
                Text(footerModel.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                MAYNButton(footerModel.openButtonTitle, height: HotkeyChipPresentation.compactHeight) {
                    openSelectedTabInMainWindow()
                }
                if footerModel.showsCapturePause {
                    MAYNButton("Pause 60s", height: HotkeyChipPresentation.compactHeight) {
                        controller.suspendCaptureFor60Seconds()
                    }
                }
                MAYNButton("Quit", role: .destructive, height: HotkeyChipPresentation.compactHeight) {
                    NSApp.terminate(nil)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 500, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            // Opening the menu-bar popover dismisses the dock — having both
            // visible at once is messy and the user clicked the menu icon
            // explicitly, signalling they want this surface instead.
            controller.clipboardDock.hide()
            // Also dismiss any floating preview/HUD so the popover appears
            // on a clean canvas.
            PreviewPanel.dismiss()
            ClipboardSystemQuickLookCoordinator.shared.dismiss()
        }
        .onDisappear {
            PreviewPanel.dismiss()
            ClipboardSystemQuickLookCoordinator.shared.dismiss()
        }
        .onChange(of: tab) { _, _ in
            // Defer until after SwiftUI commits the new tab branch so AppKit sees
            // stable geometry before we re-anchor the popover.
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .menuBarPopoverReanchorRequested, object: nil)
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .clipboard:
            ClipboardPopoverView(
                reader: controller.clipboardReader,
                imageLoader: controller.clipboardDeps.imageLoader,
                appIcons: controller.clipboardDeps.appIcons,
                blobs: controller.clipboardDeps.blobs
            )
        case .voice:
            VoicePopoverView(controller: controller)
        case .downloads:
            DownloadsPopoverView(controller: controller)
        case .layouts:
            WindowLayoutsPopoverView(controller: controller)
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
        case .layouts:
            let layouts = statePublisher.state(for: .windowLayouts).activationState == .enabled
            let grab = statePublisher.state(for: .windowGrab).activationState == .enabled
            return !layouts && !grab
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
        case .layouts:
            AppGroupSettings.defaults.set(WindowLayoutsFunctionTab.shortcuts.rawValue, forKey: WindowLayoutsFunctionTab.storageKey)
            controller.showMainWindow(destination: .windowLayouts)
        case .reminders:
            // Reminders has no dedicated main-window destination; Voice is its
            // closest home (the reminder flow lives in the Voice pipeline).
            controller.showMainWindow(destination: .voice)
        }
    }
}
