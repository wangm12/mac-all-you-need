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
        if let s = pb.string(forType: PasteboardUTI.plainText) { items.append(.text(s)) }
        if let d = pb.data(forType: PasteboardUTI.rtf) { items.append(.rtf(d)) }
        if let s = pb.string(forType: PasteboardUTI.html) { items.append(.html(s)) }
        if let d = pb.data(forType: PasteboardUTI.png) { items.append(.png(d)) }
        if let d = pb.data(forType: PasteboardUTI.tiff) { items.append(.tiff(d)) }
        var urls = (pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]) ?? []
        if urls.isEmpty, pb.data(forType: PasteboardUTI.finderNode) != nil,
           let finderURLs = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        {
            urls = finderURLs
        }
        if !urls.isEmpty { items.append(.fileURLs(urls)) }
        return items
    }
}

public final class PasteboardObserver {
    private let reader: PasteboardReading
    public var rules: ExclusionRules
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

    public func start(callback: @escaping (PasteboardChange) -> Void) {
        self.callback = callback
        lastCount = reader.currentChangeCount()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(50))
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        callback = nil
    }

    private func tick() {
        let count = reader.currentChangeCount()
        guard count != lastCount else { return }
        lastCount = count
        let types = reader.currentTypes()
        let bundleID = reader.frontmostBundleID()
        if rules.shouldExclude(types: types, appBundleID: bundleID) { return }
        let items = reader.currentItems()
        guard !items.isEmpty else { return }
        callback?(PasteboardChange(changeCount: count, frontmostAppBundleID: bundleID, items: items))
    }
}
