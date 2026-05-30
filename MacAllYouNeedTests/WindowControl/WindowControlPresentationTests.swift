@testable import MacAllYouNeed
import AppKit
import Carbon.HIToolbox
import Core
import Platform
import XCTest

final class WindowControlPresentationTests: XCTestCase {
    func testWindowControlPagePresentationUsesSeparateMainDestinations() {
        XCTAssertEqual(WindowControlPagePresentation.firstClassDestinations, [
            .windowLayouts,
            .grabAnywhere
        ])
        XCTAssertFalse(WindowControlPagePresentation.showsCombinedTabbedPage)
        XCTAssertFalse(WindowControlPagePresentation.usesSharedSegmentedTabs)
        XCTAssertFalse(WindowControlPagePresentation.usesRawSegmentedPicker)
    }

    func testWindowControlSettingsPresentationShowsExpectedSectionsAcrossSplitPages() {
        XCTAssertEqual(WindowControlSettingsPresentation.sectionTitles, [
            "Window Layouts",
            "Layout Shortcuts",
            "Edge Snap",
            "Window Grab",
            "Double-Click Layout",
            "Shared Ignored Apps",
            "Shared Diagnostics"
        ])
        XCTAssertTrue(WindowControlSettingsPresentation.editsShortcutsInToolSettings)
    }

    func testWindowControlSettingsCanEditDefaultDisabledActionShortcutsInTool() {
        XCTAssertTrue(WindowControlSettingsPresentation.canEditShortcut(for: .windowTopLeft))
        XCTAssertEqual(
            WindowControlSettingsPresentation.seedDescriptor(for: .windowTopLeft),
            WindowControlSettingsPresentation.customShortcutSeedDescriptor
        )
        XCTAssertFalse(HotkeyAction.windowTopLeft.windowControlSubtitle.contains("Global Hotkeys"))
    }

    func testWindowControlShortcutResetBaselinePendingVsRegistered() {
        let seed = WindowControlSettingsPresentation.seedDescriptor(for: .windowTopLeft)
        let changed = HotkeyDescriptor(keyCode: UInt32(kVK_ANSI_B), modifiers: [.control])

        XCTAssertTrue(
            WindowControlSettingsPresentation.isPendingShortcutOnly(
                storedDescriptors: [],
                pendingDescriptor: seed
            )
        )
        XCTAssertFalse(
            WindowControlSettingsPresentation.isPendingShortcutOnly(
                storedDescriptors: [changed],
                pendingDescriptor: nil
            )
        )

        XCTAssertEqual(
            WindowControlSettingsPresentation.resetBaselineDescriptor(
                for: .windowTopLeft,
                current: changed,
                isPendingOnly: true
            ),
            seed
        )
        XCTAssertEqual(
            WindowControlSettingsPresentation.resetBaselineDescriptor(
                for: .windowTopLeft,
                current: changed,
                isPendingOnly: false
            ),
            changed
        )

        let leftDefault = HotkeyAction.windowLeftHalf.primaryDefaultDescriptor!
        XCTAssertEqual(
            WindowControlSettingsPresentation.resetBaselineDescriptor(
                for: .windowLeftHalf,
                current: leftDefault,
                isPendingOnly: true
            ),
            leftDefault
        )
    }

    func testWindowControlShortcutControlHelpCopy() {
        XCTAssertEqual(
            WindowControlSettingsPresentation.closeHelp(isPendingOnly: true),
            "Cancel"
        )
        XCTAssertEqual(
            WindowControlSettingsPresentation.closeHelp(isPendingOnly: false),
            "Turn off shortcut"
        )
        XCTAssertEqual(
            WindowControlSettingsPresentation.resetHelp(for: .windowTopLeft, isPendingOnly: true),
            "Revert to starter shortcut"
        )
        XCTAssertEqual(
            WindowControlSettingsPresentation.resetHelp(for: .windowLeftHalf, isPendingOnly: false),
            "Reset to default"
        )
    }

