import Foundation

public enum VoiceLanguage: String, Codable, Sendable, Equatable {
    case english = "en"
    case chinese = "zh"
    case mixed
    case unknown
}
