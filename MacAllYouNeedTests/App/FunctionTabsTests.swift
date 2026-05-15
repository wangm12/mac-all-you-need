@testable import MacAllYouNeed
import Core
import Platform
import XCTest

final class FunctionTabsTests: XCTestCase {
    func testClipboardTabDefaultsToHistory() {
        XCTAssertEqual(ClipboardFunctionTab.storedSelection(nil), .history)
        XCTAssertEqual(ClipboardFunctionTab.storedSelection("missing"), .history)
    }

    func testVoiceTabMapsKnownValuesAndDefaultsToDictate() {
        XCTAssertEqual(VoiceFunctionTab.storedSelection("models"), .models)
        XCTAssertEqual(VoiceFunctionTab.storedSelection("dictionary"), .dictionary)
        XCTAssertEqual(VoiceFunctionTab.storedSelection("missing"), .dictate)
    }

    func testDownloadsTabMapsSettings() {
        XCTAssertEqual(DownloadsFunctionTab.storedSelection("settings"), .settings)
    }

    func testFolderPreviewDefaultsToSettingsOnly() {
        XCTAssertEqual(FolderPreviewFunctionTab.storedSelection(nil), .settings)
        XCTAssertEqual(FolderPreviewFunctionTab.storedSelection("browse"), .settings)
        XCTAssertEqual(FolderPreviewFunctionTab.storedSelection("recent"), .settings)
        XCTAssertEqual(FolderPreviewFunctionTab.storedSelection("missing"), .settings)
    }

    func testFolderPreviewMainPageDoesNotShowStaticPreviewViewsSection() {
        XCTAssertEqual(FolderPreviewMainPagePresentation.visibleSectionTitles, ["Preview settings"])
        XCTAssertFalse(FolderPreviewMainPagePresentation.visibleSectionTitles.contains("How to use it"))
        XCTAssertFalse(FolderPreviewMainPagePresentation.visibleSectionTitles.contains("Preview views"))
    }

    func testFolderPreviewSettingsExposeCascadeToggle() {
        XCTAssertEqual(FolderPreviewMainPagePresentation.settingsRowTitles, [
            "Include hidden files",
            "Cascade folders",
            "Maximum entries"
        ])
    }

    func testSnippetsSettingsDoesNotShowStaticTriggerFormatRow() {
        XCTAssertEqual(SnippetsSettingsPresentation.visibleRowTitles, ["Accessibility", "Shortcut"])
        XCTAssertFalse(SnippetsSettingsPresentation.visibleRowTitles.contains("Trigger format"))
    }

    func testEveryFunctionTabHasStableStorageKey() {
        XCTAssertEqual(ClipboardFunctionTab.storageKey, "main.clipboard.selectedTab")
        XCTAssertEqual(VoiceFunctionTab.storageKey, "main.voice.selectedTab")
        XCTAssertEqual(DownloadsFunctionTab.storageKey, "main.downloads.selectedTab")
        XCTAssertEqual(FolderPreviewFunctionTab.storageKey, "main.folderPreview.selectedTab")
        XCTAssertEqual(SnippetsFunctionTab.storageKey, "main.snippets.selectedTab")
    }

    func testAppearanceModeUsesSharedSegmentedTabContract() {
        XCTAssertEqual(AppAppearanceMode.allCases.map(\.title), ["System", "Light", "Dark"])
        XCTAssertEqual(AppAppearanceMode.allCases.map(\.symbolName), [
            "circle.lefthalf.filled",
            "sun.max",
            "moon"
        ])
    }

    func testVoiceActivationModeUsesSharedSegmentedTabContract() {
        XCTAssertEqual(VoiceActivationMode.allCases.map(\.title), ["Toggle", "Hold"])
        XCTAssertEqual(VoiceActivationMode.allCases.map(\.symbolName), ["repeat", "hand.raised"])
    }

    func testDashboardToolTilesUseBalancedMultiToolOrder() {
        let tiles = DashboardToolTilePresentation.dashboardTiles(
            clipboardCount: 30,
            downloadsQueueCount: 0
        )

        XCTAssertEqual(tiles.map(\.destination), [
            .clipboard,
            .voice,
            .downloads,
            .folderPreview,
            .snippets
        ])
        XCTAssertEqual(tiles.map(\.title), [
            "Clipboard",
            "Voice",
            "Downloads",
            "Folder Preview",
            "Snippets"
        ])
        XCTAssertEqual(tiles.first?.detail, "Capture, search, pin, and paste clipboard history.")
        XCTAssertEqual(tiles.first?.metric, "30")
    }

