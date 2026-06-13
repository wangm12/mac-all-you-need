import AppKit
import SwiftUI

/// Detached switcher search field (DockDoor `SearchWindow`).
@MainActor
final class DockPreviewSearchWindow: NSObject {
    private var panel: NSPanel?
    private var searchField: NSTextField?
    private weak var state: DockPreviewStateCoordinator?
    private var appearance = DockPreviewAppearanceContext.dockHover()

    var isFocused: Bool {
        guard let panel, panel.isVisible else { return false }
        return panel.isKeyWindow && searchField?.currentEditor() != nil
    }

    func bind(state: DockPreviewStateCoordinator) {
        self.state = state
    }

    func updateAppearance(_ appearance: DockPreviewAppearanceContext) {
        self.appearance = appearance
        rebuildIfNeeded()
    }

    func show(relativeTo window: NSWindow) {
        ensurePanel()
        guard let panel else { return }
        guard window.isVisible else { return }

        let frame = window.frame
        guard frame.width > 0, frame.height > 0 else { return }

        let searchWidth: CGFloat = 300
        let searchHeight: CGFloat = 40
        let gap: CGFloat = -20
        guard let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let screenFrame = screen.visibleFrame

        var searchFrame: NSRect
        let spaceAbove = screenFrame.maxY - frame.maxY
        let spaceBelow = frame.minY - screenFrame.minY
        let requiredVerticalSpace = searchHeight + gap

        if spaceAbove >= requiredVerticalSpace {
            searchFrame = NSRect(
                x: frame.midX - searchWidth / 2,
                y: frame.maxY + gap,
                width: searchWidth,
                height: searchHeight
            )
        } else if spaceBelow >= requiredVerticalSpace {
            searchFrame = NSRect(
                x: frame.midX - searchWidth / 2,
                y: frame.minY - searchHeight - gap,
                width: searchWidth,
                height: searchHeight
            )
        } else {
            searchFrame = NSRect(
                x: frame.midX - searchWidth / 2,
                y: frame.maxY - searchHeight - gap,
                width: searchWidth,
                height: searchHeight
            )
        }

        searchFrame.origin.x = min(max(searchFrame.origin.x, screenFrame.minX + 10), screenFrame.maxX - searchWidth - 10)
        searchFrame.origin.y = min(max(searchFrame.origin.y, screenFrame.minY + 10), screenFrame.maxY - searchHeight - 10)

        panel.setFrame(searchFrame, display: false)
        panel.orderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
        searchField?.stringValue = ""
        state?.searchQuery = ""
    }

    func focus() {
        ensurePanel()
        panel?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            self?.searchField?.becomeFirstResponder()
        }
    }

    func updateText(_ text: String) {
        guard let searchField, searchField.stringValue != text else { return }
        searchField.stringValue = text
        if let editor = searchField.currentEditor() {
            editor.selectedRange = NSRange(location: text.count, length: 0)
        }
    }

    private func ensurePanel() {
        if panel != nil { return }
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: 14)
        field.usesSingleLineMode = true
        field.placeholderString = "Search windows…"
        field.delegate = self
        searchField = field

        let chrome = DockPreviewSearchFieldChrome(
            searchField: field,
            appearance: appearance.background
        )
        let hosting = NSHostingView(rootView: chrome)
        hosting.frame = NSRect(x: 0, y: 0, width: 300, height: 40)

        let newPanel = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.level = .statusBar
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = true
        newPanel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        newPanel.animationBehavior = .none
        newPanel.contentView = hosting
        panel = newPanel
    }

    private func rebuildIfNeeded() {
        guard let panel, let field = searchField else { return }
        let chrome = DockPreviewSearchFieldChrome(searchField: field, appearance: appearance.background)
        let hosting = NSHostingView(rootView: chrome)
        hosting.frame = panel.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 300, height: 40)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
    }
}

extension DockPreviewSearchWindow: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        state?.searchQuery = field.stringValue
        state?.clampSelectionToFilteredSearch()
        state?.shouldScrollToIndex = true
        state?.onFrameRefreshNeeded?()
    }
}
