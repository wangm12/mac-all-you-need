import Foundation

public enum FeatureID: String, CaseIterable, Codable, Sendable, Hashable {
    case clipboard
    case folderPreview
    case downloader
    case voice
}
