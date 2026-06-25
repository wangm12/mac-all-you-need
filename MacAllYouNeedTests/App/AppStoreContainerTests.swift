@testable import MacAllYouNeed
import Core
import CryptoKit
import Foundation
import XCTest

/// Characterization tests for AppStoreContainer.
///
/// Pins the contract that AppStoreContainer exposes the 9 encrypted stores
/// that AppController previously held as individual properties. These tests
/// were authored before AppController was decomposed and must still pass
/// after the extraction — see Phase 7 W1 in CLAUDE.md.
@MainActor
final class AppStoreContainerTests: XCTestCase {
    /// A bag of fresh on-disk stores backed by per-test temporary directories.
    /// Mirrors AppController.makeStartupStores but isolates each test run.
    private struct TestStores {
        let pinboard: PinboardStore
        let snippet: SnippetStore
        let clipboard: ClipboardStore
        let voiceTranscripts: VoiceTranscriptStore
        let voiceDictionary: VoiceDictionaryStore
        let voicePersonalization: VoicePersonalizationStore
        let voiceTrainingExamples: VoiceTrainingExampleStore
        let voiceDictionarySuggestions: VoiceDictionarySuggestionStore
        let blob: BlobStore
        let search: SearchStore
    }

    private var tempRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppStoreContainerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        tempRoot = nil
        try super.tearDownWithError()
    }

    func testContainerExposesEachStoreAsPersistedReference() throws {
        let stores = try makeStores()
        let deviceID = DeviceID.generate()
        let container = AppStoreContainer(
            deviceID: deviceID,
            pinboard: stores.pinboard,
            snippet: stores.snippet,
            clipboard: stores.clipboard,
            voiceTranscripts: stores.voiceTranscripts,
            voiceDictionary: stores.voiceDictionary,
            voicePersonalization: stores.voicePersonalization,
            voiceTrainingExamples: stores.voiceTrainingExamples,
            voiceDictionarySuggestions: stores.voiceDictionarySuggestions,
            blob: stores.blob,
            search: stores.search
        )

        XCTAssertTrue(container.pinboard === stores.pinboard)
        XCTAssertTrue(container.snippet === stores.snippet)
        XCTAssertTrue(container.clipboard === stores.clipboard)
        XCTAssertTrue(container.voiceTranscripts === stores.voiceTranscripts)
        XCTAssertTrue(container.voiceDictionary === stores.voiceDictionary)
        XCTAssertTrue(container.voicePersonalization === stores.voicePersonalization)
        XCTAssertTrue(container.voiceTrainingExamples === stores.voiceTrainingExamples)
        XCTAssertTrue(container.blob === stores.blob)
        XCTAssertTrue(container.search === stores.search)
        XCTAssertEqual(container.deviceID.rawValue, deviceID.rawValue)
    }

    func testContainerPreservesStoreTypesForAllNineSlots() throws {
        let stores = try makeStores()
        let deviceID = DeviceID.generate()
        let container = AppStoreContainer(
            deviceID: deviceID,
            pinboard: stores.pinboard,
            snippet: stores.snippet,
            clipboard: stores.clipboard,
            voiceTranscripts: stores.voiceTranscripts,
            voiceDictionary: stores.voiceDictionary,
            voicePersonalization: stores.voicePersonalization,
            voiceTrainingExamples: stores.voiceTrainingExamples,
            voiceDictionarySuggestions: stores.voiceDictionarySuggestions,
            blob: stores.blob,
            search: stores.search
        )

        // If any extraction silently demoted a store reference to a protocol or
        // wrapper, these `is` checks would fail — the container must surface the
        // concrete types AppController used to hold.
        XCTAssertTrue((container.pinboard as Any) is PinboardStore)
        XCTAssertTrue((container.snippet as Any) is SnippetStore)
        XCTAssertTrue((container.clipboard as Any) is ClipboardStore)
        XCTAssertTrue((container.voiceTranscripts as Any) is VoiceTranscriptStore)
        XCTAssertTrue((container.voiceDictionary as Any) is VoiceDictionaryStore)
        XCTAssertTrue((container.voicePersonalization as Any) is VoicePersonalizationStore)
        XCTAssertTrue((container.voiceTrainingExamples as Any) is VoiceTrainingExampleStore)
        XCTAssertTrue((container.blob as Any) is BlobStore)
        XCTAssertTrue((container.search as Any) is SearchStore)
    }

    // MARK: - Helpers

    private func makeStores() throws -> TestStores {
        let key = SymmetricKey(size: .bits256)
        let deviceID = DeviceID.generate()

        let pinboardURL = tempRoot.appendingPathComponent("pinboards.sqlite")
        let pinboardDB = try Database(url: pinboardURL, migrations: PinboardStore.migrations)
        let pinboard = PinboardStore(database: pinboardDB, deviceKey: key)

        let snippetURL = tempRoot.appendingPathComponent("snippets.sqlite")
        let snippetDB = try Database(url: snippetURL, migrations: SnippetStore.migrations)
        let snippet = SnippetStore(database: snippetDB, deviceKey: key)

        let clipboardURL = tempRoot.appendingPathComponent("clipboard.sqlite")
        let clipboardDB = try Database(url: clipboardURL, migrations: ClipboardStore.migrations)
        let clipboard = try ClipboardStore(database: clipboardDB, deviceKey: key, deviceID: deviceID)

        let searchURL = tempRoot.appendingPathComponent("search.sqlite")
        let searchDB = try Database(url: searchURL, migrations: SearchStore.migrations)
        let search = SearchStore(database: searchDB)

        let blob = BlobStore(rootURL: tempRoot.appendingPathComponent("blobs", isDirectory: true), key: key)

        return TestStores(
            pinboard: pinboard,
            snippet: snippet,
            clipboard: clipboard,
            voiceTranscripts: VoiceTranscriptStore(database: clipboardDB),
            voiceDictionary: VoiceDictionaryStore(database: clipboardDB),
            voicePersonalization: VoicePersonalizationStore(database: clipboardDB, deviceKey: key),
            voiceTrainingExamples: VoiceTrainingExampleStore(
                database: clipboardDB,
                deviceKey: key,
                audioRoot: tempRoot.appendingPathComponent("voice-training-audio", isDirectory: true)
            ),
            voiceDictionarySuggestions: VoiceDictionarySuggestionStore(database: clipboardDB),
            blob: blob,
            search: search
        )
    }
}
