import FeatureCore
import Foundation

struct UninstallSheetState {
    struct CacheRow: Identifiable, Equatable {
        let id: String
        let displayName: String
        let bytes: Int64
        var checked: Bool
    }

    var cacheRows: [CacheRow]

    static func from(descriptor: FeatureDescriptor) -> UninstallSheetState {
        UninstallSheetState(cacheRows: descriptor.assetCaches.map { cache in
            let actual = cache.actualBytes()
            return CacheRow(
                id: cache.id,
                displayName: cache.displayName,
                bytes: actual != 0 ? actual : cache.estimatedBytes,
                checked: false
            )
        })
    }

    mutating func toggle(cacheID: String) {
        guard let idx = cacheRows.firstIndex(where: { $0.id == cacheID }) else { return }
        cacheRows[idx].checked.toggle()
    }

    var checkedCacheIDs: [String] {
        cacheRows.filter(\.checked).map(\.id)
    }
}
