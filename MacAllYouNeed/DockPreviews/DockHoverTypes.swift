import AppKit
import CoreGraphics
import Foundation

enum DockHoverTarget: Equatable {
    case app(AppHoverInfo)
    case folder(FolderHoverInfo)
    case none

    struct AppHoverInfo: Equatable {
        let pid: pid_t
        let appName: String
        let bundleIdentifier: String?
        let iconRect: CGRect
        let dockItemToken: UInt
    }

    struct FolderHoverInfo: Equatable {
        let url: URL
        let title: String
        let iconRect: CGRect
        let dockItemToken: UInt
    }
}
