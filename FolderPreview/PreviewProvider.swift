import Cocoa
import Core
import Platform
import Quartz

class PreviewViewController: NSViewController, QLPreviewingController {
    private var scrollView: NSScrollView?
    private var textView: NSTextView?

    override func loadView() {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let text = NSTextView(frame: scroll.bounds)
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = true
        text.backgroundColor = .windowBackgroundColor
        text.autoresizingMask = [.width]
        text.textContainerInset = NSSize(width: 20, height: 16)
        scroll.documentView = text
        scrollView = scroll
        textView = text
        view = scroll
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        Task {
            do {
                let html: String
                if isDirectory {
                    let inv = try await FolderEnumerator.enumerate(url: url, maxEntries: 5_000)
                    html = PreviewHTML.folder(url: url, inventory: inv)
                } else {
                    let entries = try LibArchiveBackend().list(archiveURL: url, limits: .default)
                    html = PreviewHTML.archive(url: url, entries: entries)
                }
                await MainActor.run {
                    if let data = html.data(using: .utf8),
                       let attrStr = NSAttributedString(
                           html: data,
                           options: [.documentType: NSAttributedString.DocumentType.html,
                                     .characterEncoding: String.Encoding.utf8.rawValue],
                           documentAttributes: nil
                       ) {
                        self.textView?.textStorage?.setAttributedString(attrStr)
                    }
                }
                handler(nil)
            } catch {
                handler(error)
            }
        }
    }
}

enum PreviewHTML {
    static func folder(url: URL, inventory: FolderInventory) -> String {
        let rows = inventory.entries.prefix(500).map { e in
            "<tr><td>\(escape(e.name))</td><td>\(e.kind.rawValue)</td><td>\(e.size)</td></tr>"
        }.joined()
        return page(title: escape(url.lastPathComponent), body: """
        <h1>\(escape(url.lastPathComponent))</h1>
        <p>\(inventory.entries.count) items · \(inventory.totalSize) bytes\(inventory.isPartial ? " · partial" : "")</p>
        <table><tr><th>Name</th><th>Kind</th><th>Bytes</th></tr>\(rows)</table>
        """)
    }

    static func archive(url: URL, entries: [ArchiveEntry]) -> String {
        let rows = entries.prefix(500).map { e in
            "<tr><td>\(escape(e.path))</td><td>\(e.isDirectory ? "folder" : "file")</td><td>\(e.uncompressedSize)</td></tr>"
        }.joined()
        return page(title: escape(url.lastPathComponent), body: """
        <h1>\(escape(url.lastPathComponent))</h1>
        <p>\(entries.count) archive entries</p>
        <table><tr><th>Path</th><th>Kind</th><th>Bytes</th></tr>\(rows)</table>
        """)
    }

    private static func page(title: String, body: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <style>body{font:13px -apple-system;margin:0}table{border-collapse:collapse;width:100%}
        td,th{border-bottom:1px solid #ddd;padding:6px;text-align:left}
        h1{font-size:16px;margin-bottom:4px}p{color:#666;font-size:12px;margin-top:0}</style>
        <title>\(title)</title></head><body>\(body)</body></html>
        """
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
