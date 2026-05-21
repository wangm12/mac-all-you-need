import AppKit
import Core
import SwiftUI

struct AppMenuBarContent: View {
    let controller: AppController
    @State private var tab: Tab = .clipboard

    enum Tab: String, CaseIterable, Hashable, SegmentedTabDestination {
        case clipboard = "Clipboard"
        case voice = "Voice"
        case downloads = "Downloads"
        case snippets = "Snippets"

        var title: String { rawValue }

        var symbol: String {
            switch self {
            case .clipboard: "doc.on.clipboard"
            case .voice: "waveform"
            case .downloads: "arrow.down.circle"
            case .snippets: "text.quote"
            }
        }

        var symbolName: String { symbol }
    }

    var body: some View {
        let footerModel = CommandCenterFooterPresentation.model(for: tab)

        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Command Center")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Mac All You Need")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    controller.showMainWindow(destination: .settings)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            CommandCenterTabBar(selection: $tab)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)

            Divider().overlay(Color.primary.opacity(0.12))

            Group {
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
                case .snippets:
                    SnippetsListView(model: controller.clipboardDeps.dockModel)
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
    }

    private func openSelectedTabInMainWindow() {
        switch tab {
        case .clipboard:
            AppGroupSettings.defaults.set(ClipboardFunctionTab.history.rawValue, forKey: ClipboardFunctionTab.storageKey)
            controller.showMainWindow(destination: .clipboard)
        case .voice:
            AppGroupSettings.defaults.set(VoiceFunctionTab.dictate.rawValue, forKey: VoiceFunctionTab.storageKey)
            controller.showMainWindow(destination: .voice)
        case .downloads:
            AppGroupSettings.defaults.set(DownloadsFunctionTab.queue.rawValue, forKey: DownloadsFunctionTab.storageKey)
            controller.showMainWindow(destination: .downloads)
        case .snippets:
            AppGroupSettings.defaults.set(SnippetsFunctionTab.library.rawValue, forKey: SnippetsFunctionTab.storageKey)
            controller.showMainWindow(destination: .snippets)
        }
    }
}
