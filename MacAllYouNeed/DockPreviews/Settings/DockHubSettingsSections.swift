import SwiftUI

/// Master toggles and subsystem settings for the unified Dock hub.
struct DockHubSettingsSections: View {
    var onSettingsChanged: (() -> Void)?
    @State private var hub = DockHubSettingsStore.load()

    var body: some View {
        Group {
            masterSection
            previewsAppearanceSection
            switcherSection
            cmdTabSection
            widgetsSection
            dockLockSection
            indicatorSection
        }
        .onAppear { hub = DockHubSettingsStore.load() }
    }

    private func persist() {
        hub.previews.enableFolderWidget = hub.widgets.enableFolderWidget
        hub.previews.folderShowHiddenFiles = hub.widgets.folderShowHiddenFiles
        DockHubSettingsStore.save(hub)
        onSettingsChanged?()
    }

    private var masterSection: some View {
        MAYNSection(title: "Dock hub") {
            toggleRow("Dock hover previews", binding(\.master.enableDockPreviews))
            MAYNDivider()
            toggleRow("Window switcher", binding(\.master.enableWindowSwitcher))
            MAYNDivider()
            toggleRow("Cmd+Tab enhancements", binding(\.master.enableCmdTabEnhancements))
            MAYNDivider()
            toggleRow("Dock locking", binding(\.master.enableDockLocking))
            MAYNDivider()
            toggleRow("Active app indicator", binding(\.master.enableActiveAppIndicator))
        }
    }

    private var previewsAppearanceSection: some View {
        MAYNSection(title: "Preview appearance") {
            toggleRow("Dynamic thumbnail sizing", binding(\.previews.allowDynamicImageSizing))
            MAYNDivider()
            toggleRow("Preview animations", binding(\.previews.showPreviewAnimations))
            MAYNDivider()
            toggleRow("Show window titles", binding(\.previews.showWindowTitle))
            MAYNDivider()
            toggleRow("Show app name in header", binding(\.previews.showAppNameInHeader))
            MAYNDivider()
            toggleRow("Traffic light buttons", binding(\.previews.showTrafficLightButtons))
            MAYNDivider()
            toggleRow("Enable folder widget", binding(\.previews.enableFolderWidget))
            MAYNDivider()
            toggleRow("Full-size hover preview", binding(\.previews.enableFullSizeHoverPreview))
        }
    }

    private var widgetsSection: some View {
        MAYNSection(title: "Dock widgets") {
            toggleRow("Media widget (Music)", binding(\.widgets.enableMediaWidget))
            MAYNDivider()
            toggleRow("Calendar widget", binding(\.widgets.enableCalendarWidget))
            MAYNDivider()
            toggleRow("Folder stacks", binding(\.widgets.enableFolderWidget))
        }
    }

    private var switcherSection: some View {
        MAYNSection(title: "Window switcher") {
            toggleRow("Instant switch (no panel)", binding(\.switcher.instantSwitcher))
            MAYNDivider()
            toggleRow("Current space only", binding(\.switcher.currentSpaceOnly))
            MAYNDivider()
            toggleRow("Current monitor only", binding(\.switcher.currentMonitorOnly))
            MAYNDivider()
            toggleRow("Include hidden windows", binding(\.switcher.includeHiddenWindows))
        }
    }

    private var cmdTabSection: some View {
        MAYNSection(title: "Cmd+Tab") {
            toggleRow("Auto-select first window", binding(\.cmdTab.autoSelectFirstWindow))
            MAYNDivider()
            toggleRow("Current space only", binding(\.cmdTab.currentSpaceOnly))
            MAYNDivider()
            toggleRow("Include hidden windows", binding(\.cmdTab.includeHiddenWindows))
        }
    }

    private var dockLockSection: some View {
        MAYNSection(title: "Dock lock") {
            MAYNSettingsRow(
                title: "Override modifier",
                subtitle: "Hold to temporarily allow moving to another display."
            ) {
                MAYNDropdown(
                    selection: binding(\.dockLock.overrideModifier),
                    options: DockLockOverrideModifier.allCases,
                    title: { $0.displayName }
                )
            }
        }
    }

    private var indicatorSection: some View {
        MAYNSection(title: "Active app indicator") {
            toggleRow("Auto size", binding(\.indicator.autoSize))
            MAYNDivider()
            MAYNSettingsRow(title: "Line height", subtitle: nil) {
                MAYNNumericStepper(
                    text: "Height",
                    value: Binding(
                        get: { Int(hub.indicator.height.rounded()) },
                        set: { hub.indicator.height = Double($0); persist() }
                    ),
                    range: 1 ... 12,
                    step: 1,
                    presets: [2, 3, 4],
                    suffix: "pt"
                )
            }
        }
    }

    private func toggleRow(_ title: String, _ binding: Binding<Bool>) -> some View {
        MAYNSettingsRow(title: title, subtitle: nil) {
            Toggle("", isOn: binding).labelsHidden()
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<DockHubSettings, T>) -> Binding<T> where T: Equatable {
        Binding(
            get: { hub[keyPath: keyPath] },
            set: { newValue in
                hub[keyPath: keyPath] = newValue
                persist()
            }
        )
    }
}
