@testable import MacAllYouNeed
import AppKit
import XCTest

final class SettingsDestinationTests: XCTestCase {
    func testMapsLegacyTabKeysToSidebarDestinations() {
        XCTAssertEqual(SettingsDestination.legacySelection("general"), .general)
        XCTAssertEqual(SettingsDestination.legacySelection("clipboard"), .clipboard)
        XCTAssertEqual(SettingsDestination.legacySelection("downloads"), .downloads)
        XCTAssertEqual(SettingsDestination.legacySelection("folderPreview"), .folderPreview)
        XCTAssertEqual(SettingsDestination.legacySelection("hotkeys"), .hotkeys)
        XCTAssertEqual(SettingsDestination.legacySelection("shortcuts"), .snippets)
        XCTAssertEqual(SettingsDestination.legacySelection("privacy"), .clipboard)
        XCTAssertEqual(SettingsDestination.legacySelection("storage"), .general)
        XCTAssertEqual(SettingsDestination.legacySelection("search"), .search)
        XCTAssertEqual(SettingsDestination.legacySelection("appearance"), .general)
        XCTAssertEqual(SettingsDestination.legacySelection("advanced"), .advanced)
        XCTAssertEqual(SettingsDestination.legacySelection("voice"), .voice)
    }

    func testMapsDeferredSyncAndSpikeToStableDestinations() {
        XCTAssertEqual(SettingsDestination.legacySelection("sync"), .advanced)
        XCTAssertEqual(SettingsDestination.legacySelection("voiceSpike"), .voice)
    }

    func testFallsBackToClipboardForUnknownLegacyKey() {
        XCTAssertEqual(SettingsDestination.legacySelection("missing"), .clipboard)
    }

    func testSystemOnlySettingsGroupKeepsOnlySystemDestinations() {
        let destinations = SettingsSidebarGroup.systemOnly.flatMap(\.destinations)

        XCTAssertEqual(destinations, [.general, .permissions, .advanced])
    }

    func testSettingsGroupsDoNotExposePrivacyAsASeparateDestination() {
        let rawDestinations = SettingsSidebarGroup.all.flatMap(\.destinations).map(\.rawValue)

        XCTAssertFalse(rawDestinations.contains("privacy"))
    }

    func testDownloadFilenameTemplatePresetMatchesKnownTemplates() {
        XCTAssertEqual(
            DownloadFilenameTemplatePreset.matching("%(title)s [%(id)s].%(ext)s"),
            .titleAndID
        )
        XCTAssertEqual(
            DownloadFilenameTemplatePreset.matching("%(title)s - %(uploader)s.%(ext)s"),
            .titleAndChannel
        )
    }

    func testDownloadFilenameTemplatePresetTreatsUnknownPatternAsCustom() {
        XCTAssertNil(DownloadFilenameTemplatePreset.matching("%(playlist_index)s - %(title)s.%(ext)s"))
    }

    func testAppearanceModeMapsToNativeAppearanceNames() {
        XCTAssertNil(AppAppearanceMode.system.appearanceName)
        XCTAssertEqual(AppAppearanceMode.light.appearanceName, .aqua)
        XCTAssertEqual(AppAppearanceMode.dark.appearanceName, .darkAqua)
    }

    func testAppearanceModeFallsBackToSystemForUnknownStoredValue() {
        XCTAssertEqual(AppAppearanceMode.storedSelection(nil), .system)
        XCTAssertEqual(AppAppearanceMode.storedSelection("missing"), .system)
        XCTAssertEqual(AppAppearanceMode.storedSelection("dark"), .dark)
    }

    func testGeneralIconVisibilityRowsUseEditableCheckboxes() {
        XCTAssertEqual(AppChromeVisibilityPresentation.dockIconControl, .checkbox)
        XCTAssertEqual(AppChromeVisibilityPresentation.menuBarIconControl, .checkbox)
        XCTAssertFalse(AppChromeVisibilityPresentation.dockIconUsesStatusPill)
        XCTAssertFalse(AppChromeVisibilityPresentation.menuBarIconUsesStatusPill)
    }

    func testAppChromeVisibilityDefaultsToVisibleWhenUnset() {
        let suiteName = "AppChromeVisibility-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(AppChromeVisibilitySettings.dockIconVisible(defaults: defaults))
        XCTAssertTrue(AppChromeVisibilitySettings.menuBarIconVisible(defaults: defaults))
    }