    func testDashboardToolTilesUseStaticDescriptionsBelowTitles() {
        let tiles = DashboardToolTilePresentation.dashboardTiles(
            clipboardCount: 30,
            downloadsQueueCount: 1
        )

        XCTAssertEqual(tiles.map(\.detail), [
            "Capture, search, pin, and paste clipboard history.",
            "Dictate into any app with local speech recognition.",
            "Download media and manage saved files.",
            "Preview Finder folders and archives.",
            "Expand reusable text from this Mac."
        ])
        XCTAssertFalse(tiles.map(\.detail).contains("1 queue item"))
    }

    func testDashboardToolTilesOnlyShowUsefulNumericMetrics() {
        let tiles = DashboardToolTilePresentation.dashboardTiles(
            clipboardCount: 30,
            downloadsQueueCount: 0
        )

        XCTAssertEqual(tiles.map(\.metric), ["30", nil, "0", nil, nil])
    }

    func testDashboardDownloadQueueCountExcludesCompletedAndKeepsFailedRecords() {
        let records = [
            downloadRecord(state: .completed),
            downloadRecord(state: .failed),
            downloadRecord(state: .queued),
            downloadRecord(state: .running),
            downloadRecord(state: .paused)
        ]

        XCTAssertEqual(DashboardDownloadSummaryPresentation.activeQueueCount(in: records), 4)
        XCTAssertFalse(DashboardDownloadSummaryPresentation.isQueueState(.completed))
        XCTAssertTrue(DashboardDownloadSummaryPresentation.isQueueState(.failed))
    }

    func testDownloadsSidebarBadgeCountsOnlyRunningRecords() {
        let records = [
            downloadRecord(state: .completed),
            downloadRecord(state: .failed),
            downloadRecord(state: .queued),
            downloadRecord(state: .running),
            downloadRecord(state: .running),
            downloadRecord(state: .paused)
        ]

        XCTAssertEqual(
            MainSidebarBadgePresentation.badgeText(for: .downloads, records: records),
            "2"
        )
        XCTAssertNil(MainSidebarBadgePresentation.badgeText(for: .clipboard, records: records))
        XCTAssertNil(MainSidebarBadgePresentation.badgeText(for: .downloads, records: [downloadRecord(state: .queued)]))
    }

    func testDashboardToolTilesIncludeShortcutDisplays() {
        let tiles = DashboardToolTilePresentation.dashboardTiles(
            clipboardCount: 30,
            downloadsQueueCount: 0,
            hotkeys: [
                .clipboard: [.defaultClipboard]
            ],
            voiceSettings: .default
        )

        XCTAssertEqual(tiles.map(\.shortcutDisplay), [
            "⇧⌘V",
            "⌃⌥Space",
            nil,
            "Space",
            nil
        ])
    }

    func testDashboardToolTilesDoNotExposeInlineSettingsButtons() {
        let tile = DashboardToolTilePresentation.dashboardTiles(
            clipboardCount: 30,
            downloadsQueueCount: 0
        )[0]

        let modelFields = Mirror(reflecting: tile).children.compactMap(\.label)
        XCTAssertFalse(modelFields.contains("actionTitle"))
    }

    private func downloadRecord(state: DownloadState) -> DownloadRecord {
        DownloadRecord(
            url: "https://example.com/video",
            title: "Video",
            destinationPath: "/tmp/video.mp4",
            state: state
        )
    }

    func testDashboardHeaderDoesNotExposeSettingsAction() {
        XCTAssertNil(DashboardHeaderPresentation.trailingActionTitle)
    }

    func testDashboardUsesToolCardsInsteadOfStaticStartupSummary() {
        XCTAssertFalse(DashboardRenderingPresentation.usesStaticStartupSummary)
        XCTAssertTrue(DashboardRenderingPresentation.usesToolCards)
        XCTAssertFalse(DashboardRenderingPresentation.usesPlainRows)
    }

    func testDashboardToolCardsUseFixedUnifiedHeight() {
        XCTAssertEqual(DashboardRenderingPresentation.toolCardHeight, 156)
    }

    func testMainWindowRootTypeErasesDetailViews() {
        XCTAssertTrue(MainWindowRootPresentation.usesTypeErasedDetailViews)
    }

    func testHotkeyMapStoreExposesPureDefaultMapForViewInitialization() {
        XCTAssertEqual(HotkeyMapStore.defaultMap[.clipboard], [.defaultClipboard])
        XCTAssertEqual(HotkeyMapStore.defaultMap[.browseFolder], [.defaultFolder])
    }

