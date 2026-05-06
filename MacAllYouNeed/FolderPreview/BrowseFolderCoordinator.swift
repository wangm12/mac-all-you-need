import AppKit
import Foundation
import UI

@MainActor
final class BrowseFolderCoordinator {
    func perform(_ action: PreviewAction) {
        switch action {
        case let .open(url):
            NSWorkspace.shared.open(url)
        case let .copy(url):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([url as NSURL])
        case let .revealInFinder(url):
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}
