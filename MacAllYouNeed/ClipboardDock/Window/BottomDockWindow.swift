import AppKit

final class BottomDockWindow: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = false
        isFloatingPanel = true
        // Sit above the system Dock, but below macOS's native drag-preview
        // window. `.screenSaver` covers the Dock too, but it also covers
        // native drag previews, making card drags appear behind this panel.
        level = .popUpMenu
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
