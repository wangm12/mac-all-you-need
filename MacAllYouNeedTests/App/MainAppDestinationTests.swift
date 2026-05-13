@testable import MacAllYouNeed
import Core
import XCTest

final class MainAppDestinationTests: XCTestCase {
    func testStoredSelectionMapsKnownRawValues() {
        XCTAssertEqual(MainAppDestination.storedSelection("dashboard"), .dashboard)
        XCTAssertEqual(MainAppDestination.storedSelection("clipboard"), .clipboard)
        XCTAssertEqual(MainAppDestination.storedSelection("voice"), .voice)
        XCTAssertEqual(MainAppDestination.storedSelection("downloads"), .downloads)
        XCTAssertEqual(MainAppDestination.storedSelection("folderPreview"), .folderPreview)
        XCTAssertEqual(MainAppDestination.storedSelection("snippets"), .snippets)
        XCTAssertEqual(MainAppDestination.storedSelection("settings"), .settings)
    }

    func testStoredSelectionFallsBackToDashboard() {
        XCTAssertEqual(MainAppDestination.storedSelection(nil), .dashboard)
        XCTAssertEqual(MainAppDestination.storedSelection("missing"), .dashboard)
    }

    func testPersistenceRoundTripsThroughStableStorageKey() {
        let suiteName = "MainAppDestinationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        MainAppDestination.persist(.downloads, to: defaults)

        XCTAssertEqual(defaults.string(forKey: MainAppDestination.storageKey), "downloads")
        XCTAssertEqual(MainAppDestination.load(from: defaults), .downloads)
    }

    func testSettingsPersistenceRoundTripsThroughStableStorageKey() {
        let suiteName = "MainAppDestinationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        MainAppDestination.persist(.settings, to: defaults)

        XCTAssertEqual(defaults.string(forKey: MainAppDestination.storageKey), "settings")
        XCTAssertEqual(MainAppDestination.load(from: defaults), .settings)
    }

    func testSettingsDestinationUsesEmbeddedPresentationInsideMainWindow() {
        XCTAssertEqual(MainAppDestination.settings.contentStyle, .embeddedSettings)
        XCTAssertEqual(MainAppDestination.dashboard.contentStyle, .standard)
        XCTAssertEqual(MainAppDestination.clipboard.contentStyle, .standard)
        XCTAssertEqual(MainAppDestination.voice.contentStyle, .standard)
        XCTAssertEqual(MainAppDestination.downloads.contentStyle, .standard)
        XCTAssertEqual(MainAppDestination.folderPreview.contentStyle, .standard)
        XCTAssertEqual(MainAppDestination.snippets.contentStyle, .standard)
    }

    func testSettingsDestinationDisplaysAsSystemInMainWindowSidebar() {
        XCTAssertEqual(MainAppDestination.settings.title, "System")
        XCTAssertEqual(MainAppDestination.settings.subtitle, "Global settings and maintenance")
    }
}

final class DockSettingsNavigationTests: XCTestCase {
    func testRequestWritesDestinationAndPostsMainWindowSettingsRequest() {
        let suiteName = "DockSettingsNavigationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let center = NotificationCenter()
        var didDismiss = false
        var didActivate = false
        var postedDestination: String?
        let token = center.addObserver(
            forName: .mainWindowSettingsRequested,
            object: nil,
            queue: nil
        ) { note in
            postedDestination = note.object as? String
        }
        defer {
            center.removeObserver(token)
            defaults.removePersistentDomain(forName: suiteName)
        }

        DockSettingsNavigation.request(
            .privacy,
            defaults: defaults,
            notificationCenter: center,
            dismissDock: { didDismiss = true },
            activateApp: { didActivate = true }
        )

        XCTAssertEqual(defaults.string(forKey: "settings.selectedTab"), "privacy")
        XCTAssertTrue(didDismiss)
        XCTAssertTrue(didActivate)
        XCTAssertEqual(postedDestination, "privacy")
    }
}

final class MainClipboardItemPresentationTests: XCTestCase {
    func testImageClipboardItemUsesThumbnailPreview() {
        let item = ClipboardItemMeta(
            id: RecordID(rawValue: "01H00000000000000000000000")!,
            created: Date(timeIntervalSince1970: 10),
            modified: Date(timeIntervalSince1970: 20),
            deviceID: DeviceID(rawValue: "00000000-0000-0000-0000-000000000000")!,
            lamport: 1,
            kind: .clipboardItem,
            preview: "(image 849×906)",
            sourceAppBundleID: nil,
            frequency: 0,
            lastAccessed: nil
        )

        XCTAssertEqual(
            MainClipboardItemPresentation.previewKind(for: item),
            .imageThumbnail(recordID: "01H00000000000000000000000")
        )
    }
}
