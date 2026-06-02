import SwiftUI

/// Shared persist + binding helpers for Dock settings tabs.
struct DockSettingsHubBindings {
    @Binding var hub: DockHubSettings
    var onSettingsChanged: (() -> Void)?
    var willPersist: (() -> Void)?

    func persist() {
        DockHubSettingsStore.save(hub)
        willPersist?()
        onSettingsChanged?()
    }

    func bool(_ keyPath: WritableKeyPath<DockHubSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { hub[keyPath: keyPath] },
            set: { hub[keyPath: keyPath] = $0; persist() }
        )
    }

    func value<T>(_ keyPath: WritableKeyPath<DockHubSettings, T>) -> Binding<T> {
        Binding(
            get: { hub[keyPath: keyPath] },
            set: { hub[keyPath: keyPath] = $0; persist() }
        )
    }

    func int(_ keyPath: WritableKeyPath<DockHubSettings, Int>) -> Binding<Int> {
        Binding(
            get: { hub[keyPath: keyPath] },
            set: { hub[keyPath: keyPath] = $0; persist() }
        )
    }

    func roundedInt(from keyPath: WritableKeyPath<DockHubSettings, Double>) -> Binding<Int> {
        Binding(
            get: { Int(hub[keyPath: keyPath].rounded()) },
            set: { hub[keyPath: keyPath] = Double($0); persist() }
        )
    }

    func percentInt(from keyPath: WritableKeyPath<DockHubSettings, Double>) -> Binding<Int> {
        Binding(
            get: { Int((hub[keyPath: keyPath] * 100).rounded()) },
            set: { hub[keyPath: keyPath] = Double($0) / 100.0; persist() }
        )
    }

    @ViewBuilder
    func toggleRow(
        _ title: String,
        _ subtitle: String,
        _ keyPath: WritableKeyPath<DockHubSettings, Bool>
    ) -> some View {
        MAYNSettingsRow(title: title, subtitle: subtitle) {
            Toggle("", isOn: bool(keyPath)).labelsHidden()
        }
    }
}

extension DockSettingsHubBindings {
    static func persist(
        _ hub: DockHubSettings,
        onSettingsChanged: (() -> Void)?,
        willPersist: (() -> Void)? = nil
    ) {
        DockHubSettingsStore.save(hub)
        willPersist?()
        onSettingsChanged?()
    }
}
