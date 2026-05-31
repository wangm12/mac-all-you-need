import AppKit
import Core
import QuartzCore
import QuickLookUI
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

final class ClipboardQuickLookPreviewItem: NSObject, QLPreviewItem {
    let previewItemURL: URL!
    let previewItemTitle: String!

    init(url: URL, title: String) {
        previewItemURL = url
        previewItemTitle = title
        super.init()
    }
}

struct ClipboardQuickLookPayload {
    let items: [ClipboardQuickLookPreviewItem]
    let temporaryURLs: [URL]
}

enum ClipboardSystemQuickLookMaterializationError: Error {
    case missingBlobStore
    case noPreviewableItems
}

enum ClipboardSystemQuickLookLayering {
    static let panelLevel = NSWindow.Level.screenSaver
    static let collectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .fullScreenAuxiliary,
        .stationary
    ]

    static func apply(to panel: QLPreviewPanel) {
        panel.level = panelLevel
        panel.collectionBehavior.formUnion(collectionBehavior)
        panel.hidesOnDeactivate = false
    }
}

enum ClipboardSystemQuickLookMaterializer {
    static func materialize(
        record: ClipboardRecord,
        title: String,
        blobs: BlobStore?,
        temporaryDirectory: URL
    ) throws -> ClipboardQuickLookPayload {
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        switch record {
        case let .files(urls):
            guard !urls.isEmpty else { throw ClipboardSystemQuickLookMaterializationError.noPreviewableItems }
            let fallbackTitle = displayTitle(title, fallback: "Files")
            let items = urls.enumerated().map { index, url in
                let itemTitle: String
                if urls.count == 1 {
                    itemTitle = displayTitle(title, fallback: url.lastPathComponent)
                } else {
                    itemTitle = url.lastPathComponent.isEmpty ? "\(fallbackTitle) \(index + 1)" : url.lastPathComponent
                }
                return ClipboardQuickLookPreviewItem(url: url, title: itemTitle)
            }
            return ClipboardQuickLookPayload(items: items, temporaryURLs: [])

        case let .text(text):
            let url = try writeTemporaryFile(
                data: Data(text.utf8),
                title: title,
                fallbackTitle: "Copied Text",
                pathExtension: "txt",
                temporaryDirectory: temporaryDirectory
            )
            return ClipboardQuickLookPayload(
                items: [ClipboardQuickLookPreviewItem(url: url, title: displayTitle(title, fallback: "Copied Text"))],
                temporaryURLs: [url]
            )

        case let .html(html):
            let url = try writeTemporaryFile(
                data: Data(html.utf8),
                title: title,
                fallbackTitle: "Copied HTML",
                pathExtension: "html",
                temporaryDirectory: temporaryDirectory
            )
            return ClipboardQuickLookPayload(
                items: [ClipboardQuickLookPreviewItem(url: url, title: displayTitle(title, fallback: "Copied HTML"))],
                temporaryURLs: [url]
            )

        case let .rtf(data):
            let url = try writeTemporaryFile(
                data: data,
                title: title,
                fallbackTitle: "Copied Rich Text",
                pathExtension: "rtf",
                temporaryDirectory: temporaryDirectory
            )
            return ClipboardQuickLookPayload(
                items: [ClipboardQuickLookPreviewItem(url: url, title: displayTitle(title, fallback: "Copied Rich Text"))],
                temporaryURLs: [url]
            )

        case let .image(blobID, _, _):
            guard let blobs else { throw ClipboardSystemQuickLookMaterializationError.missingBlobStore }
            let raw = try blobs.read(id: blobID)
            let image = quickLookImageData(from: raw)
            let url = try writeTemporaryFile(
                data: image.data,
                title: title,
                fallbackTitle: "Copied Image",
                pathExtension: image.pathExtension,
                temporaryDirectory: temporaryDirectory
            )
            return ClipboardQuickLookPayload(
                items: [ClipboardQuickLookPreviewItem(url: url, title: displayTitle(title, fallback: "Copied Image"))],
                temporaryURLs: [url]
            )
        }
    }

