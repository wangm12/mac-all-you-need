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

    func testVoiceMainPageHeaderShowsShortcutWithoutInlineStartButton() {
        XCTAssertTrue(VoiceMainPagePresentation.showsHeaderShortcut)
        XCTAssertNil(VoiceMainPagePresentation.headerActionTitle)
    }

    func testDownloadsTabMapsSettings() {
        XCTAssertEqual(DownloadsFunctionTab.storedSelection("settings"), .settings)
    }

    func testDownloadsTabMigratesLegacyQueueAndCompletedSelections() {
        XCTAssertEqual(DownloadsFunctionTab.storedSelection("queue"), .downloads)
        XCTAssertEqual(DownloadsFunctionTab.storedSelection("completed"), .downloads)
    }

    func testWindowLayoutsTabDefaultsToShortcuts() {
        XCTAssertEqual(WindowLayoutsFunctionTab.storedSelection(nil), .shortcuts)
        XCTAssertEqual(WindowLayoutsFunctionTab.storedSelection("missing"), .shortcuts)
    }

    func testWindowLayoutsTabMapsAllCases() {
        XCTAssertEqual(WindowLayoutsFunctionTab.storedSelection("shortcuts"), .shortcuts)
        XCTAssertEqual(WindowLayoutsFunctionTab.storedSelection("radial"), .radial)
        XCTAssertEqual(WindowLayoutsFunctionTab.storedSelection("snap"), .snap)
        XCTAssertEqual(WindowLayoutsFunctionTab.storedSelection("apps"), .apps)
        XCTAssertEqual(WindowLayoutsFunctionTab.storedSelection("rules"), .rules)
        XCTAssertEqual(WindowLayoutsFunctionTab.storedSelection("diagnostics"), .diagnostics)
    }

    func testRadialMenuSettingsPresentationSectionsWhenEnabled() {
        XCTAssertEqual(
            RadialMenuSettingsPresentation.sectionTitles(whenEnabled: true),
            ["Radial Menu", "Preview", "Trigger", "Selection", "Target Highlight", "Layout Actions"]
        )
    }

    func testWindowGrabTabDefaultsToGesture() {
        XCTAssertEqual(WindowGrabFunctionTab.storedSelection(nil), .gesture)
        XCTAssertEqual(WindowGrabFunctionTab.storedSelection("missing"), .gesture)
    }

    func testWindowGrabTabMapsAllCases() {
        XCTAssertEqual(WindowGrabFunctionTab.storedSelection("gesture"), .gesture)
        XCTAssertEqual(WindowGrabFunctionTab.storedSelection("apps"), .apps)
    }

    func testDownloadJobRowPresentationMapsQueuedRunningMergingPausedCompletedAndFailedStates() {
        let queued = DownloadJobRowModel(
            record: downloadPresentationRecord(state: .queued),
            progress: nil,
            statusText: nil
        )
        XCTAssertEqual(queued.statusText, "Queued")
        XCTAssertEqual(queued.phase, "Waiting for an available slot")
        XCTAssertEqual(queued.statusPillKind, .neutral)
        XCTAssertEqual(queued.progress, 0)

        let running = DownloadJobRowModel(
            record: downloadPresentationRecord(state: .running),
            progress: DownloadProgress(
                fraction: 0.42,
                speedBytesPerSec: 14_200_000,
                etaSeconds: 62,
                downloadedBytes: 42,
                totalBytes: 100
            ),
            statusText: "Downloading 720p video"
        )
        XCTAssertEqual(running.statusText, "Downloading")
        XCTAssertEqual(running.phase, "Downloading 720p video")
        XCTAssertEqual(running.statusPillKind, .progress)
        XCTAssertEqual(running.progress, 0.42, accuracy: 0.001)
        XCTAssertNotNil(running.speedText)
        XCTAssertEqual(running.etaText, "ETA 1:02")

        let merging = DownloadJobRowModel(
            record: downloadPresentationRecord(state: .running),
            progress: DownloadProgress(
                fraction: 1,
                speedBytesPerSec: nil,
                etaSeconds: nil,
                downloadedBytes: 100,
                totalBytes: 100
            ),
            statusText: "Merging video and audio"
        )
        XCTAssertEqual(merging.statusText, "Merging")
        XCTAssertEqual(merging.phase, "Merging video and audio")

        let paused = DownloadJobRowModel(
            record: downloadPresentationRecord(state: .paused, bytesDownloaded: 31, bytesTotal: 100),
            progress: nil,
            statusText: nil
        )
        XCTAssertEqual(paused.statusText, "Paused")
        XCTAssertEqual(paused.phase, "Paused; resume continues from partial file")
        XCTAssertEqual(paused.statusPillKind, .warning)
        XCTAssertEqual(paused.progress, 0.31, accuracy: 0.001)

        let completed = DownloadJobRowModel(
            record: downloadPresentationRecord(state: .completed, bytesDownloaded: 100, bytesTotal: 100),
            progress: nil,
            statusText: nil
        )
        XCTAssertEqual(completed.statusText, "Done")
        XCTAssertEqual(completed.phase, "Completed")
        XCTAssertEqual(completed.statusPillKind, .success)
        XCTAssertEqual(completed.progress, 1)
        XCTAssertEqual(DownloadJobRowActionPresentation.primaryActionTitle(for: completed.state), "Open Folder")

        let failed = DownloadJobRowModel(
            record: downloadPresentationRecord(
                state: .failed,
                lastError: "ERROR: Unable to extract video data"
            ),
            progress: nil,
            statusText: nil
        )
        XCTAssertEqual(failed.statusText, "Failed")
        XCTAssertEqual(failed.phase, "Failed during extractor step")
        XCTAssertEqual(failed.inlineError, "ERROR: Unable to extract video data")
        XCTAssertEqual(failed.errorTooltip, "ERROR: Unable to extract video data")
        XCTAssertEqual(failed.statusPillKind, .danger)
        XCTAssertEqual(DownloadJobRowActionPresentation.primaryActionTitle(for: failed.state), "Retry")
    }

    func testDownloadsQueuePresentationKeepsFailedRowsRetryableAndExcludesCompletedRows() {
        let failed = downloadPresentationRecord(state: .failed)
        let completed = downloadPresentationRecord(state: .completed)

        XCTAssertTrue(DownloadsListFilter.activeQueue.includes(.failed))
        XCTAssertFalse(DownloadsListFilter.activeQueue.includes(.completed))
        XCTAssertEqual(DownloadsQueuePresentation.visibleRows([failed, completed], filter: .activeQueue).map(\.id), [failed.id])
        XCTAssertTrue(DownloadsQueuePresentation.showsFailedBanner(rows: [failed, completed], filter: .activeQueue))
        XCTAssertTrue(DownloadJobRowActionPresentation.isRetryable(failed.state))
    }

    func testCompletedDownloadFolderActionsResolveFinderFolderURLs() {
        let completed = downloadPresentationRecord(state: .completed)

        XCTAssertEqual(
            DownloadFolderOpenTarget.completedRecord(completed).folderURL.path,
            "/Users/mingjie.wang/Downloads/MacAllYouNeed"
        )
        XCTAssertEqual(
            DownloadFolderOpenTarget.defaultDownloadFolder(downloadDir: "/Users/mingjie.wang/Movies").folderURL.path,
            "/Users/mingjie.wang/Movies"
        )
    }

    func testFailedDownloadRowExposesRowLevelHoverHelpEvenWithoutCapturedError() {
        let capturedError = DownloadJobRowModel(
            record: downloadPresentationRecord(
                state: .failed,
                lastError: "ERROR: Unable to extract video data"
            ),
            progress: nil,
            statusText: nil
        )
        let missingError = DownloadJobRowModel(
            record: downloadPresentationRecord(state: .failed),
            progress: nil,
            statusText: nil
        )
        let running = DownloadJobRowModel(
            record: downloadPresentationRecord(state: .running),
            progress: nil,
            statusText: nil
        )

        XCTAssertEqual(
            DownloadJobRowHoverPresentation.rowHelpText(for: capturedError),
            "ERROR: Unable to extract video data"
        )
        XCTAssertEqual(
            DownloadJobRowHoverPresentation.rowHelpText(for: missingError),
            "No captured yt-dlp error is available for this failed download. Retry the row to capture fresh stderr details."
        )
        XCTAssertNil(DownloadJobRowHoverPresentation.rowHelpText(for: running))
        XCTAssertEqual(DownloadJobRowHoverPresentation.inlineErrorLineLimit(isHovering: false), 1)
        XCTAssertNil(DownloadJobRowHoverPresentation.inlineErrorLineLimit(isHovering: true))
    }

    func testDownloadsEmptyStatePresentationShowsNeutralActionsForQueue() {
        let emptyState = DownloadsEmptyStatePresentation.model(for: .activeQueue)

        XCTAssertEqual(emptyState.title, "No downloads queued")
        XCTAssertEqual(emptyState.subtitle, "Add a URL, paste with ⌘V, or send a link from the optional Chrome Companion.")
        XCTAssertEqual(emptyState.primaryActionTitle, "Add URL")
        XCTAssertEqual(emptyState.secondaryActionTitle, "Paste URL")
    }

    func testDownloadsSettingsPresentationIncludesRecoveryFilenameCookieAndAssetRows() {
        XCTAssertEqual(DownloadsSettingsPresentation.interruptedRecoveryTitle, "Resume interrupted downloads on launch")
        XCTAssertEqual(DownloadsSettingsPresentation.interruptedRecoveryStatusText, "Automatic")
        XCTAssertEqual(DownloadsSettingsPresentation.filenameExampleActionTitle, "Copy")
        XCTAssertEqual(DownloadsSettingsPresentation.cookieProfileTitle, "Cookie profiles")
        XCTAssertEqual(
            DownloadsSettingsPresentation.cookieProfileSubtitle,
            "Use Browser Auto by default. Chrome Companion is optional for exact tab-session cookie sync."
        )
        XCTAssertEqual(DownloadsSettingsPresentation.bundledAssetsTitle, "Bundled downloader assets")
        XCTAssertEqual(DownloadConcurrencyControlPresentation.range, 1...10)
        XCTAssertEqual(
            DownloadFilenameTemplatePreset.example(for: "%(title)s - %(id)s.%(ext)s"),
            "My Video - abc123.mp4"
        )
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

    func testFolderPreviewMainPageHidesRedundantSingleSettingsTab() {
        XCTAssertFalse(FunctionPageShellPresentation.showsTabStrip(tabCount: Array(FolderPreviewFunctionTab.allCases).count))
        XCTAssertTrue(FunctionPageShellPresentation.showsTabStrip(tabCount: Array(DownloadsFunctionTab.allCases).count))
    }

    func testFolderPreviewSettingsExposeCascadeToggle() {
        XCTAssertEqual(FolderPreviewMainPagePresentation.settingsRowTitles, [
            "Include hidden files",
            "Cascade folders",
            "Maximum entries"
        ])
    }

    func testSnippetsSettingsDoesNotShowStaticTriggerFormatRow() {
        XCTAssertEqual(SnippetsSettingsPresentation.visibleRowTitles, ["Expansion mode", "Accessibility", "Shortcut"])
        XCTAssertFalse(SnippetsSettingsPresentation.visibleRowTitles.contains("Trigger format"))
    }

    func testSnippetExpansionModeUsesSharedSegmentedTabContract() {
        XCTAssertEqual(SnippetExpansionMode.allCases.map(\.title), ["Auto", "Tab", "Off"])
        XCTAssertEqual(SnippetExpansionMode.allCases.map(\.symbolName), [
            "bolt.fill",
            "keyboard",
            "pause.circle"
        ])
    }

    func testSnippetsListUsesLocalDockModelSource() {
        XCTAssertTrue(SnippetsListPresentation.usesLocalDockModelSource)
    }

    func testSnippetsMenuRowsShowBodyPreviewAndKeepTriggerVisible() {
        let snippet = Snippet(name: "Email", body: "mingjie.wang@uber.com", trigger: ";email")

        XCTAssertTrue(SnippetsListPresentation.menuRowsShowBodyPreview)
        XCTAssertTrue(SnippetsListPresentation.menuRowsKeepTriggerVisible)
        XCTAssertEqual(SnippetsListPresentation.menuBodyPreview(for: snippet), "mingjie.wang@uber.com")
    }

    func testSnippetsMenuBodyPreviewNormalizesMultilineText() {
        let snippet = Snippet(name: "Signature", body: "Best,\nMingjie", trigger: ";sig")

        XCTAssertEqual(SnippetsListPresentation.menuBodyPreview(for: snippet), "Best, Mingjie")
    }

    func testCommandCenterFooterReflectsSelectedTab() {
        XCTAssertEqual(
            CommandCenterFooterPresentation.model(for: .clipboard),
            CommandCenterFooterModel(
                shortcutText: "⌘⇧V",
                label: "clipboard dock",
                openButtonTitle: "Open Clipboard",
                showsCapturePause: true
            )
        )
        XCTAssertEqual(
            CommandCenterFooterPresentation.model(for: .voice, voiceShortcut: "⌃⌥Space"),
            CommandCenterFooterModel(
                shortcutText: "⌃⌥Space",
                label: "transcript history",
                openButtonTitle: "Open Voice",
                showsCapturePause: false
            )
        )
        XCTAssertEqual(
            CommandCenterFooterPresentation.model(for: .downloads),
            CommandCenterFooterModel(
                shortcutText: nil,
                label: "download queue",
                openButtonTitle: "Open Downloads",
                showsCapturePause: false
            )
        )
        XCTAssertEqual(
            CommandCenterFooterPresentation.model(for: .layouts),
            CommandCenterFooterModel(
                shortcutText: nil,
                label: "window snap",
                openButtonTitle: "Open Window Layouts",
                showsCapturePause: false
            )
        )
    }

    func testClipboardFunctionTabMigratesLegacySnippetsSelection() {
        XCTAssertEqual(ClipboardFunctionTab.storedSelection("library"), .snippets)
    }

    func testClipboardFunctionTabMigratesLegacyRulesSelection() {
        XCTAssertEqual(ClipboardFunctionTab.storedSelection("rules"), .settings)
    }

    func testEveryFunctionTabHasStableStorageKey() {
        XCTAssertEqual(ClipboardFunctionTab.storageKey, "main.clipboard.selectedTab")
        XCTAssertEqual(VoiceFunctionTab.storageKey, "main.voice.selectedTab")
        XCTAssertEqual(DownloadsFunctionTab.storageKey, "main.downloads.selectedTab")
        XCTAssertEqual(FolderPreviewFunctionTab.storageKey, "main.folderPreview.selectedTab")
        XCTAssertEqual(SnippetsFunctionTab.storageKey, "main.snippets.selectedTab")
    }

    func testWindowControlPresentationUsesFirstClassDestinationsInsteadOfNestedTabs() {
        XCTAssertEqual(WindowControlPagePresentation.firstClassDestinations, [
            .windowLayouts,
            .grabAnywhere
        ])
        XCTAssertFalse(WindowControlPagePresentation.showsCombinedTabbedPage)
        XCTAssertFalse(WindowControlPagePresentation.usesSharedSegmentedTabs)
        XCTAssertFalse(WindowControlPagePresentation.usesRawSegmentedPicker)
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
            .voiceReminders,
            .downloads,
            .folderPreview,
            .aiFileOrganizer,
            .windowLayouts,
            .grabAnywhere,
            .dockPreviews
        ])
        XCTAssertEqual(tiles.map(\.title), [
            "Clipboard",
            "Voice",
            "Voice Reminders",
            "Downloads",
            "Enhanced Finder",
            "AI File Organizer",
            "Window Layouts",
            "Window Grab",
            "Dock Hover Previews"
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
            "Capture, search, pin, paste, and expand snippets.",
            "Dictate into any app with local speech recognition.",
            "Speak a task and save it directly to Apple Reminders.",
            "Download media and manage saved files.",
            "Quick Look previews, browse folder, and visit history.",
            "Rename and re-file messy folders using on-device content extraction.",
            "Arrange, snap, and restore windows.",
            "Move windows by holding a modifier and dragging.",
            "See window thumbnails when hovering an app's Dock icon."
        ])
        XCTAssertFalse(tiles.map(\.detail).contains("1 queue item"))
    }

    func testDashboardToolTilesOnlyShowUsefulNumericMetrics() {
        let tiles = DashboardToolTilePresentation.dashboardTiles(
            clipboardCount: 30,
            downloadsQueueCount: 0
        )

        XCTAssertEqual(tiles.map(\.metric), ["30", nil, nil, nil, "0", nil, nil, nil, nil])
    }

    func testDashboardWindowLayoutTileSurfacesOnlyActionableStatus() {
        var enabledSettings = WindowControlSettings.default
        enabledSettings.enabled = true

        let offTile = DashboardToolTilePresentation.dashboardTiles(
            clipboardCount: 0,
            downloadsQueueCount: 0,
            windowControlSettings: .default,
            windowControlAXTrusted: false
        ).first { $0.destination == .windowLayouts }
        let needsAccessibilityTile = DashboardToolTilePresentation.dashboardTiles(
            clipboardCount: 0,
            downloadsQueueCount: 0,
            windowControlSettings: enabledSettings,
            windowControlAXTrusted: false
        ).first { $0.destination == .windowLayouts }
        let readyTile = DashboardToolTilePresentation.dashboardTiles(
            clipboardCount: 0,
            downloadsQueueCount: 0,
            windowControlSettings: enabledSettings,
            windowControlAXTrusted: true
        ).first { $0.destination == .windowLayouts }

        XCTAssertEqual(offTile?.statusText, "Off")
        XCTAssertEqual(needsAccessibilityTile?.statusText, "Needs Accessibility")
        XCTAssertNil(readyTile?.statusText)
    }

    func testDashboardGrabAnywhereTileSurfacesOnlyActionableStatus() {
        var enabledSettings = WindowControlSettings.default
        enabledSettings.enabled = true
        enabledSettings.dragAnywhereEnabled = true

        var disabledDragSettings = enabledSettings
        disabledDragSettings.dragAnywhereEnabled = false

        let offTile = DashboardToolTilePresentation.dashboardTiles(
            clipboardCount: 0,
            downloadsQueueCount: 0,
            windowControlSettings: disabledDragSettings,
            windowControlAXTrusted: true
        ).first { $0.destination == .grabAnywhere }
        let needsAccessibilityTile = DashboardToolTilePresentation.dashboardTiles(
            clipboardCount: 0,
            downloadsQueueCount: 0,
            windowControlSettings: enabledSettings,
            windowControlAXTrusted: false
        ).first { $0.destination == .grabAnywhere }
        let readyTile = DashboardToolTilePresentation.dashboardTiles(
            clipboardCount: 0,
            downloadsQueueCount: 0,
            windowControlSettings: enabledSettings,
            windowControlAXTrusted: true
        ).first { $0.destination == .grabAnywhere }

        XCTAssertEqual(offTile?.statusText, "Off")
        XCTAssertEqual(needsAccessibilityTile?.statusText, "Needs Accessibility")
        XCTAssertNil(readyTile?.statusText)
    }

    func testDashboardVoiceFooterDoesNotShowIdleReadyStatus() {
        XCTAssertNil(DashboardVoiceStatusPresentation.footerStatus(for: .idle))
        XCTAssertEqual(
            DashboardVoiceStatusPresentation.footerStatus(for: .recording),
            DashboardVoiceStatusPresentation.Status(text: "Listening", kind: .progress)
        )
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
        XCTAssertNil(MainSidebarBadgePresentation.badgeText(for: .windowLayouts, records: records))
        XCTAssertNil(MainSidebarBadgePresentation.badgeText(for: .grabAnywhere, records: records))
        XCTAssertNil(MainSidebarBadgePresentation.badgeText(for: .downloads, records: [downloadRecord(state: .queued)]))
    }

    func testSidebarDestinationsKeepDisabledFeaturesVisible() {
        XCTAssertEqual(
            MainSidebarDestinationPresentation.renderedDestinations(),
            MainAppDestination.primarySidebarDestinations
        )
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
            nil,
            "Space",
            nil,
            nil,
            nil,
            nil
        ])
    }

    func testDashboardWindowLayoutTileDoesNotExposePerActionShortcutWall() {
        let tiles = DashboardToolTilePresentation.dashboardTiles(
            clipboardCount: 30,
            downloadsQueueCount: 0,
            hotkeys: [
                .windowLeftHalf: [.defaultClipboard],
                .windowRightHalf: [.defaultDownload],
                .windowMaximize: [.defaultFolder]
            ]
        )
        let windowsTile = tiles.first { $0.destination == .windowLayouts }

        XCTAssertEqual(windowsTile?.title, "Window Layouts")
        XCTAssertEqual(windowsTile?.detail, "Arrange, snap, and restore windows.")
        XCTAssertNil(windowsTile?.shortcutDisplay)
    }

    func testDashboardTileOpenRouteOpensWindowFeaturesDirectly() {
        XCTAssertNil(DashboardToolOpenNavigation.route(for: .windowLayouts).tabStorageKey)
        XCTAssertNil(DashboardToolOpenNavigation.route(for: .grabAnywhere).tabStorageKey)
        XCTAssertNil(DashboardToolOpenNavigation.route(for: .clipboard).tabStorageKey)
    }

    func testMainHotkeyPresentationShowsOffForExplicitlyDisabledAction() {
        XCTAssertEqual(
            MainHotkeyPresentation.display(for: .clipboard, in: [.clipboard: []]),
            "Off"
        )
    }

    func testMainHotkeyPresentationFallsBackToMissingDefaultAndOffWhenNoDefaultExists() {
        XCTAssertEqual(
            MainHotkeyPresentation.display(for: .clipboard, in: [:]),
            "⇧⌘V"
        )
        XCTAssertEqual(
            MainHotkeyPresentation.display(for: .windowTopLeft, in: [:]),
            "Off"
        )
    }

    func testHotkeysSettingsPresentationGroupsActionsByFeature() {
        XCTAssertEqual(HotkeysSettingsPresentation.groups.map(\.title), [
            "Core tools",
            "Window Layouts"
        ])
        XCTAssertEqual(HotkeysSettingsPresentation.groups.first?.actions, [
            .clipboard,
            .browseFolder,
            .finderHistory
        ])
        XCTAssertTrue(HotkeysSettingsPresentation.groups[1].actions.contains(.windowLeftHalf))
        XCTAssertTrue(HotkeysSettingsPresentation.groups[1].actions.contains(.windowRestore))
    }

    func testHotkeysSettingsPresentationCanAddCustomTriggerForDefaultDisabledAction() {
        XCTAssertNil(HotkeyAction.windowTopLeft.primaryDefaultDescriptor)
        XCTAssertTrue(HotkeysSettingsPresentation.canAddTrigger(to: []))
        XCTAssertEqual(
            HotkeysSettingsPresentation.seedDescriptor(for: .windowTopLeft),
            HotkeysSettingsPresentation.customTriggerSeedDescriptor
        )
    }

    func testHotkeysSettingsPresentationKeepsNewTriggerPendingUntilRecorded() {
        let stored: [HotkeyDescriptor] = []
        let pending = HotkeysSettingsPresentation.pendingDescriptorsAfterAdding(
            action: .windowTopLeft,
            storedDescriptors: stored,
            pendingDescriptors: []
        )

        XCTAssertEqual(stored, [])
        XCTAssertEqual(pending, [HotkeysSettingsPresentation.customTriggerSeedDescriptor])
        XCTAssertEqual(
            HotkeysSettingsPresentation.displayedDescriptors(stored: stored, pending: pending),
            [HotkeysSettingsPresentation.customTriggerSeedDescriptor]
        )
    }

    func testHotkeysSettingsPresentationAllowsOnlyOnePendingTriggerPerAction() {
        let pending = [HotkeysSettingsPresentation.customTriggerSeedDescriptor]

        XCTAssertEqual(
            HotkeysSettingsPresentation.pendingDescriptorsAfterAdding(
                action: .windowTopLeft,
                storedDescriptors: [],
                pendingDescriptors: pending
            ),
            pending
        )
    }

    func testHotkeysSettingsPresentationCanRemoveOnlyTriggerToDisableAction() {
        XCTAssertEqual(
            HotkeysSettingsPresentation.descriptorsAfterRemoving(index: 0, from: [.defaultClipboard]),
            []
        )
    }

    func testHotkeysSettingsPresentationDoesNotOfferNoopAddAtLimit() {
        XCTAssertFalse(
            HotkeysSettingsPresentation.canAddTrigger(to: [
                .defaultClipboard,
                .defaultFolder,
                .defaultDownload
            ])
        )
    }

    func testHotkeysSettingsPresentationDisablesResetWhenActionHasNoDefault() {
        let descriptor = HotkeyDescriptor(keyCode: 18, modifiers: [.control, .option])

        XCTAssertEqual(
            HotkeysSettingsPresentation.resetDescriptor(for: .windowTopLeft, current: descriptor),
            descriptor
        )
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
        XCTAssertEqual(DashboardRenderingPresentation.toolCardHeight, 170)
    }

    func testMainWindowRootTypeErasesDetailViews() {
        XCTAssertTrue(MainWindowRootPresentation.usesTypeErasedDetailViews)
    }

    func testMainWindowRootObservesFeatureStatePublisherForSidebarDisabledState() {
        XCTAssertTrue(MainWindowRootPresentation.observesFeatureStatePublisher)
    }

    func testMainWindowRootMakesDisabledSidebarItemsNonClickable() {
        XCTAssertTrue(MainWindowRootPresentation.disabledSidebarItemsAreNonClickable)
    }

    func testMainWindowRootMakesDisabledSidebarItemsVisuallyInert() {
        XCTAssertTrue(MainWindowRootPresentation.disabledSidebarItemsIgnoreHover)
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
                destination: .clipboard,
                tabStorageKey: ClipboardFunctionTab.storageKey,
                tabRawValue: ClipboardFunctionTab.snippets.rawValue
            )
        )
        XCTAssertEqual(
            DashboardToolSettingsNavigation.route(for: .windowLayouts),
            DashboardToolSettingsRoute(destination: .windowLayouts, tabStorageKey: nil, tabRawValue: nil)
        )
        XCTAssertEqual(
            DashboardToolSettingsNavigation.route(for: .grabAnywhere),
            DashboardToolSettingsRoute(destination: .grabAnywhere, tabStorageKey: nil, tabRawValue: nil)
        )
    }

    func testVoiceModelsNavigationRoutesToVoiceModelsTab() {
        XCTAssertEqual(
            VoiceModelsNavigation.route(),
            DashboardToolSettingsRoute(
                destination: .voice,
                tabStorageKey: VoiceFunctionTab.storageKey,
                tabRawValue: VoiceFunctionTab.models.rawValue
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
        XCTAssertNil(
            MainToolHeaderShortcutModel.display(for: .snippets, hotkeys: hotkeys, voiceSettings: voiceSettings)
        )
        XCTAssertEqual(
            MainToolHeaderShortcutModel.display(for: .voice, hotkeys: hotkeys, voiceSettings: voiceSettings),
            "⌥⌘Space"
        )
        XCTAssertEqual(
            MainToolHeaderShortcutModel.display(for: .folderPreview, hotkeys: hotkeys, voiceSettings: voiceSettings),
            "Space"
        )
        XCTAssertNil(
            MainToolHeaderShortcutModel.display(for: .windowLayouts, hotkeys: hotkeys, voiceSettings: voiceSettings)
        )
        XCTAssertNil(
            MainToolHeaderShortcutModel.display(for: .grabAnywhere, hotkeys: hotkeys, voiceSettings: voiceSettings)
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
            FunctionTabFlow.direction(from: .settings, to: .snippets, in: tabs),
            .backward
        )
        XCTAssertNil(FunctionTabFlow.direction(from: .snippets, to: .snippets, in: tabs))
    }

    func testTabFlowContentInsertionOffsetIsSmallAndDirectional() {
        XCTAssertEqual(FunctionTabFlow.contentInsertionOffset(for: .forward), 18)
        XCTAssertEqual(FunctionTabFlow.contentInsertionOffset(for: .backward), -18)
    }
}

private func downloadPresentationRecord(
    state: DownloadState,
    bytesDownloaded: Int64 = 0,
    bytesTotal: Int64? = nil,
    lastError: String? = nil
) -> DownloadRecord {
    var record = DownloadRecord(
        url: "https://www.youtube.com/watch?v=IwQFzy9kUFw",
        title: "Fallback title",
        destinationPath: "/Users/mingjie.wang/Downloads/MacAllYouNeed/video.mp4",
        state: state
    )
    record.videoTitle = "Bilibili member-only livestream archive"
    record.channelName = "Creator Channel"
    record.durationSeconds = 4324
    record.bytesDownloaded = bytesDownloaded
    record.bytesTotal = bytesTotal
    record.lastError = lastError
    return record
}
