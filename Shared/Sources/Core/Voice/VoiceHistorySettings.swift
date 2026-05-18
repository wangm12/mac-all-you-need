import Foundation

public struct VoiceHistorySettings: Equatable, Sendable {
    public var retention: VoiceHistoryRetention
    public var saveAudio: Bool

    public init(retention: VoiceHistoryRetention = .forever, saveAudio: Bool = false) {
        self.retention = retention
        self.saveAudio = saveAudio
    }

    public static let retentionKey = "voice.history.retention"
    public static let saveAudioKey = "voice.history.saveAudio"

    public static func load(from defaults: UserDefaults) -> VoiceHistorySettings {
        let retention: VoiceHistoryRetention
        if let raw = defaults.string(forKey: retentionKey) {
            retention = VoiceHistoryRetention(storageKey: raw)
        } else {
            retention = .forever
        }
        let saveAudio = defaults.bool(forKey: saveAudioKey)
        return VoiceHistorySettings(retention: retention, saveAudio: saveAudio)
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(retention.storageKey, forKey: Self.retentionKey)
        defaults.set(saveAudio, forKey: Self.saveAudioKey)
    }
}
