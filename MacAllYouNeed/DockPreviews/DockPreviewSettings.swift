import Foundation

struct DockPreviewSettings: Codable, Equatable {
    var isEnabled: Bool
    var showThumbnails: Bool
    var showOnHoverDelay: TimeInterval

    static let `default` = DockPreviewSettings(isEnabled: false, showThumbnails: true, showOnHoverDelay: 0.5)

    init(isEnabled: Bool = false, showThumbnails: Bool = true, showOnHoverDelay: TimeInterval = 0.5) {
        self.isEnabled = isEnabled
        self.showThumbnails = showThumbnails
        self.showOnHoverDelay = showOnHoverDelay
    }
}
