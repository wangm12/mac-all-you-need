import Core
import Foundation

enum DockListSelector: Hashable {
    case history
    case pinned
    case pinboard(RecordID)
    case snippets
}
