import Core
import Foundation

enum PinnedPinboard {
    static let reservedName = "__pinned__"

    static func findOrCreate(in store: PinboardStore) throws -> Pinboard {
        if let existing = (try? store.list())?.first(where: { $0.name == reservedName }) {
            return existing
        }
        return try store.create(name: reservedName, color: nil)
    }

    static func userVisibleLists(_ all: [Pinboard]) -> [Pinboard] {
        all.filter { $0.name != reservedName }
    }
}
