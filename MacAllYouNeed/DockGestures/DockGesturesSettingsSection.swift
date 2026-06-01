import SwiftUI

struct DockGesturesSettingsSection: View {
    @State private var settings = DockGesturesSettingsStore.load()

    var body: some View {
        MAYNSection(title: "Gestures") {
            Text("Trackpad and dock-scroll gestures are not available yet. Toggles are saved for a future release.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            MAYNDivider()
            toggleRow("Dock icon scroll", \.enableDockScroll, enabled: false)
            MAYNDivider()
            toggleRow("Title bar scroll", \.enableTitleBarScroll, enabled: false)
            MAYNDivider()
            toggleRow("Preview card swipe", \.enablePreviewGestures, enabled: false)
        }
        .onAppear { settings = DockGesturesSettingsStore.load() }
    }

    private func toggleRow(
        _ title: String,
        _ keyPath: WritableKeyPath<DockGesturesSettings, Bool>,
        enabled: Bool = true
    ) -> some View {
        MAYNSettingsRow(title: title, subtitle: nil) {
            Toggle("", isOn: Binding(
                get: { settings[keyPath: keyPath] },
                set: {
                    settings[keyPath: keyPath] = $0
                    DockGesturesSettingsStore.save(settings)
                }
            ))
            .labelsHidden()
            .disabled(!enabled)
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}
