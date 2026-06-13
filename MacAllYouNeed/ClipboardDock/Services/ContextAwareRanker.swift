import Core
import Foundation
import UI

/// Reranks clipboard items by how well their content type matches what the
/// frontmost target app is most likely to want. Items within the same
/// preference tier stay in their original recency order.
///
/// Usage:
///   let ranked = ContextAwareRanker.rank(model.items, forBundleID: model.previousFrontmostBundleID)
enum ContextAwareRanker {

    // MARK: - DockItem ranking

    static func rank(_ items: [DockItem], forBundleID bundleID: String?) -> [DockItem] {
        let prefs = preferences(for: bundleID)
        guard !prefs.isEmpty else { return items }
        return stable(items, by: { score(dockItem: $0, prefs: prefs) })
    }

    // MARK: - ClipboardItemMeta ranking

    static func rank(_ items: [ClipboardItemMeta], forBundleID bundleID: String?) -> [ClipboardItemMeta] {
        let prefs = preferences(for: bundleID)
        guard !prefs.isEmpty else { return items }
        return stable(items, by: { score(meta: $0, prefs: prefs) })
    }

    // MARK: - Content type

    private enum ContentType: Int {
        case text, code, image, link, file, color, richText
    }

    // MARK: - Bundle → preferences

    private static func preferences(for bundleID: String?) -> [ContentType] {
        guard let id = bundleID?.lowercased() else { return [] }
        if matchesAny(id, ["xcode", "coderunner", "vscode", "codeedit", "nova", "bbedit",
                            "textmate", "sublimetext", "terminal", "iterm", "warp",
                            "com.apple.dt.xcode", "com.jetbrains"]) {
            return [.code, .text, .link]
        }
        if matchesAny(id, ["figma", "sketch", "pixelmator", "affinity", "illustrator",
                            "photoshop", "canva", "procreate", "gimp"]) {
            return [.image, .color, .text]
        }
        if matchesAny(id, ["finder", "com.apple.finder", "path finder", "forklift",
                            "transmit", "cyberduck"]) {
            return [.file, .image, .text]
        }
        if matchesAny(id, ["slack", "discord", "messages", "telegram", "whatsapp",
                            "signal", "mail", "spark", "airmail", "mimestream",
                            "com.apple.mail"]) {
            return [.text, .link, .image]
        }
        if matchesAny(id, ["safari", "chrome", "firefox", "edge", "arc", "orion",
                            "com.apple.safari", "google chrome", "mozilla"]) {
            return [.link, .text, .image]
        }
        if matchesAny(id, ["word", "pages", "notion", "obsidian", "bear", "craft",
                            "onenote", "scrivener", "ulysses"]) {
            return [.text, .richText, .link]
        }
        return []
    }

    private static func matchesAny(_ bundleID: String, _ fragments: [String]) -> Bool {
        fragments.contains { bundleID.contains($0.lowercased()) }
    }

    // MARK: - Item → score

    private static func score(dockItem item: DockItem, prefs: [ContentType]) -> Int {
        let ct: ContentType
        switch item.kind {
        case .text: ct = .text
        case .code: ct = .code
        case .image: ct = .image
        case .link: ct = .link
        case .file: ct = .file
        case .color: ct = .color
        case .rtf: ct = .richText
        }
        return prefs.firstIndex(of: ct).map { prefs.count - $0 } ?? 0
    }

    private static func score(meta item: ClipboardItemMeta, prefs: [ContentType]) -> Int {
        // Derive content type from preview text using the same heuristics as DockItem.init.
        let ct: ContentType
        if item.preview.hasPrefix("(image") {
            // Image records: preview is "(image WxH)" or similar.
            ct = .image
        } else if item.preview.hasPrefix("(") && item.preview.contains("file") {
            ct = .file
        } else if item.preview == "(rich text)" {
            ct = .richText
        } else {
            switch PreviewDetection.detect(item.preview) {
            case .color: ct = .color
            case .url: ct = .link
            case .code: ct = .code
            case .plain: ct = .text
            }
        }
        return prefs.firstIndex(of: ct).map { prefs.count - $0 } ?? 0
    }

    // MARK: - Stable sort helper

    private static func stable<T>(_ items: [T], by score: (T) -> Int) -> [T] {
        items.enumerated()
            .sorted { a, b in
                let sa = score(a.element), sb = score(b.element)
                return sa != sb ? sa > sb : a.offset < b.offset
            }
            .map(\.element)
    }
}
