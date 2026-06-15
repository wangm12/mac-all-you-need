import Core
import Foundation

/// All ASR engine implementations satisfy VoiceTranscriptionEngine from the
/// Shared package. This typealias keeps existing callers compiling without change.
typealias ASRProviding = VoiceTranscriptionEngine
