import Cocoa
import Core
import Platform
import Quartz
import WebKit

class PreviewViewController: NSViewController, QLPreviewingController {
    private var webView: WKWebView?

    override func loadView() {
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        webView = web
        view = web
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
                    webView?.loadHTMLString(html, baseURL: nil)
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
        let rows = inventory.entries.prefix(500).map { entry in
            "<tr><td>\(escape(entry.name))</td><td>\(entry.kind.rawValue)</td><td>\(entry.size)</td></tr>"
        }.joined()
        return page(title: escape(url.lastPathComponent), body: """
        <h1>\(escape(url.lastPathComponent))</h1>
        <p>\(inventory.entries.count) items · \(inventory.totalSize) bytes\(inventory.isPartial ? " · partial" : "")</p>
        <table><tr><th>Name</th><th>Kind</th><th>Bytes</th></tr>\(rows)</table>
        """)
    }

    static func archive(url: URL, entries: [ArchiveEntry]) -> String {
        let rows = entries.prefix(500).map { entry in
            "<tr><td>\(escape(entry.path))</td><td>\(entry.isDirectory ? "folder" : "file")</td><td>\(entry.uncompressedSize)</td></tr>"
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
        <style>body{font:13px -apple-system;margin:20px;color:#1f2328}
        table{border-collapse:collapse;width:100%}td,th{border-bottom:1px solid #ddd;padding:6px;text-align:left}
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
