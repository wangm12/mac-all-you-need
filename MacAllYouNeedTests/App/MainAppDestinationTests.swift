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
        XCTAssertEqual(MainAppDestination.storedSelection("snippets"), .clipboard)
        XCTAssertEqual(MainAppDestination.storedSelection("finderHistory"), .folderPreview)
        XCTAssertEqual(MainAppDestination.storedSelection("windowLayouts"), .windowLayouts)
        XCTAssertEqual(MainAppDestination.storedSelection("grabAnywhere"), .grabAnywhere)
        XCTAssertEqual(MainAppDestination.storedSelection("settings"), .settings)
        XCTAssertEqual(MainAppDestination.storedSelection("voiceReminders"), .voice)
    }

    func testLegacyWindowsSelectionMapsToWindowLayouts() {
        XCTAssertEqual(MainAppDestination.storedSelection("windows"), .windowLayouts)
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

    func testPrimarySidebarDestinationsExcludeFooterSettings() {
        XCTAssertFalse(MainAppDestination.primarySidebarDestinations.contains(.settings))
        XCTAssertTrue(MainAppDestination.allCases.contains(.settings))
    }

    func testWindowFeatureDestinationsUseStablePresentationMetadata() {
        XCTAssertEqual(MainAppDestination.windowLayouts.title, "Window Layouts")
        XCTAssertEqual(MainAppDestination.windowLayouts.subtitle, "Keyboard shortcuts and edge snapping")
        XCTAssertEqual(MainAppDestination.windowLayouts.symbolName, "rectangle.3.group")
        XCTAssertEqual(MainAppDestination.grabAnywhere.title, "Window Grab")
        XCTAssertEqual(MainAppDestination.grabAnywhere.subtitle, "Modifier-drag windows")
        XCTAssertEqual(MainAppDestination.grabAnywhere.symbolName, "hand.draw")
    }

    func testPrimarySidebarDestinationsMergeSnippetsAndFinderHistoryIntoParentTools() {
        XCTAssertEqual(MainAppDestination.primarySidebarDestinations, [
            .dashboard,
            .clipboard,
            .voice,
            .downloads,
            .aiFileOrganizer,
            .folderPreview,
            .windowLayouts,
            .grabAnywhere,
            .windowHub
        ])
        XCTAssertFalse(MainAppDestination.primarySidebarDestinations.contains(.settings))
    }

    func testDestinationViewTypeNamesAreStable() {
        XCTAssertEqual(
            MainWindowDestinationRouter.detailViewTypeName(for: .dashboard),
            "DashboardDestinationView"
        )
        XCTAssertEqual(
            MainWindowDestinationRouter.detailViewTypeName(for: .clipboard),
            "ClipboardDestinationView"
        )
        XCTAssertEqual(
            MainWindowDestinationRouter.detailViewTypeName(for: .voice),
            "VoiceDestinationView"
        )
        XCTAssertEqual(
            MainWindowDestinationRouter.detailViewTypeName(for: .downloads),
            "DownloadsDestinationView"
        )
        XCTAssertEqual(
            MainWindowDestinationRouter.detailViewTypeName(for: .folderPreview),
            "FolderPreviewDestinationView"
        )
        XCTAssertEqual(
            MainWindowDestinationRouter.detailViewTypeName(for: .snippets),
            "ClipboardDestinationView"
        )
        XCTAssertEqual(
            MainWindowDestinationRouter.detailViewTypeName(for: .finderHistory),
            "FolderPreviewDestinationView"
        )
        XCTAssertEqual(
            MainWindowDestinationRouter.detailViewTypeName(for: .windowLayouts),
            "WindowLayoutsDestinationView"
        )
        XCTAssertEqual(
            MainWindowDestinationRouter.detailViewTypeName(for: .grabAnywhere),
            "WindowGrabDestinationView"
        )
        XCTAssertEqual(
            MainWindowDestinationRouter.detailViewTypeName(for: .settings),
            "SettingsDestinationView"
        )
    }
}

final class DockSettingsNavigationTests: XCTestCase {
    func testRequestClipboardRulesSelectsClipboardRulesAndPostsDedicatedRoute() {
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

        DockSettingsNavigation.requestClipboardRules(
            defaults: defaults,
            notificationCenter: center,
            dismissDock: { didDismiss = true },
            activateApp: { didActivate = true }
        )

        XCTAssertEqual(defaults.string(forKey: ClipboardFunctionTab.storageKey), ClipboardFunctionTab.settings.rawValue)
        XCTAssertTrue(didDismiss)
        XCTAssertTrue(didActivate)
        XCTAssertEqual(postedDestination, DockSettingsNavigation.clipboardRulesRoute)
    }

