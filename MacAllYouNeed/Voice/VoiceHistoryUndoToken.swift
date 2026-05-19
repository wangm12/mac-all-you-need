import Foundation

struct VoiceHistoryUndoToken {
    let message: String
    let undo: () -> Void
    let expiresAt: Date
}
