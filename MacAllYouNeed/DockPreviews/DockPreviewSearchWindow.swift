import AppKit
import SwiftUI

/// Detached switcher search field (DockDoor `SearchWindow` subset).
@MainActor
final class DockPreviewSearchWindow {
    private var panel: NSPanel?
    private weak var state: DockPreviewStateCoordinator?

    func bind(state: DockPreviewStateCoordinator) {
        self.state = state
    }

    func show(relativeTo anchor: NSWindow) {
        guard let state else { return }
        if let panel {
            panel.orderFrontRegardless()
            position(relativeTo: anchor)
            return
        }
        let field = DockPreviewDetachedSearchField(state: state)
        let hosting = NSHostingView(rootView: field)
        hosting.frame.size = CGSize(width: 280, height: 36)
        let newPanel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.frame.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.level = .popUpMenu
        newPanel.isFloatingPanel = true
        newPanel.backgroundColor = .clear
        newPanel.contentView = hosting
        panel = newPanel
        position(relativeTo: anchor)
        newPanel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func updateSearchText(_ text: String) {
        state?.searchQuery = text
    }

    private func position(relativeTo anchor: NSWindow) {
        guard let panel else { return }
        let anchorFrame = anchor.frame
        panel.setFrameOrigin(NSPoint(
            x: anchorFrame.midX - panel.frame.width / 2,
            y: anchorFrame.maxY + 8
        ))
    }
}

private struct DockPreviewDetachedSearchField: View {
    @Bindable var state: DockPreviewStateCoordinator

    var body: some View {
        DockPreviewSearchBar(query: $state.searchQuery)
            .onChange(of: state.searchQuery) { _, _ in
                state.clampSelectionToFilteredSearch()
            }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