    private static func writeTemporaryFile(
        data: Data,
        title: String,
        fallbackTitle: String,
        pathExtension: String,
        temporaryDirectory: URL
    ) throws -> URL {
        let fileName = "\(safeFilenameBase(title, fallback: fallbackTitle))-\(UUID().uuidString).\(pathExtension)"
        let url = temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func displayTitle(_ title: String, fallback: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func safeFilenameBase(_ title: String, fallback: String) -> String {
        let base = displayTitle(title, fallback: fallback)
        let cleaned = base.replacingOccurrences(
            of: "[^A-Za-z0-9._ -]+",
            with: "-",
            options: .regularExpression
        )
        let collapsed = cleaned
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-_ "))
        return String((collapsed.isEmpty ? fallback : collapsed).prefix(48))
    }

    private static func quickLookImageData(from data: Data) -> (data: Data, pathExtension: String) {
        if hasPrefix([0x89, 0x50, 0x4E, 0x47], data: data) { return (data, "png") }
        if hasPrefix([0xFF, 0xD8, 0xFF], data: data) { return (data, "jpg") }
        if hasPrefix([0x47, 0x49, 0x46, 0x38], data: data) { return (data, "gif") }
        if hasPrefix([0x49, 0x49, 0x2A, 0x00], data: data)
            || hasPrefix([0x4D, 0x4D, 0x00, 0x2A], data: data) {
            return (data, "tiff")
        }
        if let image = NSImage(data: data),
           let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:])
        {
            return (png, "png")
        }
        return (data, "bin")
    }

    private static func hasPrefix(_ prefix: [UInt8], data: Data) -> Bool {
        data.count >= prefix.count && data.prefix(prefix.count).elementsEqual(prefix)
    }
}

@MainActor
final class ClipboardSystemQuickLookCoordinator {
    static let shared = ClipboardSystemQuickLookCoordinator()

    private let source = ClipboardSystemQuickLookPanelSource()
    private var temporaryURLs: [URL] = []

    private init() {
        source.onClose = { [weak self] in
            Task { @MainActor in
                self?.cleanupTemporaryFiles()
                self?.source.items = []
            }
        }
    }

    var isVisible: Bool {
        guard QLPreviewPanel.sharedPreviewPanelExists() else { return false }
        return QLPreviewPanel.shared()?.isVisible ?? false
    }

    func show(record: ClipboardRecord, title: String, blobs: BlobStore?) {
        do {
            let payload = try ClipboardSystemQuickLookMaterializer.materialize(
                record: record,
                title: title,
                blobs: blobs,
                temporaryDirectory: temporaryDirectory()
            )
            show(payload: payload, index: 0)
        } catch {
            dismiss()
        }
    }

    func show(payload: ClipboardQuickLookPayload, index: Int = 0) {
        guard !payload.items.isEmpty else { return }
        guard let panel = QLPreviewPanel.shared() else {
            removeTemporaryFiles(payload.temporaryURLs)
            return
        }

        let oldTemporaryURLs = temporaryURLs
        temporaryURLs = payload.temporaryURLs
        source.items = payload.items

        panel.dataSource = source
        panel.delegate = source
        ClipboardSystemQuickLookLayering.apply(to: panel)
        panel.reloadData()
        panel.currentPreviewItemIndex = max(0, min(index, payload.items.count - 1))
        panel.refreshCurrentPreviewItem()
        panel.orderFrontRegardless()
        ClipboardSystemQuickLookLayering.apply(to: panel)
        DispatchQueue.main.async {
            ClipboardSystemQuickLookLayering.apply(to: panel)
            panel.orderFrontRegardless()
        }
        removeTemporaryFiles(oldTemporaryURLs)
    }

    func dismiss() {
        if QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared() {
            panel.orderOut(nil)
            panel.dataSource = nil
            panel.delegate = nil
        }
        source.items = []
        cleanupTemporaryFiles()
    }

    private func cleanupTemporaryFiles() {
        removeTemporaryFiles(temporaryURLs)
        temporaryURLs = []
    }

    private func removeTemporaryFiles(_ urls: [URL]) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MacAllYouNeed-ClipboardQuickLook", isDirectory: true)
    }
}

private final class ClipboardSystemQuickLookPanelSource: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    var items: [ClipboardQuickLookPreviewItem] = []
    var onClose: (() -> Void)?

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        items.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard items.indices.contains(index) else { return nil }
        return items[index]
    }

    func previewPanelWillClose(_ panel: QLPreviewPanel!) {
        onClose?()
    }
}

/// Legacy floating preview panel. Clipboard previews use
/// `ClipboardSystemQuickLookCoordinator`; this remains for focused app-owned
/// previews such as voice transcripts.
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