    func testWindowGestureModifierPickerExposesFnAndSideSpecificModifiers() {
        // The picker now wraps HotkeyRecorderControl and captures modifiers
        // via ModifierTapShortcut.Key. Verify the underlying enum still
        // includes Fn + side-specific modifiers so the picker can map them.
        let supported = Set(ModifierTapShortcut.Key.allCases)
        XCTAssertTrue(supported.contains(.fn))
        XCTAssertTrue(supported.contains(.leftControl))
        XCTAssertTrue(supported.contains(.rightControl))
        XCTAssertTrue(supported.contains(.leftOption))
        XCTAssertTrue(supported.contains(.rightOption))
        XCTAssertTrue(supported.contains(.leftCommand))
        XCTAssertTrue(supported.contains(.rightCommand))
        XCTAssertTrue(supported.contains(.leftShift))
        XCTAssertTrue(supported.contains(.rightShift))
    }

    func testActionsTabRoutesShortcutEditsToSettings() {
        XCTAssertEqual(
            WindowControlActionPresentation.editRoute(for: .windowTopLeft),
            .windowLayouts
        )
        XCTAssertEqual(
            WindowControlActionPresentation.editRoute(for: .windowLeftHalf),
            .windowLayouts
        )
    }

    func testSnapOverlayPresentationUsesSharedPanelMetricsWithoutGlow() {
        if #available(macOS 26.0, *) {
            XCTAssertEqual(WindowSnapOverlayPresentation.cornerRadius, 16)
        } else if #available(macOS 11.0, *) {
            XCTAssertEqual(WindowSnapOverlayPresentation.cornerRadius, 10)
        } else {
            XCTAssertEqual(WindowSnapOverlayPresentation.cornerRadius, 5)
        }
        XCTAssertTrue(WindowSnapOverlayPresentation.respectsReduceMotion)
        XCTAssertFalse(WindowSnapOverlayPresentation.usesGlow)
        XCTAssertTrue(WindowSnapOverlayPresentation.usesNeutralPalette)
        XCTAssertFalse(WindowSnapOverlayPresentation.usesProgressAccent)
        XCTAssertTrue(WindowSnapOverlayPresentation.usesFixedBlackOverlay)
        XCTAssertTrue(WindowSnapOverlayPresentation.cancelsStaleDismissAnimation)
        XCTAssertEqual(WindowSnapOverlayPresentation.visibleAlpha, 0.30, accuracy: 0.001)
        XCTAssertEqual(WindowSnapOverlayPresentation.borderWidth, 2)
        XCTAssertEqual(WindowSnapOverlayPresentation.fillColor, .black)
        XCTAssertEqual(WindowSnapOverlayPresentation.borderColor, .lightGray)
        XCTAssertEqual(WindowSnapOverlayPresentation.fillOpacity, 1.0, accuracy: 0.001)
        XCTAssertEqual(WindowSnapOverlayPresentation.strokeOpacity, 1.0, accuracy: 0.001)
        XCTAssertFalse(WindowSnapOverlayPresentation.acceptsMouseEvents)
        XCTAssertTrue(WindowSnapOverlayPresentation.styleMask.contains(.borderless))
        XCTAssertTrue(WindowSnapOverlayPresentation.styleMask.contains(.nonactivatingPanel))
    }

    @MainActor
    func testWindowControlDiagnosticsPresentationExposesRuntimeFields() {
        let result = WindowMovementResult(
            action: .leftHalf,
            status: .moved,
            originalFrame: .zero,
            proposedFrame: CGRect(x: 0, y: 0, width: 500, height: 700),
            resultingFrame: CGRect(x: 0, y: 0, width: 500, height: 700)
        )

        XCTAssertEqual(WindowControlDiagnosticsPresentation.eventTapText(for: .active), "Running")
        XCTAssertEqual(WindowControlDiagnosticsPresentation.lastActionText(.leftHalf), "Left half")
        XCTAssertEqual(WindowControlDiagnosticsPresentation.lastResultText(result), "Moved")
    }
}