    func testAppChromeVisibilityRepairsStateWhenBothEntrypointsAreHidden() {
        let suiteName = "AppChromeVisibility-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: AppChromeVisibilitySettings.dockIconVisibleKey)
        defaults.set(false, forKey: AppChromeVisibilitySettings.menuBarIconVisibleKey)

        AppChromeVisibilitySettings.ensureVisibleEntrypoint(defaults: defaults)

        XCTAssertTrue(AppChromeVisibilitySettings.dockIconVisible(defaults: defaults))
        XCTAssertFalse(AppChromeVisibilitySettings.menuBarIconVisible(defaults: defaults))
    }

    func testNumericSettingsInputUsesOnlyPlainTextField() {
        XCTAssertEqual(
            MAYNNumericInputPresentation.supplementaryControls(presets: [50, 100, 250]),
            []
        )
        XCTAssertEqual(
            MAYNNumericInputPresentation.supplementaryControls(presets: []),
            []
        )
    }

    func testNumericSettingsInputCommitsTypedValuesWithoutStepperControls() {
        XCTAssertEqual(
            MAYNNumericInputPresentation.committedValue(from: "42", currentValue: 10, range: 1...100),
            MAYNNumericInputCommit(value: 42, draft: "42")
        )
        XCTAssertEqual(
            MAYNNumericInputPresentation.committedValue(from: "999", currentValue: 10, range: 1...100),
            MAYNNumericInputCommit(value: 100, draft: "100")
        )
        XCTAssertEqual(
            MAYNNumericInputPresentation.committedValue(from: "abc", currentValue: 10, range: 1...100),
            MAYNNumericInputCommit(value: 10, draft: "10")
        )
    }

    func testClipboardDockHeightUsesSliderAsOnlyEditableControl() {
        XCTAssertTrue(ClipboardDockHeightControlPresentation.usesSliderAsOnlyInput)
        XCTAssertFalse(ClipboardDockHeightControlPresentation.showsEditableValueInput)
        XCTAssertTrue(ClipboardDockHeightControlPresentation.showsReadOnlyValueLabel)
    }

    func testDownloadConcurrencyUsesBoundedDropdownOptions() {
        XCTAssertTrue(DownloadConcurrencyControlPresentation.usesDropdown)
        XCTAssertFalse(DownloadConcurrencyControlPresentation.allowsFreeformInput)
        XCTAssertEqual(DownloadConcurrencyControlPresentation.options, Array(1...10))
        XCTAssertEqual(DownloadConcurrencyControlPresentation.normalized(0), 1)
        XCTAssertEqual(DownloadConcurrencyControlPresentation.normalized(3), 3)
        XCTAssertEqual(DownloadConcurrencyControlPresentation.normalized(99), 10)
    }

    func testTextFocusDismissPolicyOnlyDismissesForNonTextTargets() {
        XCTAssertTrue(
            MAYNTextFocusDismissPolicy.shouldDismissTextFocus(
                isTextEditingFirstResponder: true,
                clickedTargetIsTextInput: false
            )
        )
        XCTAssertFalse(
            MAYNTextFocusDismissPolicy.shouldDismissTextFocus(
                isTextEditingFirstResponder: true,
                clickedTargetIsTextInput: true
            )
        )
        XCTAssertFalse(
            MAYNTextFocusDismissPolicy.shouldDismissTextFocus(
                isTextEditingFirstResponder: false,
                clickedTargetIsTextInput: false
            )
        )
    }

    func testTextEditingShortcutPolicyYieldsNativeCommandEditingShortcuts() {
        XCTAssertTrue(
            MAYNTextEditingShortcutPolicy.shouldYieldToFocusedTextInput(
                isTextEditingFirstResponder: true,
                keyEquivalent: "a",
                modifiers: .command
            )
        )
        XCTAssertTrue(
            MAYNTextEditingShortcutPolicy.shouldYieldToFocusedTextInput(
                isTextEditingFirstResponder: true,
                keyEquivalent: "v",
                modifiers: .command
            )
        )
        XCTAssertFalse(
            MAYNTextEditingShortcutPolicy.shouldYieldToFocusedTextInput(
                isTextEditingFirstResponder: false,
                keyEquivalent: "a",
                modifiers: .command
            )
        )
        XCTAssertFalse(
            MAYNTextEditingShortcutPolicy.shouldYieldToFocusedTextInput(
                isTextEditingFirstResponder: true,
                keyEquivalent: "a",
                modifiers: [.command, .shift]
            )
        )
    }

