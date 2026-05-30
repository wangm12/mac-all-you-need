import Core
import Foundation

/// Process-wide accessor for the folder-history database location and a shared
/// `FolderHistoryStore` instance.
///
/// The feature has three readers — the recorder (main app), the menu-bar view
/// (built from the static feature registry, before `AppController` exists), and
/// the FinderSync extension (separate process). The first two share this single
/// in-process store; the extension opens its own handle at the same URL.
@MainActor
enum FolderHistoryStoreLocator {
    static let databaseURL: URL = AppGroup.containerURL()
        .appendingPathComponent("databases/folder-history.sqlite")

    private static var cached: FolderHistoryStore?

    /// Returns the shared store, or nil if the database cannot be opened.
    static func shared() -> FolderHistoryStore? {
        if let cached { return cached }
        let store = try? FolderHistoryStore(url: databaseURL)
        cached = store
        return store
    }
}
