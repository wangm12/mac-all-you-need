import AppKit
import Foundation

public protocol PasteboardReading {
    func currentChangeCount() -> Int
    func currentTypes() -> [String]
    func currentItems() -> [PasteboardItem]
    func frontmostBundleID() -> String?
}

public final class SystemPasteboardReader: PasteboardReading {
    private let pb = NSPasteboard.general
    public init() {}
    public func currentChangeCount() -> Int {
        pb.changeCount
    }

    public func currentTypes() -> [String] {
        (pb.types ?? []).map(\.rawValue)
    }

    public func frontmostBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    public func currentItems() -> [PasteboardItem] {
        var items: [PasteboardItem] = []

        let plainText = pb.string(forType: PasteboardUTI.plainText)
        if let s = plainText, !Self.isSynthesizedImagePlaceholder(s) { items.append(.text(s)) }
        if let d = pb.data(forType: PasteboardUTI.rtf) { items.append(.rtf(d)) }
        if let s = pb.string(forType: PasteboardUTI.html) { items.append(.html(s)) }
        if let d = pb.data(forType: PasteboardUTI.png) { items.append(.png(d)) }
        if let d = pb.data(forType: PasteboardUTI.tiff) { items.append(.tiff(d)) }

        // Fallback: some apps (e.g. CleanShot) put images under non-standard UTIs.
        // NSImage handles pasteboard type coercion for all AppKit-supported formats.
        let hasImage = items.contains { if case .png = $0 { return true }; if case .tiff = $0 { return true }; return false }
        if !hasImage, let nsImage = NSImage(pasteboard: pb), let tiffData = nsImage.tiffRepresentation {
            items.append(.tiff(tiffData))
        }
        var urls = (pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]) ?? []
        if urls.isEmpty, pb.data(forType: PasteboardUTI.finderNode) != nil,
           let finderURLs = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        {
            urls = finderURLs
        }
        if !urls.isEmpty { items.append(.fileURLs(urls)) }
        return items
    }

    // macOS synthesizes "(image WxH)" as plain text when an image is on the pasteboard
    // but no real plain-text representation exists. Detect and discard these.
    private static func isSynthesizedImagePlaceholder(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("(image "), trimmed.hasSuffix(")") else { return false }
        let inner = trimmed.dropFirst(7).dropLast()
        // Expected format: "WxH" with × (U+00D7) or "x"
        return inner.contains("×") || inner.contains("x")
    }
}

public final class PasteboardObserver {
    private let reader: PasteboardReading
    public private(set) var rules: ExclusionRules
    private let interval: TimeInterval
    private var timer: DispatchSourceTimer?
    private var lastCount: Int = -1
    private let queue = DispatchQueue(label: "PasteboardObserver", qos: .utility)
    private var callback: ((PasteboardChange) -> Void)?

    public init(reader: PasteboardReading, rules: ExclusionRules, pollInterval: TimeInterval = 0.4) {
        self.reader = reader
        self.rules = rules
        interval = pollInterval
    }

    /// Thread-safe rules handoff. Callers (e.g. Darwin notification handler) may
    /// run on arbitrary CFRunLoop threads; the actual mutation hops onto the
    /// observer's serial queue so `tick()` never reads a torn struct.
    public func updateRules(_ rules: ExclusionRules) {
        queue.async { [weak self] in
            self?.rules = rules
        }
    }

    public func start(callback: @escaping (PasteboardChange) -> Void) {
        queue.sync { [weak self] in
            guard let self else { return }
            self.stopOnQueue()
            self.callback = callback
            self.lastCount = self.reader.currentChangeCount()
            let t = DispatchSource.makeTimerSource(queue: self.queue)
            t.schedule(deadline: .now() + self.interval, repeating: self.interval, leeway: .milliseconds(50))
            t.setEventHandler { [weak self] in self?.tick() }
            self.timer = t
            t.resume()
        }
    }

    public func stop() {
        queue.sync { [weak self] in
            self?.stopOnQueue()
        }
    }

    private func stopOnQueue() {
        timer?.cancel()
        timer = nil
        callback = nil
    }

    private func tick() {
        let count = reader.currentChangeCount()
        guard count != lastCount else { return }
        let types = reader.currentTypes()
        lastCount = reader.currentChangeCount()
        if types.contains(PasteboardUTI.daemonWrite.rawValue) { return }
        let bundleID = reader.frontmostBundleID()
        if rules.shouldExclude(types: types, appBundleID: bundleID) { return }
        let items = reader.currentItems()
        let countAfterReadingItems = reader.currentChangeCount()
        if items.isEmpty {
            lastCount = count
            return
        }
        lastCount = countAfterReadingItems
        callback?(PasteboardChange(
            changeCount: count,
            frontmostAppBundleID: bundleID,
            items: items,
            pasteboardTypes: types
        ))
    }
}
