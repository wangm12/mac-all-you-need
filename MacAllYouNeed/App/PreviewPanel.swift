import AppKit
import QuartzCore
import SwiftUI

enum PreviewPanelTransitionDirection: Equatable {
    case none
    case forward
    case backward

    static func horizontal(from oldIndex: Int, to newIndex: Int) -> PreviewPanelTransitionDirection {
        if newIndex > oldIndex { return .forward }
        if newIndex < oldIndex { return .backward }
        return .none
    }
}

struct PreviewPanelMetadata: Equatable {
    var title: String
    var subtitle: String?
    var badge: String?
    var symbol: String

    static let empty = PreviewPanelMetadata(
        title: "Preview",
        subtitle: nil,
        badge: nil,
        symbol: "eye"
    )
}

enum PreviewPanelLayout {
    static let minimumClearance: CGFloat = 14

    static func frame(
        desiredSize: NSSize,
        visibleFrame: NSRect,
        avoiding avoidedFrame: NSRect? = nil
    ) -> NSRect {
        let available = availableFrame(visibleFrame: visibleFrame, avoiding: avoidedFrame)
        let width = min(desiredSize.width, available.width)
        let height = min(desiredSize.height, available.height)
        return NSRect(
            x: available.midX - width / 2,
            y: available.midY - height / 2,
            width: width,
            height: height
        )
    }

    private static func availableFrame(
        visibleFrame: NSRect,
        avoiding avoidedFrame: NSRect?
    ) -> NSRect {
        guard let avoidedFrame,
              visibleFrame.intersectsHorizontally(with: avoidedFrame),
              avoidedFrame.maxY > visibleFrame.minY,
              avoidedFrame.minY < visibleFrame.maxY
        else {
            return visibleFrame
        }

        let bottom = min(visibleFrame.maxY, max(visibleFrame.minY, avoidedFrame.maxY + minimumClearance))
        return NSRect(
            x: visibleFrame.minX,
            y: bottom,
            width: visibleFrame.width,
            height: max(1, visibleFrame.maxY - bottom)
        )
    }
}

private extension NSRect {
    func intersectsHorizontally(with other: NSRect) -> Bool {
        min(maxX, other.maxX) > max(minX, other.minX)
    }
}

/// Floating Quick-Look-style preview panel used by both the dock (⌘⇧V) and
/// the menu bar popover. Borderless `.popUpMenu`-level NSPanel so it
/// appears on top of any active full-screen Space without stealing focus
/// from the underlying app or popover. Dismissed by Space, Esc, or click.
@MainActor
enum PreviewPanel {
    /// Payload kinds the panel knows how to render. Keep this small —
    /// previews that need bespoke chrome (color swatch, file list) should
    /// keep using the in-window QuickLookOverlay.
    enum Content: Equatable {
        case image(NSImage)
        case text(String, monospaced: Bool)
    }

    private static var window: NSPanel?
    private static var keyMonitor: Any?
    private static var localClickMonitor: Any?
    private static var globalClickMonitor: Any?

#if DEBUG
    private static var debugDismissCount = 0

    static var debugDismissCountForTesting: Int { debugDismissCount }

    static func debugResetDismissCountForTesting() {
        debugDismissCount = 0
    }
#endif

    static var isVisible: Bool { window?.isVisible ?? false }