    func testSharedControlMetricsKeepInputsAndInlineTabsAligned() {
        XCTAssertEqual(MAYNControlMetrics.controlHeight, 30)
        XCTAssertEqual(MAYNControlMetrics.inlineTabHeight, MAYNControlMetrics.controlHeight)
        XCTAssertEqual(MAYNControlMetrics.dropdownHeight, MAYNControlMetrics.controlHeight)
        XCTAssertEqual(MAYNControlMetrics.hotkeyHeight, MAYNControlMetrics.controlHeight)
    }

    func testSharedControlMetricsExposeUnifiedCornerRadii() {
        XCTAssertEqual(MAYNControlMetrics.controlRadius, 7)
        XCTAssertEqual(MAYNControlMetrics.cardRadius, 8)
        XCTAssertEqual(MAYNControlMetrics.panelRadius, 8)
    }

    func testDropdownUsesSharedControlChromeInsteadOfNativePickerChrome() {
        XCTAssertTrue(MAYNDropdownPresentation.usesSingleSharedControlChrome)
        XCTAssertFalse(MAYNDropdownPresentation.usesNativePickerChrome)
        XCTAssertTrue(MAYNDropdownPresentation.backgroundMatchesTextField)
        XCTAssertTrue(MAYNDropdownPresentation.hidesNativeMenuIndicator)
        XCTAssertFalse(MAYNDropdownPresentation.usesBorderlessNativeMenuStyle)
        XCTAssertNil(MAYNDropdownPresentation.leadingIndicatorSymbol)
        XCTAssertEqual(MAYNDropdownPresentation.trailingIndicatorSymbol, "chevron.up.chevron.down")
    }

    func testMotionTokensExposeNamedDurationsForSwiftUIAndAppKit() {
        XCTAssertEqual(MAYNMotionDuration.press, 0.12, accuracy: 0.001)
        XCTAssertEqual(MAYNMotionDuration.hover, 0.16, accuracy: 0.001)
        XCTAssertEqual(MAYNMotionDuration.control, 0.18, accuracy: 0.001)
        XCTAssertEqual(MAYNMotionDuration.tab, 0.23, accuracy: 0.001)
        XCTAssertEqual(MAYNMotionDuration.panel, 0.28, accuracy: 0.001)
        XCTAssertEqual(MAYNMotionDuration.instruction, 0.32, accuracy: 0.001)
        XCTAssertEqual(MAYNMotionDuration.toastIn, 0.16, accuracy: 0.001)
        XCTAssertEqual(MAYNMotionDuration.toastOut, 0.22, accuracy: 0.001)
    }

    func testMotionBridgeRemovesMovementWhenReduceMotionIsEnabled() {
        XCTAssertEqual(
            MAYNMotionBridge.effectiveDuration(.panel, reduceMotion: true),
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            MAYNMotionBridge.effectiveDuration(.panel, reduceMotion: false),
            MAYNMotionDuration.panel,
            accuracy: 0.001
        )
        XCTAssertEqual(MAYNMotionBridge.translation(18, reduceMotion: true), 0)
        XCTAssertEqual(MAYNMotionBridge.translation(18, reduceMotion: false), 18)
    }

    func testClipboardCleanupThresholdDropdownUsesSimpleTimeLabels() {
        XCTAssertEqual(ClipboardCleanupThreshold.allCases.map(\.title), [
            "Day",
            "Week",
            "Month",
            "Never"
        ])
    }

    func testClipboardCleanupThresholdMapsToClearRequestDays() {
        XCTAssertEqual(ClipboardCleanupThreshold.day.days, 1)
        XCTAssertEqual(ClipboardCleanupThreshold.week.days, 7)
        XCTAssertEqual(ClipboardCleanupThreshold.month.days, 30)
        XCTAssertNil(ClipboardCleanupThreshold.never.days)
    }
}
