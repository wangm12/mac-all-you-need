import AppKit
import Core
import CryptoKit
import Foundation
import CoreFoundation
import Platform

final class DaemonContainer {
    private static let settingsChangedDarwin = "com.macallyouneed.settings-changed" as CFString
    private static let defaultExcludedBundleIDs: [String] = [
        "com.apple.keychainaccess",
        "com.1password.1password",
        "com.1password.1password7",
        "com.1password.1password8",
        "com.lastpass.LastPass",
        "com.bitwarden.desktop",
        "com.agilebits.onepassword4",
        "com.dashlane.Dashlane"
    ]

    let key: SymmetricKey
    let deviceID: DeviceID
    let clipDB: Database
    let clip: ClipboardStore
    let searchDB: Database
    let search: SearchStore
    let blobs: BlobStore
    let snippetDB: Database
    let snippets: SnippetStore
    let pinboardDB: Database
    let pinboards: PinboardStore
    let observer: PasteboardObserver
    let expander: SnippetExpander
    let log = Logging.logger(for: "daemon", category: "container")
    private var retentionTimer: DispatchSourceTimer?

    init() throws {
        let root = AppGroup.containerURL().appendingPathComponent("databases", isDirectory: true)
        let blobRoot = AppGroup.containerURL().appendingPathComponent("blobs", isDirectory: true)
        let manager = KeyManager(keychain: SystemKeychain())
        key = try manager.deviceKey()
        deviceID = try DeviceIdentityStore.loadOrCreate(root: AppGroup.containerURL())
        clipDB = try Database(
            url: root.appendingPathComponent("clipboard.sqlite"),
            migrations: ClipboardStore.migrations
        )
        clip = try ClipboardStore(database: clipDB, deviceKey: key, deviceID: deviceID)
        searchDB = try Database(
            url: root.appendingPathComponent("search.sqlite"),
            migrations: SearchStore.migrations
        )
        search = SearchStore(database: searchDB)
        blobs = BlobStore(rootURL: blobRoot, key: key)
        snippetDB = try Database(
            url: root.appendingPathComponent("snippets.sqlite"),
            migrations: SnippetStore.migrations
        )
        snippets = SnippetStore(database: snippetDB, deviceKey: key)
        pinboardDB = try Database(
            url: root.appendingPathComponent("pinboards.sqlite"),
            migrations: PinboardStore.migrations
        )
        pinboards = PinboardStore(database: pinboardDB, deviceKey: key)
        observer = PasteboardObserver(reader: SystemPasteboardReader(), rules: Self.loadRules())
        expander = SnippetExpander { [snippets] trigger in
            try? snippets.find(trigger: trigger)?.body
        }
        expander.start()
        installSettingsReloader()
        startRetentionTimer()
    }

    func persist(item: PasteboardItem, source: String?) throws {
        let rules = observer.rules
        switch item {
        case let .text(text):
            if rules.shouldExcludeText(text) { return }
        case let .html(text):
            if rules.shouldExcludeText(text) { return }
        case let .rtf(data):
            let text = NSAttributedString(rtf: data, documentAttributes: nil)?.string ?? ""
            if rules.shouldExcludeText(text) { return }
        default:
            break
        }

        switch item {
        case let .text(s):
            let meta = try clip.append(.text(s), sourceAppBundleID: source)
            try search.upsert(kind: .clipboardItem, id: meta.id, text: s)
        case let .rtf(d):
            let meta = try clip.append(.rtf(d), sourceAppBundleID: source)
            if let s = NSAttributedString(rtf: d, documentAttributes: nil)?.string {
                try search.upsert(kind: .clipboardItem, id: meta.id, text: s)
            }
        case let .html(s):
            let meta = try clip.append(.html(s), sourceAppBundleID: source)
            try search.upsert(kind: .clipboardItem, id: meta.id, text: s)
        case let .png(d), let .tiff(d):
            let blobID = try blobs.write(d)
            let nsImg = NSImage(data: d)
            let w = Int(nsImg?.size.width ?? 0)
            let h = Int(nsImg?.size.height ?? 0)
            let meta = try clip.append(.image(blobID: blobID, width: w, height: h), sourceAppBundleID: source)
            Task.detached { [search] in
                if let png = Self.pngData(from: d),
                   let text = try? await OCRService.recognize(pngData: png), !text.isEmpty
                {
                    try? search.upsert(kind: .clipboardItem, id: meta.id, text: text)
                }
            }
        case let .fileURLs(urls):
            let meta = try clip.append(.files(urls), sourceAppBundleID: source)
            try search.upsert(
                kind: .clipboardItem,
                id: meta.id,
                text: urls.map(\.lastPathComponent).joined(separator: " ")
            )
        case .unknown:
            break
        }

        CaptureSound.playIfEnabled()
    }

    func isCaptureSuspended(now: Date = Date()) -> Bool {
        guard let until = AppGroupSettings.defaults.object(forKey: "captureSuspendUntil") as? Double else {
            return false
        }
        return now.timeIntervalSince1970 < until
    }

    private static func loadRules() -> ExclusionRules {
        let defaults = AppGroupSettings.defaults
        let blockedArray: [String]
        if let stored = defaults.stringArray(forKey: "clipboardExcludedBundleIDs") {
            blockedArray = stored
        } else {
            blockedArray = defaultExcludedBundleIDs
            defaults.set(blockedArray, forKey: "clipboardExcludedBundleIDs")
        }
        let regexes = defaults.stringArray(forKey: "clipboardRegexBlocklist") ?? []
        return ExclusionRules(
            blockedBundleIDs: Set(blockedArray),
            regexBlocklist: RegexBlocklist(patterns: regexes)
        )
    }

    private func installSettingsReloader() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let me = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            center,
            me,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let container = Unmanaged<DaemonContainer>.fromOpaque(observer).takeUnretainedValue()
                container.observer.rules = DaemonContainer.loadRules()
                container.runRetention()
            },
            Self.settingsChangedDarwin,
            nil,
            .deliverImmediately
        )
    }

    private func startRetentionTimer() {
        let queue = DispatchQueue(label: "RetentionTimer", qos: .utility)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .seconds(5), repeating: .seconds(12 * 3600))
        timer.setEventHandler { [weak self] in
            self?.runRetention()
        }
        retentionTimer = timer
        timer.resume()
    }

    private func runRetention() {
        guard let policy = currentPolicy() else { return }
        let protected = (try? PinboardStore.protectedIDs(from: pinboards)) ?? []
        try? policy.enforceItemCap(store: clip, blobs: blobs, protectedIDs: protected)
        try? policy.enforceMaxAge(store: clip, blobs: blobs, protectedIDs: protected)
        try? policy.enforceImageCap(store: clip, blobs: blobs, protectedIDs: protected)
    }

    private func currentPolicy() -> RetentionPolicy? {
        let defaults = AppGroupSettings.defaults
        let maxItems = defaults.object(forKey: "retention.maxItems") as? Int ?? 1000
        let maxAgeDays = defaults.object(forKey: "retention.maxAgeDays") as? Int ?? 30
        let maxImageMB = defaults.object(forKey: "retention.maxImageMB") as? Int ?? 200

        return RetentionPolicy(
            maxItems: maxItems,
            maxAgeSeconds: maxAgeDays > 0 ? Double(maxAgeDays) * 86400 : nil,
            maxImageBytes: maxImageMB > 0 ? maxImageMB * 1024 * 1024 : nil
        )
    }

    private static func pngData(from data: Data) -> Data? {
        guard let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
