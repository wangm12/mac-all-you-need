import Core
import CryptoKit
import Foundation

/// Owns the 9 encrypted stores that back the app's persistent state.
///
/// AppController used to hold these as 9 separate properties; consolidating
/// them lets the composition root pass a single container reference around
/// instead of replicating the bag at every collaborator boundary.
///
/// Constructed once at app launch by `AppController.init` (see
/// `makeStartupStores`). The same instance is reused for the process
/// lifetime; stores themselves manage their own thread-safety.
@MainActor
final class AppStoreContainer {
    let deviceID: DeviceID
    let pinboard: PinboardStore
    let snippet: SnippetStore
    let clipboard: ClipboardStore
    let voiceTranscripts: VoiceTranscriptStore
    let voiceDictionary: VoiceDictionaryStore
    let voicePersonalization: VoicePersonalizationStore
    let voiceTrainingExamples: VoiceTrainingExampleStore
    let blob: BlobStore
    let search: SearchStore

    init(
        deviceID: DeviceID,
        pinboard: PinboardStore,
        snippet: SnippetStore,
        clipboard: ClipboardStore,
        voiceTranscripts: VoiceTranscriptStore,
        voiceDictionary: VoiceDictionaryStore,
        voicePersonalization: VoicePersonalizationStore,
        voiceTrainingExamples: VoiceTrainingExampleStore,
        blob: BlobStore,
        search: SearchStore
    ) {
        self.deviceID = deviceID
        self.pinboard = pinboard
        self.snippet = snippet
        self.clipboard = clipboard
        self.voiceTranscripts = voiceTranscripts
        self.voiceDictionary = voiceDictionary
        self.voicePersonalization = voicePersonalization
        self.voiceTrainingExamples = voiceTrainingExamples
        self.blob = blob
        self.search = search
    }

    /// Resolve the canonical set of stores backed by the App Group container.
    /// Fails fast if any per-store database migration fails — orphaning a
    /// store silently would lose user data.
    static func makeProductionStores(
        deviceID: DeviceID,
        key: SymmetricKey
    ) throws -> AppStoreContainer {
        let pinboardURL = AppGroup.containerURL().appendingPathComponent("databases/pinboards.sqlite")
        let pinboardDB = try Database(url: pinboardURL, migrations: PinboardStore.migrations)
        let pinboard = PinboardStore(database: pinboardDB, deviceKey: key)

        let snippetURL = AppGroup.containerURL().appendingPathComponent("databases/snippets.sqlite")
        let snippetDB = try Database(url: snippetURL, migrations: SnippetStore.migrations)
        let snippet = SnippetStore(database: snippetDB, deviceKey: key)

        let clipboardURL = AppGroup.containerURL().appendingPathComponent("databases/clipboard.sqlite")
        let clipboardDB = try Database(url: clipboardURL, migrations: ClipboardStore.migrations)
        let clipboard = try ClipboardStore(database: clipboardDB, deviceKey: key, deviceID: deviceID)

        let searchURL = AppGroup.containerURL().appendingPathComponent("databases/search.sqlite")
        let searchDB = try Database(url: searchURL, migrations: SearchStore.migrations)
        let search = SearchStore(database: searchDB)

        let blobRoot = AppGroup.containerURL().appendingPathComponent("blobs", isDirectory: true)
        let blob = BlobStore(rootURL: blobRoot, key: key)

        return AppStoreContainer(
            deviceID: deviceID,
            pinboard: pinboard,
            snippet: snippet,
            clipboard: clipboard,
            voiceTranscripts: VoiceTranscriptStore(database: clipboardDB),
            voiceDictionary: VoiceDictionaryStore(database: clipboardDB),
            voicePersonalization: VoicePersonalizationStore(database: clipboardDB, deviceKey: key),
            voiceTrainingExamples: VoiceTrainingExampleStore(
                database: clipboardDB,
                deviceKey: key,
                audioRoot: AppGroup.containerURL().appendingPathComponent("voice-training-audio", isDirectory: true)
            ),
            blob: blob,
            search: search
        )
    }
}
