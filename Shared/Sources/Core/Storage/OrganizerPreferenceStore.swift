import Foundation

public struct FolderCorrection: Codable, Sendable {
    public let originalName: String
    public let correctedName: String
    public let folderPath: String
    public let learnedAt: Date

    public init(originalName: String, correctedName: String, folderPath: String, learnedAt: Date = Date()) {
        self.originalName = originalName
        self.correctedName = correctedName
        self.folderPath = folderPath
        self.learnedAt = learnedAt
    }
}

/// Stores user corrections and folder bookmarks in the App Group.
public final class OrganizerPreferenceStore {
    private let defaults: UserDefaults
    private let correctionKey = "organizer.corrections"
    private let bookmarkKey = "organizer.bookmarks"

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func saveCorrection(_ correction: FolderCorrection) {
        var corrections = loadCorrections()
        corrections.append(correction)
        if let data = try? JSONEncoder().encode(corrections) {
            defaults.set(data, forKey: correctionKey)
        }
    }

    public func loadCorrections() -> [FolderCorrection] {
        guard let data = defaults.data(forKey: correctionKey),
              let corrections = try? JSONDecoder().decode([FolderCorrection].self, from: data)
        else { return [] }
        return corrections
    }

    public func saveBookmark(data: Data, forKey key: String) {
        defaults.set(data, forKey: "\(bookmarkKey).\(key)")
    }

    public func loadBookmark(forKey key: String) -> Data? {
        defaults.data(forKey: "\(bookmarkKey).\(key)")
    }
}
