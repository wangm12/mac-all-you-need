import Core
import Foundation

enum DockListSelector: Hashable {
    case history
    /// User-created pinboard (the auto-created "Pinned" list shows up here
    /// too — it's no longer a special case).
    case pinboard(RecordID)
    case snippets
}