    func testClipboardRulesRouteAcceptsLegacyPrivacyRequests() {
        XCTAssertTrue(DockSettingsNavigation.isClipboardRulesRoute(DockSettingsNavigation.clipboardRulesRoute))
        XCTAssertTrue(DockSettingsNavigation.isClipboardRulesRoute("privacy"))
        XCTAssertFalse(DockSettingsNavigation.isClipboardRulesRoute("general"))
    }
}

final class MainClipboardItemPresentationTests: XCTestCase {
    func testClipboardHistoryFiltersPreviewAndCustomLabelCaseInsensitively() {
        let items = [
            makeClipboardItem(preview: "Deploy service"),
            makeClipboardItem(preview: "Plain text", customLabel: "Production command"),
            makeClipboardItem(preview: "Meeting notes")
        ]

        let state = MainClipboardHistoryPresentation.state(
            items: items,
            query: "prod",
            requestedPage: 0,
            pageSize: 20
        )

        XCTAssertEqual(state.totalItems, 1)
        XCTAssertEqual(state.visibleItems.map(\.customLabel), ["Production command"])
    }

    func testClipboardHistoryPaginatesAllFilteredItemsAndClampsPage() {
        let items = (0 ..< 45).map { makeClipboardItem(preview: "Item \($0)") }

        let state = MainClipboardHistoryPresentation.state(
            items: items,
            query: "",
            requestedPage: 99,
            pageSize: 20
        )

        XCTAssertEqual(state.currentPage, 2)
        XCTAssertEqual(state.totalPages, 3)
        XCTAssertEqual(state.totalItems, 45)
        XCTAssertEqual(state.visibleItems.map(\.preview), ["Item 40", "Item 41", "Item 42", "Item 43", "Item 44"])
        XCTAssertEqual(state.rangeText, "41-45 of 45")
        XCTAssertTrue(state.canGoPrevious)
        XCTAssertFalse(state.canGoNext)
    }

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

    func testClipboardHistoryIconUsesSourceAppBundleIDWhenAvailable() {
        let item = makeClipboardItem(preview: "Deploy service", sourceAppBundleID: "com.apple.Safari")

        XCTAssertEqual(
            ClipboardHistoryIconPresentation.iconKind(for: item, fallbackSymbol: "doc.plaintext"),
            .sourceApp(bundleID: "com.apple.Safari", fallbackSymbol: "doc.plaintext")
        )
    }

    func testClipboardHistoryIconFallsBackToSymbolWithoutSourceApp() {
        let item = makeClipboardItem(preview: "Deploy service", sourceAppBundleID: nil)

        XCTAssertEqual(
            ClipboardHistoryIconPresentation.iconKind(for: item, fallbackSymbol: "doc.plaintext"),
            .symbol("doc.plaintext")
        )
    }

    func testClipboardHistoryIconTreatsBlankSourceAppAsMissing() {
        let item = makeClipboardItem(preview: "Deploy service", sourceAppBundleID: " ")

        XCTAssertEqual(
            ClipboardHistoryIconPresentation.iconKind(for: item, fallbackSymbol: "doc.plaintext"),
            .symbol("doc.plaintext")
        )
    }

    func testDashboardPreviewHidesSensitiveText() {
        XCTAssertEqual(
            DashboardClipboardPreviewPresentation.displayTitle(
                customLabel: nil,
                preview: "CODEX_AUTH_TOKEN=$(usso -ussh genai-api -print)"
            ),
            "Sensitive text captured"
        )
    }

    func testDashboardPreviewKeepsCustomLabel() {
        XCTAssertEqual(
            DashboardClipboardPreviewPresentation.displayTitle(
                customLabel: "Deploy command",
                preview: "API_KEY=abc123"
            ),
            "Deploy command"
        )
    }

    private func makeClipboardItem(
        preview: String,
        customLabel: String? = nil,
        sourceAppBundleID: String? = nil
    ) -> ClipboardItemMeta {
        ClipboardItemMeta(
            id: RecordID.generate(),
            created: Date(timeIntervalSince1970: 10),
            modified: Date(timeIntervalSince1970: 20),
            deviceID: DeviceID(rawValue: "00000000-0000-0000-0000-000000000000")!,
            lamport: 1,
            kind: .clipboardItem,
            preview: preview,
            sourceAppBundleID: sourceAppBundleID,
            frequency: 0,
            lastAccessed: nil,
            customLabel: customLabel
        )
    }
}

