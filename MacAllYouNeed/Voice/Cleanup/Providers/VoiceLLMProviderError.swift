import Foundation

enum VoiceLLMProviderError: Error, Equatable {
    case invalidResponse
    case httpStatus(Int)
}
