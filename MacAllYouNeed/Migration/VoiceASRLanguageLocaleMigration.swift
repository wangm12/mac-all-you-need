import Core
import Foundation

enum VoiceASRLanguageLocaleMigration {
    private static let doneKey = "voice.asr.languageLocaleMigration.v1.done"

    static func migrateIfNeeded() {
        guard !AppGroupSettings.defaults.bool(forKey: doneKey) else { return }
        defer { AppGroupSettings.defaults.set(true, forKey: doneKey) }
        var settings = VoiceASRSettingsStore.load()
        guard settings.languageHint == .automatic else { return }
        settings = settings.updating(languageHint: VoiceASRLanguageHint.localeDefault())
        VoiceASRSettingsStore.save(settings)
    }
}
