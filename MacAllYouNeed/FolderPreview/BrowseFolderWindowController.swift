import AppKit
import SwiftUI
import UI

@MainActor
final class BrowseFolderWindowController {
    private var window: NSWindow?
    private var url: URL = FileManager.default.homeDirectoryForCurrentUser
    private let onAction: (PreviewAction) -> Void

    init(onAction: @escaping (PreviewAction) -> Void) {
        self.onAction = onAction
    }

    func openPanelAndBrowse() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let chosen = panel.url {
            url = chosen
            show()
        }
    }

    func show(at targetURL: URL) {
        url = targetURL
        show()
    }

    func show() {
        if window == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            win.title = "Browse Folder"
            win.center()
            win.contentView = NSHostingView(rootView: FolderPreviewView(folderURL: url, onAction: onAction))
            win.isReleasedWhenClosed = false
            window = win
        } else {
            (window?.contentView as? NSHostingView<FolderPreviewView>)?.rootView = FolderPreviewView(
                folderURL: url,
                onAction: onAction
            )
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
