import AppKit
import SwiftUI

/// Middle-click and Aero-shake handlers for dock preview cards.
enum DockPreviewInteractionGestures {
    static func handleMiddleClick(
        action: DockMiddleClickAction,
        entry: DockPreviewWindowEntry
    ) {
        switch action {
        case .close:
            DockPreviewWindowActions.close(entry: entry)
        case .minimize:
            DockPreviewWindowActions.minimize(entry: entry)
        case .quit:
            DockPreviewWindowActions.quitApplication(pid: entry.pid)
        case .none:
            break
        }
    }

    static func handleAeroShake(
        action: DockAeroShakeAction,
        entries: [DockPreviewWindowEntry],
        selectedIndex: Int
    ) {
        guard action != .none else { return }
        let others = entries.enumerated().filter { $0.offset != selectedIndex }.map(\.element)
        for entry in others {
            DockPreviewWindowActions.minimize(entry: entry)
        }
    }
}

/// Shake detection on preview cards.
struct DockPreviewAeroShakeModifier: ViewModifier {
    let enabled: Bool
    let action: DockAeroShakeAction
    let entries: [DockPreviewWindowEntry]
    let selectedIndex: Int

    @State private var shakeSamples: [Date] = []

    func body(content: Content) -> some View {
        content
            .onTapGesture(count: 3) {
                guard enabled, action != .none else { return }
                registerShake()
            }
    }

    private func registerShake() {
        let now = Date()
        shakeSamples.append(now)
        shakeSamples = shakeSamples.filter { now.timeIntervalSince($0) < 0.6 }
        guard shakeSamples.count >= 3 else { return }
        shakeSamples = []
        DockPreviewInteractionGestures.handleAeroShake(
            action: action,
            entries: entries,
            selectedIndex: selectedIndex
        )
    }
}

extension View {
    func dockPreviewAeroShake(
        enabled: Bool,
        action: DockAeroShakeAction,
        entries: [DockPreviewWindowEntry],
        selectedIndex: Int
    ) -> some View {
        modifier(DockPreviewAeroShakeModifier(
            enabled: enabled,
            action: action,
            entries: entries,
            selectedIndex: selectedIndex
        ))
    }
}
