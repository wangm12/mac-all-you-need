import Core
import SwiftUI

struct SettingsRoot: View {
    let controller: AppController

    var body: some View {
        SettingsContainer(
            controller: controller,
            style: .standalone,
            groups: SettingsSidebarGroup.systemOnly,
            fallback: .general
        )
    }
}

struct EmbeddedSettingsView: View {
    let controller: AppController

    var body: some View {
        SettingsContainer(
            controller: controller,
            style: .embedded,
            groups: SettingsSidebarGroup.systemOnly,
            fallback: .general
        )
    }
}

private enum SettingsContainerStyle {
    case standalone
    case embedded
}

private struct SettingsContainer: View {
    let controller: AppController
    let style: SettingsContainerStyle
    let groups: [SettingsSidebarGroup]
    let fallback: SettingsDestination
    @State private var shortcuts = ShortcutRegistry.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("settings.selectedTab", store: AppGroupSettings.defaults)
    private var selectedRaw = SettingsDestination.clipboard.rawValue
    @State private var selected: SettingsDestination = .clipboard

    var body: some View {
        Group {
            switch style {
            case .standalone:
                standaloneBody
            case .embedded:
                embeddedBody
            }
        }
        .onAppear {
            selected = availableSelection(for: selectedRaw)
            selectedRaw = selected.rawValue
        }
        .onChange(of: selectedRaw) { _, raw in
            let destination = availableSelection(for: raw)
            if selected != destination {
                selected = destination
            }
        }
        .onChange(of: selected) { _, destination in
            selectedRaw = destination.rawValue
        }
    }

    private var standaloneBody: some View {
        MAYNSettingsShell {
            SettingsSidebarList(selected: $selected, groups: groups)
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
        } detail: {
            SettingsDetailContent(
                controller: controller,
                shortcuts: shortcuts,
                selected: selected
            )
                .id(selected)
                .animation(MAYNMotion.panelAnimation(reduceMotion: reduceMotion), value: selected)
        }
    }

    private var embeddedBody: some View {
        VStack(spacing: 0) {
            EmbeddedSettingsHeader(
                selected: $selected,
                groups: groups,
                title: "System",
                subtitle: "Global app behavior, permissions, storage, and diagnostics."
            )

            Rectangle()
                .fill(MAYNTheme.divider)
                .frame(height: 1)

            SettingsDetailContent(
                controller: controller,
                shortcuts: shortcuts,
                selected: selected
            )
            .id(selected)
            .animation(MAYNMotion.panelAnimation(reduceMotion: reduceMotion), value: selected)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MAYNTheme.window)
    }

    private func availableSelection(for raw: String?) -> SettingsDestination {
        let destination = SettingsDestination.legacySelection(raw)
        let available = groups.flatMap(\.destinations)
        return available.contains(destination) ? destination : fallback
    }
}

private struct SettingsSidebarList: View {
    @Binding var selected: SettingsDestination
    let groups: [SettingsSidebarGroup]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.top, group.id == groups.first?.id ? 4 : 0)

                        ForEach(group.destinations) { destination in
                            SettingsSidebarButton(
                                destination: destination,
                                isSelected: selected == destination
                            ) {
                                selected = destination
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(MAYNTheme.panel)
    }
}

private struct SettingsSidebarButton: View {
    let destination: SettingsDestination
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(destination.title, systemImage: destination.symbolName)
                .font(.callout)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(rowBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var rowBackground: Color {
        if isSelected { return Color.primary.opacity(0.14) }
        if isHovering { return MAYNTheme.hover }
        return .clear
    }
}

private struct EmbeddedSettingsHeader: View {
    @Binding var selected: SettingsDestination
    let groups: [SettingsSidebarGroup]
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            FunctionSegmentedTabStrip(
                tabs: groups.flatMap(\.destinations),
                selection: selected
            ) { destination in
                selected = destination
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .background(MAYNTheme.window)
    }
}

private struct SettingsDetailContent: View {
    let controller: AppController
    let shortcuts: ShortcutRegistry
    let selected: SettingsDestination

    var body: some View {
        detailView
    }

    @ViewBuilder
    private var detailView: some View {
        switch selected {
        case .clipboard:
            ClipboardSettingsView(controller: controller)
        case .voice:
            VoiceSettingsView(controller: controller)
        case .downloads:
            DownloadsSettingsView(controller: controller)
        case .folderPreview:
            FolderPreviewSettingsView(controller: controller)
        case .snippets:
            ShortcutsSettingsView(registry: shortcuts)
        case .hotkeys:
            HotkeysSettingsView(controller: controller)
        case .search:
            SearchSettingsView()
        case .permissions:
            PermissionsSettingsView()
        case .storage:
            StorageSettingsView()
        case .general:
            GeneralSettingsView(controller: controller)
        case .advanced:
            AdvancedSettingsView(controller: controller)
        }
    }
}