    static func show(
        _ content: Content,
        metadata: PreviewPanelMetadata = .empty,
        direction: PreviewPanelTransitionDirection = .none,
        avoiding avoidedFrame: NSRect? = nil
    ) {
        let panel: NSPanel = window ?? makePanel()
        window = panel

        let screen = NSScreen.screens.first(where: {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        let maxSize = NSSize(width: visible.width * 0.72, height: visible.height * 0.72)

        let fitted = sizeForContent(content, in: maxSize)
        let frame = PreviewPanelLayout.frame(
            desiredSize: fitted,
            visibleFrame: visible,
            avoiding: avoidedFrame
        )

        let hosting = NSHostingView(rootView: PreviewBody(content: content, metadata: metadata))
        hosting.frame = NSRect(origin: .zero, size: frame.size)
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        panel.contentView = hosting

        panel.setFrame(frame, display: true)

        if panel.isVisible {
            animateContentSwap(hosting, direction: direction)
        } else {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            animateContentSwap(hosting, direction: .none)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = MAYNMotionBridge.effectiveDuration(.toastIn)
                panel.animator().alphaValue = 1
            }
        }

        installKeyMonitor()
        installClickMonitors()
    }

    static func dismiss() {
#if DEBUG
        debugDismissCount += 1
#endif
        guard let panel = window, panel.isVisible else { return }
        removeMonitors()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = MAYNMotionBridge.effectiveDuration(.toastOut)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    private static func makePanel() -> NSPanel {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isMovableByWindowBackground = true
        return p
    }

    private static func sizeForContent(_ content: Content, in maxSize: NSSize) -> NSSize {
        switch content {
        case let .image(image):
            let src = image.size
            guard src.width > 0, src.height > 0 else { return maxSize }
            let scale = min(maxSize.width / src.width, maxSize.height / src.height, 1)
            return NSSize(
                width: max(300, min(maxSize.width, src.width * scale + 2)),
                height: max(240, min(maxSize.height, src.height * scale + 54))
            )
        case .text:
            // Text previews use a fixed comfortable reading width capped by
            // the screen — same width regardless of content length so
            // navigation across cards doesn't make the panel jump in size.
            let width = min(maxSize.width, 760)
            let height = min(maxSize.height, 540)
            return NSSize(width: width, height: height)
        }
    }

    private static func installKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { event in
            if event.type == .keyDown {
                let chars = event.charactersIgnoringModifiers ?? ""
                if chars == " " || event.keyCode == 53 /* esc */ {
                    dismiss()
                    return nil
                }
            }
            if event.type == .leftMouseDown { dismiss() }
            return event
        }
    }

    private static func installClickMonitors() {
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { event in
            dismiss()
            return event
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            Task { @MainActor in dismiss() }
        }
    }

    private static func removeMonitors() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
    }

    private static func animateContentSwap(
        _ view: NSView,
        direction: PreviewPanelTransitionDirection
    ) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let layer = view.layer
        else { return }

        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [0.985, 1.0]
        scale.keyTimes = [0, 1]
        scale.duration = MAYNMotionDuration.tab
        scale.timingFunctions = [MAYNMotionBridge.timingFunction(.tab)]

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.72
        fade.toValue = 1
        fade.duration = MAYNMotionDuration.hover
        fade.timingFunction = MAYNMotionBridge.timingFunction(.hover)

        layer.add(scale, forKey: "previewSwapScale")
        layer.add(fade, forKey: "previewSwapOpacity")

        guard direction != .none else { return }
        let offset: CGFloat = direction == .forward ? 18 : -18
        let slide = CABasicAnimation(keyPath: "transform.translation.x")
        slide.fromValue = offset
        slide.toValue = 0
        slide.duration = MAYNMotionDuration.tab
        slide.timingFunction = MAYNMotionBridge.timingFunction(.tab)
        layer.add(slide, forKey: "previewSwapSlide")
    }
}

private struct PreviewBody: View {
    let content: PreviewPanel.Content
    let metadata: PreviewPanelMetadata

    var body: some View {
        VStack(spacing: 0) {
            previewContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().overlay(Color.primary.opacity(0.10))

            HStack(spacing: 10) {
                Image(systemName: metadata.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.07), in: Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(metadata.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let subtitle = metadata.subtitle {
                        Text(subtitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 12)
                if let badge = metadata.badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.07), in: Capsule())
                }
                Text("← →")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(MAYNTheme.panel)
        }
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.18), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var previewContent: some View {
        switch content {
        case let .image(image):
            ZStack {
                Color.black.opacity(0.90)
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(1)
            }
        case let .text(string, monospaced):
            ScrollView {
                Text(string)
                    .font(.system(size: 15, weight: .regular, design: monospaced ? .monospaced : .default))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 20)
            }
            .background(MAYNTheme.window)
        }
    }

    private var backgroundColor: Color {
        Color(nsColor: .controlBackgroundColor)
    }
}
