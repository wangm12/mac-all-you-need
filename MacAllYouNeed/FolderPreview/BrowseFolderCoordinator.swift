import AppKit
import Core
import Foundation

final class BrowseFolderCoordinator: NSObject, FolderPreviewXPCProtocol, NSXPCListenerDelegate {
    static let serviceName = "group.com.macallyouneed.shared.folderpreview"
    let listener: NSXPCListener

    override init() {
        listener = NSXPCListener(machServiceName: Self.serviceName)
        super.init()
        listener.delegate = self
        listener.resume()
    }

    func listener(_: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard Self.isAllowedClient(newConnection) else { return false }
        newConnection.exportedInterface = NSXPCInterface(with: FolderPreviewXPCProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    static func isAllowedClient(_ connection: NSXPCConnection) -> Bool {
        let allowed: Set = ["com.macallyouneed.app"]
        guard let bundleID = NSRunningApplication(processIdentifier: connection.processIdentifier)?.bundleIdentifier
        else { return false }
        return allowed.contains(bundleID)
    }

    private func resolve(bookmark: Data, fallbackPath: String) -> URL? {
        var stale = false
        if let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ), !stale { return url }
        let fallback = URL(fileURLWithPath: fallbackPath)
        guard fallback.path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path) else { return nil }
        return fallback
    }

    func openFile(bookmark: Data, fallbackPath: String, reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            guard let url = self.resolve(bookmark: bookmark, fallbackPath: fallbackPath) else { reply(false); return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            reply(NSWorkspace.shared.open(url))
        }
    }

    func revealInFinder(bookmark: Data, fallbackPath: String, reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            guard let url = self.resolve(bookmark: bookmark, fallbackPath: fallbackPath) else { reply(false); return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            NSWorkspace.shared.activateFileViewerSelecting([url])
            reply(true)
        }
    }

    func copyFileURLToPasteboard(bookmark: Data, fallbackPath: String, reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            guard let url = self.resolve(bookmark: bookmark, fallbackPath: fallbackPath) else { reply(false); return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([url as NSURL])
            reply(true)
        }
    }
}