final class MainVoiceTranscriptHistoryPresentationTests: XCTestCase {
    func testDisplayTextPrefersCleanedTranscriptAndFallsBackToRaw() {
        XCTAssertEqual(
            MainVoiceTranscriptHistoryPresentation.displayText(
                makeTranscript(id: "clean", rawText: "raw transcript", cleanedText: "clean transcript")
            ),
            "clean transcript"
        )
        XCTAssertEqual(
            MainVoiceTranscriptHistoryPresentation.displayText(
                makeTranscript(id: "raw", rawText: "raw transcript", cleanedText: "")
            ),
            "raw transcript"
        )
        XCTAssertEqual(
            MainVoiceTranscriptHistoryPresentation.displayText(
                makeTranscript(id: "empty", rawText: "   ", cleanedText: "\n")
            ),
            "Empty transcript"
        )
        XCTAssertEqual(
            MainVoiceTranscriptHistoryPresentation.displayText(
                makeTranscript(
                    id: "cancelled",
                    rawText: "",
                    cleanedText: "",
                    status: .failed,
                    failedStage: .cancelled,
                    failureReason: "user_cancelled"
                )
            ),
            "Cancelled"
        )
    }

    func testClickSelectionMatchesClipboardHistoryRules() {
        let orderedIDs = ["one", "two", "three", "four"]

        let single = MainVoiceTranscriptHistoryPresentation.selection(
            afterClicking: "two",
            orderedIDs: orderedIDs,
            selectedIDs: ["one", "three"],
            anchorID: "one",
            command: false,
            shift: false
        )
        XCTAssertEqual(single.selectedIDs, ["two"])
        XCTAssertEqual(single.anchorID, "two")

        let toggled = MainVoiceTranscriptHistoryPresentation.selection(
            afterClicking: "three",
            orderedIDs: orderedIDs,
            selectedIDs: ["two"],
            anchorID: "two",
            command: true,
            shift: false
        )
        XCTAssertEqual(toggled.selectedIDs, ["two", "three"])
        XCTAssertEqual(toggled.anchorID, "three")

        let range = MainVoiceTranscriptHistoryPresentation.selection(
            afterClicking: "four",
            orderedIDs: orderedIDs,
            selectedIDs: ["two"],
            anchorID: "two",
            command: false,
            shift: true
        )
        XCTAssertEqual(range.selectedIDs, ["two", "three", "four"])
        XCTAssertEqual(range.anchorID, "two")
    }

    func testEffectiveSelectionAndArrowMovementUseVisibleOrder() {
        let orderedIDs = ["one", "two", "three"]

        XCTAssertEqual(
            MainVoiceTranscriptHistoryPresentation.effectiveIDs(
                selectedIDs: ["three", "one"],
                anchorID: "two",
                orderedIDs: orderedIDs
            ),
            ["one", "three"]
        )
        XCTAssertEqual(
            MainVoiceTranscriptHistoryPresentation.effectiveIDs(
                selectedIDs: [],
                anchorID: "two",
                orderedIDs: orderedIDs
            ),
            ["two"]
        )
        XCTAssertEqual(
            MainVoiceTranscriptHistoryPresentation.effectiveIDs(
                selectedIDs: [],
                anchorID: nil,
                orderedIDs: orderedIDs
            ),
            ["one"]
        )

        let moved = MainVoiceTranscriptHistoryPresentation.selection(
            afterMovingFrom: "two",
            orderedIDs: orderedIDs,
            delta: 1
        )
        XCTAssertEqual(moved.selectedIDs, ["three"])
        XCTAssertEqual(moved.anchorID, "three")
    }

    private func makeTranscript(
        id: String,
        rawText: String,
        cleanedText: String,
        status: VoiceTranscriptStatus = .success,
        failedStage: VoiceTranscriptFailedStage? = nil,
        failureReason: String? = nil
    ) -> VoiceTranscript {
        VoiceTranscript(
            id: id,
            startedAt: Date(timeIntervalSince1970: 1),
            endedAt: Date(timeIntervalSince1970: 2),
            durationMs: 1_000,
            rawText: rawText,
            cleanedText: cleanedText,
            appBundleID: nil,
            language: .mixed,
            modelIdentifier: "qwen3-asr-0.6b-f32",
            audioPath: nil,
            status: status,
            failedStage: failedStage,
            failureReason: failureReason
        )
    }
}
