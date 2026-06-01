import AppKit
import SwiftUI

/// Frame-aware dismissal tracking (DockDoor `MouseTrackingNSView` subset).
@MainActor
final class DockPreviewDismissalTracker: NSView {
    var onMouseEnteredPanel: (() -> Void)?
    var onMouseExitedPanel: (() -> Void)?
    var onDismissRequest: (() -> Void)?
    var shouldKeepOpen: (() -> Bool)?
    var shouldSkipFadeOut: (() -> Bool)?
    var onDismissWithPreservePendingShow: (() -> Void)?
    var anchorRect: CGRect = .zero
    var dockItemToken: UInt?
    var activeDockItemToken: (() -> UInt?)?

    private var inactivityTimer: Timer?
    private var fadeOutTimer: Timer?
    private let fadeOutDuration: TimeInterval
    private let inactivityInterval: TimeInterval

    init(
        fadeOutDuration: TimeInterval,
        inactivityInterval: TimeInterval,
        frame frameRect: NSRect = .zero
    ) {
        self.fadeOutDuration = fadeOutDuration
        self.inactivityInterval = inactivityInterval
        super.init(frame: frameRect)
        startInactivityMonitoring()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        inactivityTimer?.invalidate()
        fadeOutTimer?.invalidate()
    }

    private func startInactivityMonitoring() {
        inactivityTimer?.invalidate()
        guard inactivityInterval > 0 else { return }
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: inactivityInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluateInactivity() }
        }
    }

    private func evaluateInactivity() {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        let padded = window.frame.insetBy(
            dx: -DockPreviewHoverPadding.container,
            dy: -DockPreviewHoverPadding.container
        )
        let onPanel = padded.contains(mouse)
        let onIcon = DockHoverObserver.isHoveredTokenMatching(dockItemToken)
            || DockPreviewDockMouse.isOverDockIcon(axRect: anchorRect, padding: 15)
        if onPanel || onIcon {
            resetOpacity()
            return
        }
        if shouldKeepOpen?() == true { return }
        beginFadeOut()
    }

    private func beginFadeOut() {
        guard let window else { return }
        if shouldSkipFadeOut?() == true { return }
        if shouldPreservePendingShowForDockIconTransition() {
            onDismissWithPreservePendingShow?()
            return
        }
        guard fadeOutDuration > 0 else {
            onDismissRequest?()
            return
        }
        guard window.alphaValue > 0 else { return }
        fadeOutTimer?.invalidate()
        setWindowOpacity(to: 0, duration: fadeOutDuration)
        fadeOutTimer = Timer.scheduledTimer(withTimeInterval: fadeOutDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.performDismiss() }
        }
    }

    private func performDismiss() {
        fadeOutTimer?.invalidate()
        onDismissRequest?()
    }

    private func setWindowOpacity(to value: CGFloat, duration: TimeInterval) {
        guard let window else { return }
        if window.alphaValue == value { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            window.animator().alphaValue = value
        }
    }

    private func shouldPreservePendingShowForDockIconTransition() -> Bool {
        guard let active = dockItemToken, let hovered = activeDockItemToken?() else { return false }
        return active != hovered
    }

    func resetOpacity() {
        let settings = DockPreviewSettingsStore.load()
        guard !settings.preventPreviewReentryDuringFadeOut else { return }
        fadeOutTimer?.invalidate()
        setWindowOpacity(to: 1, duration: 0.2)
    }

    override func mouseEntered(with event: NSEvent) {
        resetOpacity()
        onMouseEnteredPanel?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExitedPanel?()
        evaluateInactivity()
    }
}

struct DockPreviewDismissalContainer<Content: View>: NSViewRepresentable {
    let dockItemToken: UInt?
    let anchorRect: CGRect
    let onMouseInPanel: (Bool) -> Void
    let onDismissRequest: () -> Void
    let onDismissPreservePendingShow: () -> Void
    let shouldKeepOpen: () -> Bool
    let shouldSkipFadeOut: () -> Bool
    let content: Content

    init(
        dockItemToken: UInt?,
        anchorRect: CGRect,
        onMouseInPanel: @escaping (Bool) -> Void,
        onDismissRequest: @escaping () -> Void,
        onDismissPreservePendingShow: @escaping () -> Void,
        shouldKeepOpen: @escaping () -> Bool,
        shouldSkipFadeOut: @escaping () -> Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.dockItemToken = dockItemToken
        self.anchorRect = anchorRect
        self.onMouseInPanel = onMouseInPanel
        self.onDismissRequest = onDismissRequest
        self.onDismissPreservePendingShow = onDismissPreservePendingShow
        self.shouldKeepOpen = shouldKeepOpen
        self.shouldSkipFadeOut = shouldSkipFadeOut
        self.content = content()
    }

    func makeNSView(context: Context) -> NSView {
        let settings = DockPreviewSettingsStore.load()
        let container = NSView(frame: .zero)
        let tracker = DockPreviewDismissalTracker(
            fadeOutDuration: settings.fadeOutDuration,
            inactivityInterval: max(0.05, settings.dismissInactivity)
        )
        tracker.anchorRect = anchorRect
        tracker.dockItemToken = dockItemToken
        tracker.activeDockItemToken = { DockHoverObserver.lastHoveredTokenProvider?() }
        tracker.onMouseEnteredPanel = { onMouseInPanel(true) }
        tracker.onMouseExitedPanel = { onMouseInPanel(false) }
        tracker.onDismissRequest = onDismissRequest
        tracker.onDismissWithPreservePendingShow = onDismissPreservePendingShow
        tracker.shouldKeepOpen = shouldKeepOpen
        tracker.shouldSkipFadeOut = shouldSkipFadeOut
        tracker.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tracker)
        NSLayoutConstraint.activate([
            tracker.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tracker.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tracker.topAnchor.constraint(equalTo: container.topAnchor),
            tracker.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        context.coordinator.tracker = tracker

        let hosting = NSHostingView(rootView: content)
        context.coordinator.hosting = hosting
        hosting.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.hosting?.rootView = content
        context.coordinator.tracker?.anchorRect = anchorRect
        context.coordinator.tracker?.dockItemToken = dockItemToken
        context.coordinator.tracker?.shouldKeepOpen = shouldKeepOpen
        context.coordinator.tracker?.onDismissRequest = onDismissRequest
        context.coordinator.tracker?.onDismissWithPreservePendingShow = onDismissPreservePendingShow
        context.coordinator.tracker?.shouldSkipFadeOut = shouldSkipFadeOut
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var tracker: DockPreviewDismissalTracker?
        var hosting: NSHostingView<Content>?
    }
}

extension DockHoverObserver {
    /// Set by coordinator at start for dismissal preserve logic.
    static var lastHoveredTokenProvider: (() -> UInt?)?
}
