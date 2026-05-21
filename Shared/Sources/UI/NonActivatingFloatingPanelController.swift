import AppKit
import SwiftUI

/// A generic controller that owns a non-activating floating NSPanel
/// wrapping a SwiftUI content view with optional fade animation.
@MainActor
public final class NonActivatingFloatingPanelController<Content: View> {

    // MARK: - Configuration

    private let styleMask: NSWindow.StyleMask
    private let level: NSWindow.Level
    private let collectionBehavior: NSWindow.CollectionBehavior
    private let hasShadow: Bool
    private let backgroundColor: NSColor
    private let showAnimationDuration: TimeInterval
    private let hideAnimationDuration: TimeInterval
    private let positioner: ((NSPanel, CGSize) -> Void)?

    // MARK: - State

    private var panel: NSPanel?
    private var hostingView: NSHostingView<Content>?

    // MARK: - Public API

    public init(
        styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel],
        level: NSWindow.Level = .floating,
        collectionBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary],
        hasShadow: Bool = true,
        backgroundColor: NSColor = .clear,
        showAnimationDuration: TimeInterval = 0.18,
        hideAnimationDuration: TimeInterval = 0.18,
        positioner: ((NSPanel, CGSize) -> Void)? = nil
    ) {
        self.styleMask = styleMask
        self.level = level
        self.collectionBehavior = collectionBehavior
        self.hasShadow = hasShadow
        self.backgroundColor = backgroundColor
        self.showAnimationDuration = showAnimationDuration
        self.hideAnimationDuration = hideAnimationDuration
        self.positioner = positioner
    }

    public var currentPanel: NSPanel? { panel }

    public var isPresented: Bool { panel?.isVisible == true }

    /// Presents the panel with the given root view at the given size.
    /// If the panel doesn't exist yet it is created; otherwise the existing
    /// panel is reused and its hosting view updated.
    public func present(rootView: Content, size: CGSize, animated: Bool = true) {
        if let existingPanel = panel {
            // Reuse existing panel — update content and position, no re-animation.
            hostingView?.rootView = rootView
            existingPanel.setContentSize(size)
            positioner?(existingPanel, size)
            return
        }

        // Create new panel.
        let newPanel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        newPanel.level = level
        newPanel.collectionBehavior = collectionBehavior
        newPanel.hasShadow = hasShadow
        newPanel.backgroundColor = backgroundColor
        newPanel.isFloatingPanel = true
        newPanel.worksWhenModal = true
        newPanel.isReleasedWhenClosed = false

        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = NSRect(origin: .zero, size: size)
        newPanel.contentView = hosting
        self.hostingView = hosting
        self.panel = newPanel

        if animated {
            newPanel.alphaValue = 0
        }

        positioner?(newPanel, size)
        newPanel.orderFrontRegardless()

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = showAnimationDuration
                newPanel.animator().alphaValue = 1
            }
        }
    }

    /// Updates the root view in-place without changing position or size.
    public func update(rootView: Content) {
        hostingView?.rootView = rootView
    }

    /// Updates the panel size, preserving position policy via the positioner.
    public func updateSize(_ size: CGSize) {
        guard let panel else { return }
        panel.setContentSize(size)
        positioner?(panel, size)
    }

    /// Dismisses the panel, optionally with a fade animation.
    public func dismiss(animated: Bool = true) {
        guard let panel else { return }

        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = hideAnimationDuration
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                panel.orderOut(nil)
                self?.tearDown()
            })
        } else {
            panel.orderOut(nil)
            tearDown()
        }
    }

    // MARK: - Private

    private func tearDown() {
        panel = nil
        hostingView = nil
    }
}
