import Core
import Foundation

enum DockListSelector: Hashable {
    case history
    /// User-created pinboard (the auto-created "Pinned" list shows up here
    /// too — it's no longer a special case).
    case pinboard(RecordID)
    case snippets

    var animationID: String {
        switch self {
        case .history:
            return "history"
        case .snippets:
            return "snippets"
        case let .pinboard(id):
            return "pinboard-\(id.rawValue)"
        }
    }
}
