import SwiftUI

extension DockFunctionTab {
    var previewContext: DockSettingsMockPreviewContext? {
        switch self {
        case .previews, .customize: .dock
        case .switcher: .windowSwitcher
        case .cmdTab: .cmdTab
        case .features, .locking, .permissions: nil
        }
    }

    var usesSplitPreviewLayout: Bool {
        previewContext != nil
    }
}

/// Shared hub state + split or single-column layout for Dock settings tabs.
struct DockSettingsPageBody: View {
    let tab: DockFunctionTab
    var onSettingsChanged: (() -> Void)?

    @State private var hub = DockHubSettingsStore.load()

    var body: some View {
        Group {
            if tab.usesSplitPreviewLayout, let previewContext = tab.previewContext {
                DockSettingsSplitLayout(hub: $hub, previewContext: previewContext) {
                    DockFunctionTabContent(tab: tab, hub: $hub, onSettingsChanged: persist)
                }
            } else {
                DockSettingsScrollColumn {
                    DockFunctionTabContent(tab: tab, hub: $hub, onSettingsChanged: persist)
                }
                .frame(maxWidth: 1040, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.vertical, 26)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .onAppear { hub = DockHubSettingsStore.load() }
    }

    private func persist() {
        DockSettingsHubBindings.persist(hub, onSettingsChanged: onSettingsChanged)
    }
}

/// Left preview panel (sticky) + right settings column.
private struct DockSettingsSplitLayout<Settings: View>: View {
    @Binding var hub: DockHubSettings
    let previewContext: DockSettingsMockPreviewContext
    @ViewBuilder let settings: () -> Settings

    private let previewWidth: CGFloat = 340
    private let previewColumnInset: CGFloat = 20

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack {
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    Spacer(minLength: previewColumnInset)
                    DockSettingsMockPreview(hub: $hub, context: previewContext)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: previewColumnInset)
                }
                Spacer(minLength: 0)
            }
            .frame(width: previewWidth)
            .frame(maxHeight: .infinity)

            Rectangle()
                .fill(MAYNTheme.divider)
                .frame(width: 1)
                .frame(maxHeight: .infinity)
                .padding(.vertical, 8)

            DockSettingsScrollColumn {
                settings()
            }
            .padding(.leading, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: 1040, alignment: .leading)
        .padding(.horizontal, 32)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Scrollable settings column (single-column tabs and split right pane).
struct DockSettingsScrollColumn<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
    }
}
