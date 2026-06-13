import Foundation

/// Window chrome actions (DockDoor `WindowAction` subset for preview traffic lights).
enum DockPreviewWindowAction: String, Codable, CaseIterable, Hashable, Identifiable {
    case quit
    case close
    case minimize
    case toggleFullScreen
    case maximize
    case bringToCurrentSpace

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .quit: "power"
        case .close: "xmark"
        case .minimize: "minus"
        case .toggleFullScreen: "arrow.up.left.and.arrow.down.right"
        case .maximize: "arrow.up.to.line"
        case .bringToCurrentSpace: "arrow.right.to.line"
        }
    }

    var displayName: String {
        switch self {
        case .quit: "Quit"
        case .close: "Close"
        case .minimize: "Minimize"
        case .toggleFullScreen: "Fullscreen"
        case .maximize: "Maximize"
        case .bringToCurrentSpace: "Bring to Current Space"
        }
    }
}