    func testDashboardToolSettingsRoutesOpenEachToolSettingsTab() {
        XCTAssertEqual(
            DashboardToolSettingsNavigation.route(for: .clipboard),
            DashboardToolSettingsRoute(
                destination: .clipboard,
                tabStorageKey: ClipboardFunctionTab.storageKey,
                tabRawValue: ClipboardFunctionTab.settings.rawValue
            )
        )
        XCTAssertEqual(
            DashboardToolSettingsNavigation.route(for: .voice),
            DashboardToolSettingsRoute(
                destination: .voice,
                tabStorageKey: VoiceFunctionTab.storageKey,
                tabRawValue: VoiceFunctionTab.settings.rawValue
            )
        )
        XCTAssertEqual(
            DashboardToolSettingsNavigation.route(for: .downloads),
            DashboardToolSettingsRoute(
                destination: .downloads,
                tabStorageKey: DownloadsFunctionTab.storageKey,
                tabRawValue: DownloadsFunctionTab.settings.rawValue
            )
        )
        XCTAssertEqual(
            DashboardToolSettingsNavigation.route(for: .folderPreview),
            DashboardToolSettingsRoute(
                destination: .folderPreview,
                tabStorageKey: FolderPreviewFunctionTab.storageKey,
                tabRawValue: FolderPreviewFunctionTab.settings.rawValue
            )
        )
        XCTAssertEqual(
            DashboardToolSettingsNavigation.route(for: .snippets),
            DashboardToolSettingsRoute(
                destination: .snippets,
                tabStorageKey: SnippetsFunctionTab.storageKey,
                tabRawValue: SnippetsFunctionTab.settings.rawValue
            )
        )
    }

    func testFunctionPageHeaderShortcutsAreReadOnlyDisplayOnly() {
        for destination in MainAppDestination.primarySidebarDestinations where destination != .dashboard {
            XCTAssertFalse(MainToolHeaderShortcutModel.isEditable(for: destination))
        }
    }

    func testFunctionPageHeaderShortcutDisplayComesFromCurrentSettings() {
        let hotkeys: [HotkeyAction: [HotkeyDescriptor]] = [
            .clipboard: [.defaultDownload]
        ]
        let voiceSettings = VoiceActivationSettings(
            shortcut: HotkeyDescriptor(keyCode: 49, modifiers: [.command, .option]),
            mode: .toggle
        )

        XCTAssertEqual(
            MainToolHeaderShortcutModel.display(for: .clipboard, hotkeys: hotkeys, voiceSettings: voiceSettings),
            "⇧⌘D"
        )
        XCTAssertEqual(
            MainToolHeaderShortcutModel.display(for: .downloads, hotkeys: hotkeys, voiceSettings: voiceSettings),
            nil
        )
        XCTAssertEqual(
            MainToolHeaderShortcutModel.display(for: .snippets, hotkeys: hotkeys, voiceSettings: voiceSettings),
            "⇧⌘D"
        )
        XCTAssertEqual(
            MainToolHeaderShortcutModel.display(for: .voice, hotkeys: hotkeys, voiceSettings: voiceSettings),
            "⌥⌘Space"
        )
        XCTAssertEqual(
            MainToolHeaderShortcutModel.display(for: .folderPreview, hotkeys: hotkeys, voiceSettings: voiceSettings),
            "Space"
        )
    }

    func testFunctionPageHeaderDoesNotReportDownloadSystemHotkeyConflict() {
        let issue = MainToolHeaderShortcutModel.issue(
            for: .downloads,
            hotkeys: HotkeyMapStore.defaultMap,
            voiceSettings: .default,
            systemHotkeys: [.defaultDownload]
        )

        XCTAssertNil(issue)
    }

    func testFunctionPageHeaderHasNoDownloadConflictWhenSystemHotkeysAreClear() {
        let issue = MainToolHeaderShortcutModel.issue(
            for: .downloads,
            hotkeys: HotkeyMapStore.defaultMap,
            voiceSettings: .default,
            systemHotkeys: []
        )

        XCTAssertNil(issue)
    }

    func testTabFlowDirectionFollowsTabOrder() {
        let tabs = Array(ClipboardFunctionTab.allCases)

        XCTAssertEqual(
            FunctionTabFlow.direction(from: .history, to: .settings, in: tabs),
            .forward
        )
        XCTAssertEqual(
            FunctionTabFlow.direction(from: .settings, to: .rules, in: tabs),
            .backward
        )
        XCTAssertNil(FunctionTabFlow.direction(from: .rules, to: .rules, in: tabs))
    }

    func testTabFlowContentInsertionOffsetIsSmallAndDirectional() {
        XCTAssertEqual(FunctionTabFlow.contentInsertionOffset(for: .forward), 18)
        XCTAssertEqual(FunctionTabFlow.contentInsertionOffset(for: .backward), -18)
    }
}
