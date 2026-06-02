import SwiftUI

/// Title-only list when over compact threshold (DockDoor `WindowPreviewCompact` parity).
struct DockPreviewCompactList: View {
    let state: DockPreviewStateCoordinator
    let onSelect: (DockPreviewWindowEntry) -> Void
    var onHoverIndex: ((Int?) -> Void)?

    @State private var compactSettings: DockAppearanceSettingsFull = DockHubSettingsStore.load().appearance

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if state.appearance.showAppHeader {
                HStack(spacing: 6) {
                    if let icon = state.appIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: iconSize, height: iconSize)
                    }
                    Text(state.appName)
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.bottom, 4)
            }
            ForEach(listEntries) { item in
                compactRow(for: item.entry, index: item.index)
            }
        }
        .frame(maxWidth: CGFloat(state.settings.previewCardWidth) + 40)
        .onAppear { compactSettings = DockHubSettingsStore.load().appearance }
    }

    @ViewBuilder
    private func compactRow(for entry: DockPreviewWindowEntry, index: Int) -> some View {
        Button {
            onSelect(entry)
        } label: {
            HStack(spacing: 8) {
                rowIcon(for: entry)
                rowTitle(for: entry)
                Spacer()
                if !compactSettings.compactModeHideTrafficLights, state.appearance.showTrafficLights {
                    compactTrafficLights(for: entry)
                }
            }
            .padding(.vertical, rowVerticalPadding)
            .padding(.horizontal, 10)
            .frame(minHeight: rowMinHeight)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onContinuousHover { phase in
            guard let onHoverIndex, state.isWindowSwitcherActive else { return }
            switch phase {
            case .active:
                onHoverIndex(index)
            case .ended:
                onHoverIndex(nil)
            }
        }
    }

    @ViewBuilder
    private func rowIcon(for entry: DockPreviewWindowEntry) -> some View {
        if let stateLabel = stateIndicator(for: entry) {
            HStack(spacing: 4) {
                Image(systemName: "eye.slash")
                    .foregroundStyle(.secondary)
                Text(stateLabel)
                    .font(.system(size: 11, weight: .medium))
                    .italic()
                    .foregroundStyle(.secondary)
            }
        } else {
            Image(systemName: entry.isMinimized ? "minus.square" : "macwindow")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func rowTitle(for entry: DockPreviewWindowEntry) -> some View {
        let title = entry.title.isEmpty ? "Window" : entry.title
        let appName = state.appName

        switch compactSettings.compactModeTitleFormat {
        case .appNameAndTitle:
            VStack(alignment: .leading, spacing: 1) {
                Text(appName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(title)
                    .lineLimit(1)
            }
        case .titleOnly:
            Text(title).lineLimit(1)
        case .appNameOnly:
            Text(appName).lineLimit(1)
        }
    }

    @ViewBuilder
    private func compactTrafficLights(for entry: DockPreviewWindowEntry) -> some View {
        HStack(spacing: 6) {
            if state.appearance.enabledTrafficLightButtons.contains(.close) {
                trafficLightButton(color: .red, icon: "xmark") {
                    DockPreviewWindowActions.close(entry: entry)
                }
            }
            if state.appearance.enabledTrafficLightButtons.contains(.minimize) {
                trafficLightButton(color: .yellow, icon: "minus") {
                    DockPreviewWindowActions.minimize(entry: entry)
                }
            }
            if state.appearance.enabledTrafficLightButtons.contains(.toggleFullScreen) {
                trafficLightButton(color: .green, icon: "arrow.up.left.and.arrow.down.right") {
                    DockPreviewWindowActions.toggleFullScreen(entry: entry)
                }
            }
        }
    }

    private func trafficLightButton(color: Color, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 14, height: 14)
                .background(
                    Circle().fill(state.appearance.useMonochromeTrafficLights ? Color.secondary.opacity(0.5) : color)
                )
        }
        .buttonStyle(.plain)
    }

    private func stateIndicator(for entry: DockPreviewWindowEntry) -> String? {
        guard state.appearance.showMinimizedHiddenLabels else { return nil }
        if entry.isMinimized { return "Minimized" }
        if entry.isHidden { return "Hidden" }
        return nil
    }

    private var listEntries: [CompactRow] {
        state.filteredWindowIndices().map { index in
            CompactRow(index: index, entry: state.windows[index])
        }
    }

    private var iconSize: CGFloat {
        switch compactSettings.compactModeItemSize {
        case .xSmall: 14
        case .small: 16
        case .medium: 20
        case .large: 24
        case .xLarge: 28
        case .xxLarge: 32
        case .xxxLarge: 40
        }
    }

    private var rowMinHeight: CGFloat {
        switch compactSettings.compactModeItemSize {
        case .xSmall: 24
        case .small: 28
        case .medium: 32
        case .large: 36
        case .xLarge: 40
        case .xxLarge: 46
        case .xxxLarge: 52
        }
    }

    private var rowVerticalPadding: CGFloat {
        switch compactSettings.compactModeItemSize {
        case .xSmall, .small: 4
        case .medium: 6
        case .large, .xLarge: 8
        case .xxLarge, .xxxLarge: 10
        }
    }

    private struct CompactRow: Identifiable {
        let index: Int
        let entry: DockPreviewWindowEntry
        var id: CGWindowID { entry.id }
    }
}
