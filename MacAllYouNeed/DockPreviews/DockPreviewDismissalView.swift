import AppKit
import ApplicationServices
import SwiftUI

// MARK: - Tracker NSView

/// Mouse tracking + inactivity fade (DockDoor `MouseTrackingNSView`).
@MainActor
final class DockPreviewDismissalTracker: NSView {
    var onMouseEnteredPanel: (() -> Void)?
    var onMouseExitedPanel: (() -> Void)?
    var onDismissRequest: (() -> Void)?
    var onDismissWithPreservePendingShow: (() -> Void)?
    var shouldSkipFadeOut: (() -> Bool)?
    var dockItemElement: AXUIElement?

    private var inactivityTimer: Timer?
    private var fadeOutTimer: Timer?
    private var resetFadeObserver: NSObjectProtocol?
    private let fadeOutDuration: TimeInterval
    private let inactivityInterval: TimeInterval

    init(fadeOutDuration: TimeInterval, inactivityInterval: TimeInterval, frame frameRect: NSRect = .zero) {
        self.fadeOutDuration = fadeOutDuration
        self.inactivityInterval = inactivityInterval
        super.init(frame: frameRect)
        setupTrackingArea()
        startInactivityMonitoring()
        resetFadeObserver = NotificationCenter.default.addObserver(
            forName: .dockPreviewResetFadeState,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.resetOpacity() }
        }
        resetOpacityVisually()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let resetFadeObserver {
            NotificationCenter.default.removeObserver(resetFadeObserver)
        }
        inactivityTimer?.invalidate()
        fadeOutTimer?.invalidate()
    }

    private func setupTrackingArea() {
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        setupTrackingArea()
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
        let windowFrame = window.frame.insetBy(
            dx: DockPreviewHoverPadding.container,
            dy: DockPreviewHoverPadding.container
        )

        let pointerInDockRegion = DockPreviewDockPosition.isMouseInDockRegion(padding: 48)
        let overDisplayedDockIcon = isMouseOverDisplayedDockIcon()

        if windowFrame.contains(mouse) || pointerInDockRegion || overDisplayedDockIcon {
            resetOpacityVisually()
        } else if fadeOutTimer == nil, window.alphaValue == 1.0 {
            startFadeOut()
        }
    }

    private func isMouseOverDisplayedDockIcon() -> Bool {
        guard let dockItemElement else { return false }
        guard let current = DockHoverObserver.activeObserver?.getHoveredDockItemElement() else { return false }
        return CFEqual(dockItemElement, current)
    }

    func resetOpacity() {
        resetOpacityVisually()
    }

    private func resetOpacityVisually() {
        let settings = DockHubSettingsStore.loadPreviews()
        guard !settings.preventPreviewReentryDuringFadeOut else { return }
        cancelFadeOut()
        setWindowOpacity(to: 1.0, duration: 0.2)
    }

    override func mouseEntered(with event: NSEvent) {
        resetOpacityVisually()
        onMouseEnteredPanel?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExitedPanel?()
    }

    private func startFadeOut() {
        guard shouldSkipFadeOut?() != true else { return }
        guard let window else { return }
        guard window.alphaValue > 0 else { return }

        cancelFadeOut()

        if fadeOutDuration == 0 {
            performDismiss()
        } else {
            setWindowOpacity(to: 0.0, duration: fadeOutDuration)
            fadeOutTimer = Timer.scheduledTimer(withTimeInterval: fadeOutDuration, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.performDismiss() }
            }
        }
    }

    func cancelFadeOut() {
        fadeOutTimer?.invalidate()
        fadeOutTimer = nil
    }

    private func performDismiss() {
        if shouldPreservePendingShowForDockIconTransition() {
            onDismissWithPreservePendingShow?()
            return
        }
        onDismissRequest?()
    }

    private func setWindowOpacity(to value: CGFloat, duration: TimeInterval) {
        guard let window else { return }
        if window.alphaValue == value { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            window.animator().alphaValue = value
        }
    }

    private func shouldPreservePendingShowForDockIconTransition() -> Bool {
        guard let dockItemElement else { return false }
        guard let current = DockHoverObserver.activeObserver?.getHoveredDockItemElement() else { return false }
        return !CFEqual(dockItemElement, current)
    }
}

// MARK: - Lightweight NSViewRepresentable (tracker only, no nested hosting view)

/// Attaches the dismissal tracker NSView as an overlay layer (DockDoor `WindowDismissalContainer`).
struct DockPreviewTrackerBackground: NSViewRepresentable {
    let dockItemElement: AXUIElement?
    let onMouseInPanel: (Bool) -> Void
    let onDismissRequest: () -> Void
    let onDismissPreservePendingShow: () -> Void
    let shouldSkipFadeOut: () -> Bool

    func makeNSView(context: Context) -> DockPreviewDismissalTracker {
        let settings = DockHubSettingsStore.loadPreviews()
        let tracker = DockPreviewDismissalTracker(
            fadeOutDuration: settings.fadeOutDuration,
            inactivityInterval: max(0.05, settings.dismissInactivity)
        )
        tracker.dockItemElement = dockItemElement
        tracker.onMouseEnteredPanel = { onMouseInPanel(true) }
        tracker.onMouseExitedPanel = { onMouseInPanel(false) }
        tracker.onDismissRequest = onDismissRequest
        tracker.onDismissWithPreservePendingShow = onDismissPreservePendingShow
        tracker.shouldSkipFadeOut = shouldSkipFadeOut
        tracker.resetOpacity()
        return tracker
    }

    func updateNSView(_ tracker: DockPreviewDismissalTracker, context: Context) {
        tracker.onMouseEnteredPanel = { onMouseInPanel(true) }
        tracker.onMouseExitedPanel = { onMouseInPanel(false) }
        tracker.onDismissRequest = onDismissRequest
        tracker.onDismissWithPreservePendingShow = onDismissPreservePendingShow
        tracker.shouldSkipFadeOut = shouldSkipFadeOut
    }
}

// MARK: - SwiftUI container (no nested NSHostingView)

/// Renders content directly in the main SwiftUI tree so `fittingSize` propagates correctly.
struct DockPreviewDismissalContainer<Content: View>: View {
    let dockItemElement: AXUIElement?
    let onMouseInPanel: (Bool) -> Void
    let onDismissRequest: () -> Void
    let onDismissPreservePendingShow: () -> Void
    let shouldSkipFadeOut: () -> Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .overlay {
                DockPreviewTrackerBackground(
                    dockItemElement: dockItemElement,
                    onMouseInPanel: onMouseInPanel,
                    onDismissRequest: onDismissRequest,
                    onDismissPreservePendingShow: onDismissPreservePendingShow,
                    shouldSkipFadeOut: shouldSkipFadeOut
                )
                .allowsHitTesting(false)
            }
    }
}

extension DockHoverObserver {
    static var lastHoveredTokenProvider: (() -> UInt?)?
    static weak var activeObserver: DockHoverObserver?
}
