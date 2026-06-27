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
        becomesKeyOnlyIfNeeded = false
        ClipboardDockWindowLayering.configure(self)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func orderFront(_ sender: Any?) {
        ClipboardDockWindowLayering.orderFront(self)
    }

    override func makeKey() {
        super.makeKey()
        ClipboardDockWindowLayering.reassertLevel(self)
    }
}
