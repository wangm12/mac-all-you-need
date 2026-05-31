@testable import MacAllYouNeed
import AppKit
import Carbon.HIToolbox
import Platform
import SwiftUI
import XCTest

@MainActor
final class HotkeyRecorderTests: XCTestCase {
    func testHotkeyChipPresentationNormalizesEmptyDisplay() {
        XCTAssertEqual(HotkeyChipPresentation.displayText(""), "Not set")
        XCTAssertEqual(HotkeyChipPresentation.displayText("⌃⌥Space"), "⌃⌥Space")
    }

    func testHotkeyChipPresentationKeepsShortcutCharactersOnSharedBaseline() {
        XCTAssertEqual(HotkeyChipPresentation.baselineOffset(for: "⇧"), 0)
        XCTAssertEqual(HotkeyChipPresentation.baselineOffset(for: "⌘"), 0)
        XCTAssertEqual(HotkeyChipPresentation.baselineOffset(for: "V"), 0)
    }

    func testHotkeyChipPresentationKeepsWordKeysAsSingleSegment() {
        XCTAssertEqual(HotkeyChipPresentation.segments(for: "Space"), [
            .key("Space")
        ])
        XCTAssertEqual(HotkeyChipPresentation.segments(for: "⌃⌥Space"), [
            .modifier("⌃"),
            .modifier("⌥"),
            .key("Space")
        ])
        XCTAssertEqual(HotkeyChipPresentation.segments(for: "⌘⇧V"), [
            .modifier("⌘"),
            .modifier("⇧"),
            .key("V")
        ])
    }

    func testHotkeyDescriptorDisplaysArrowKeys() {
        XCTAssertEqual(
            HotkeyDescriptor(keyCode: UInt32(kVK_LeftArrow), modifiers: [.control, .option]).display,
            "⌃⌥←"
        )
        XCTAssertEqual(
            HotkeyDescriptor(keyCode: UInt32(kVK_RightArrow), modifiers: [.control, .option]).display,
            "⌃⌥→"
        )
        XCTAssertEqual(
            HotkeyDescriptor(keyCode: UInt32(kVK_UpArrow), modifiers: [.control, .option]).display,
            "⌃⌥↑"
        )
        XCTAssertEqual(
            HotkeyDescriptor(keyCode: UInt32(kVK_DownArrow), modifiers: [.control, .option]).display,
            "⌃⌥↓"
        )
    }

    func testHotkeyRecorderUsesSharedCompactChipHeight() {
        XCTAssertEqual(HotkeyRecorderControlPresentation.defaultRecorderHeight, HotkeyChipPresentation.compactHeight)
        XCTAssertEqual(HotkeyRecorderControlPresentation.defaultRecorderHeight, 24)
    }

    func testControlLayoutKeepsRecorderAnchoredWhenErrorAppearsBelow() {
        let layout = HotkeyRecorderControlPresentation.layout(
            recorderWidth: 112,
            resetWidth: 64,
            spacing: 8,
            errorWidth: 260
        )

        XCTAssertEqual(layout.containerWidth, 260)
        XCTAssertEqual(layout.controlsAlignment, .trailing)
        XCTAssertEqual(layout.errorPlacement, .belowControlsRightAligned)
    }

    func testControlLayoutDoesNotExpandForFloatingKeyboardVisualizer() {
        let idle = HotkeyRecorderControlPresentation.layout(
            recorderWidth: 112,
            resetWidth: 64,
            spacing: 8,
            errorWidth: 220,
            visualizerWidth: 700,
            isRecording: false
        )
        let recording = HotkeyRecorderControlPresentation.layout(
            recorderWidth: 112,
            resetWidth: 64,
            spacing: 8,
            errorWidth: 220,
            visualizerWidth: 700,
            isRecording: true
        )

        XCTAssertEqual(idle.containerWidth, 220)
        XCTAssertEqual(recording.containerWidth, 220)
    }

    func testFloatingKeyboardOverlayPresentationIsLargeAndMouseInteractive() {
        XCTAssertEqual(KeyboardShortcutVisualizerPresentation.width, 700)
        XCTAssertEqual(KeyboardShortcutVisualizerPresentation.keyHeight, 37)
        XCTAssertEqual(KeyboardShortcutFloatingOverlayPresentation.acceptsMouseEvents, true)
        XCTAssertTrue(KeyboardShortcutFloatingOverlayPresentation.styleMask.contains(.borderless))
        XCTAssertTrue(KeyboardShortcutFloatingOverlayPresentation.styleMask.contains(.nonactivatingPanel))
    }

    func testFloatingKeyboardOverlayCentersOnVisibleScreenFrame() {
        let origin = KeyboardShortcutFloatingOverlayPresentation.origin(
            panelSize: CGSize(width: 700, height: 300),
            visibleFrame: NSRect(x: 100, y: 80, width: 1600, height: 900)
        )

        XCTAssertEqual(origin.x, 550)
        XCTAssertEqual(origin.y, 380)
    }

    func testKeyboardVisualizerLayoutIncludesPhysicalModifierKeys() {
        let keyIDs = Set(KeyboardShortcutVisualizerPresentation.rows.flatMap { row in
            row.flatMap { key in key.ids }
        })

        XCTAssertTrue(keyIDs.contains(.fn))
        XCTAssertTrue(keyIDs.contains(.leftControl))
        XCTAssertTrue(keyIDs.contains(.rightControl))
        XCTAssertTrue(keyIDs.contains(.leftOption))
        XCTAssertTrue(keyIDs.contains(.rightOption))
        XCTAssertTrue(keyIDs.contains(.leftCommand))
        XCTAssertTrue(keyIDs.contains(.rightCommand))
        XCTAssertTrue(keyIDs.contains(.leftShift))
        XCTAssertTrue(keyIDs.contains(.rightShift))
    }

    func testKeyboardVisualizerModifierKeysUseGlyphLabels() {
        let keys = KeyboardShortcutVisualizerPresentation.rows.flatMap { $0 }
        let labelsByID = Dictionary(uniqueKeysWithValues: keys.flatMap { key in
            key.ids.map { ($0, key.label) }
        })

        XCTAssertEqual(labelsByID[.leftControl], "⌃")
        XCTAssertEqual(labelsByID[.rightControl], "⌃")
        XCTAssertEqual(labelsByID[.leftOption], "⌥")
        XCTAssertEqual(labelsByID[.rightOption], "⌥")
        XCTAssertEqual(labelsByID[.leftShift], "⇧")
        XCTAssertEqual(labelsByID[.rightShift], "⇧")
        XCTAssertEqual(labelsByID[.leftCommand], "⌘")
        XCTAssertEqual(labelsByID[.rightCommand], "⌘")
        XCTAssertEqual(labelsByID[.fn], "fn")
    }

    func testKeyboardVisualizerStateShowsPhysicalSideWhileDescriptorStaysCarbonGeneric() {
        let flags = CGEventFlags(
            rawValue: CGEventFlags.maskAlternate.rawValue | 0x00000040
        )
        let state = KeyboardShortcutVisualizerState.recording(
            keyCode: UInt16(kVK_ANSI_R),
            cgFlags: flags
        )
        let descriptor = HotkeyRecorderEventTranslator.descriptor(
            keyCode: UInt16(kVK_ANSI_R),
            cgFlags: flags,
            fallbackModifierFlags: []
        )

        XCTAssertTrue(state.pressedKeys.contains(.rightOption))
        XCTAssertFalse(state.pressedKeys.contains(.leftOption))
        XCTAssertTrue(state.pressedKeys.contains(.keyCode(UInt16(kVK_ANSI_R))))
        XCTAssertEqual(descriptor, HotkeyDescriptor(keyCode: UInt32(kVK_ANSI_R), modifiers: [.option]))
    }

    func testKeyboardRegistrationSummaryDistinguishesPhysicalSideFromCarbonRegistration() {
        let flags = CGEventFlags(
            rawValue: CGEventFlags.maskAlternate.rawValue | 0x00000040
        )
        let state = KeyboardShortcutVisualizerState.recording(
            keyCode: UInt16(kVK_ANSI_R),
            cgFlags: flags
        )

        let summary = KeyboardShortcutRegistrationSummary(state: state)

        XCTAssertEqual(summary.pressedText, "Right ⌥ + R")
        XCTAssertEqual(summary.registeredText, "⌥ + R")
        XCTAssertTrue(summary.usesGenericRegistration)
        XCTAssertEqual(summary.registrationNoticeText, "Generic")
    }

    func testKeyboardRegistrationSummaryUsesGenericNamesWhenPhysicalSideIsUnknown() {
        let state = KeyboardShortcutVisualizerState.recording(
            keyCode: UInt16(kVK_ANSI_R),
            modifierFlags: [.option]
        )

        let summary = KeyboardShortcutRegistrationSummary(state: state)

        XCTAssertTrue(state.pressedKeys.contains(.genericOption))
        XCTAssertFalse(state.pressedKeys.contains(.leftOption))
        XCTAssertEqual(summary.pressedText, "⌥ + R")
        XCTAssertEqual(summary.registeredText, "⌥ + R")
        XCTAssertFalse(summary.usesGenericRegistration)
        XCTAssertNil(summary.registrationNoticeText)
    }

    func testKeyboardVisualizerTreatsUnknownPhysicalSideAsGenericModifier() throws {
        let state = KeyboardShortcutVisualizerState.recording(modifierFlags: [.option])
        let optionKeys = KeyboardShortcutVisualizerPresentation.rows
            .flatMap { $0 }
            .filter { !$0.ids.isDisjoint(with: [.leftOption, .rightOption]) }

        XCTAssertEqual(optionKeys.count, 2)
        XCTAssertTrue(optionKeys.allSatisfy {
            KeyboardShortcutVisualizerPresentation.isPressed($0, state: state)
        })
    }

    func testKeyboardRegistrationSummaryMakesFnProjectionExplicit() {
        let state = KeyboardShortcutVisualizerState.recording(
            keyCode: UInt16(kVK_ANSI_R),
            cgFlags: [.maskSecondaryFn]
        )

        let summary = KeyboardShortcutRegistrationSummary(state: state)

        XCTAssertEqual(summary.pressedText, "fn + R")
        XCTAssertEqual(summary.registeredText, "R")
        XCTAssertTrue(summary.usesGenericRegistration)
        XCTAssertEqual(summary.registrationNoticeText, "Fn ignored")
    }

    func testKeyboardRegistrationSummaryCombinesGenericAndFnNotices() {
        let flags = CGEventFlags(
            rawValue: CGEventFlags.maskAlternate.rawValue | 0x00000040 | CGEventFlags.maskSecondaryFn.rawValue
        )
        let state = KeyboardShortcutVisualizerState.recording(
            keyCode: UInt16(kVK_ANSI_R),
            cgFlags: flags
        )

        let summary = KeyboardShortcutRegistrationSummary(state: state)

        XCTAssertEqual(summary.pressedText, "fn + Right ⌥ + R")
        XCTAssertEqual(summary.registeredText, "⌥ + R")
        XCTAssertEqual(summary.registrationNoticeText, "Generic, Fn ignored")
    }

    func testKeyboardVisualizerStateIncludesFnFromCGFlags() {
        let state = KeyboardShortcutVisualizerState.recording(
            keyCode: nil,
            cgFlags: [.maskSecondaryFn]
        )

        XCTAssertTrue(state.pressedKeys.contains(.fn))
    }

    func testConfirmationControlsUseExplicitConfirmCancelResetCopy() {
        XCTAssertEqual(KeyboardShortcutConfirmationPresentation.resetTitle, "Reset")
        XCTAssertEqual(KeyboardShortcutConfirmationPresentation.confirmTitle, "Confirm")
        XCTAssertEqual(KeyboardShortcutConfirmationPresentation.cancelTitle, "Cancel")
        XCTAssertEqual(KeyboardShortcutConfirmationPresentation.helpText, "Enter to confirm, Esc to cancel")
    }

    func testRecorderLabelIsVerticallyCenteredInsideCompactControl() throws {
        var descriptor = HotkeyDescriptor.defaultClipboard
        let recorder = HotkeyRecorder.RecorderView(
            descriptor: Binding(
                get: { descriptor },
                set: { descriptor = $0 }
            )
        )
        recorder.frame = NSRect(x: 0, y: 0, width: 160, height: HotkeyChipPresentation.compactHeight)
        recorder.layoutSubtreeIfNeeded()

        let labelFrame = try XCTUnwrap(recorder.visibleLabelFrame)
        XCTAssertEqual(labelFrame.midY, recorder.bounds.midY, accuracy: 0.5)
    }

    func testResetStateIsActiveOnlyWhenShortcutDiffersFromDefault() {
        XCTAssertEqual(
            HotkeyRecorderControlPresentation.resetState(
                descriptor: .defaultClipboard,
                defaultDescriptor: .defaultClipboard
            ),
            .inactive
        )
        XCTAssertEqual(
            HotkeyRecorderControlPresentation.resetState(
                descriptor: .defaultDownload,
                defaultDescriptor: .defaultClipboard
            ),
            .active
        )
    }

    func testHotkeyRowIssueOnlyShowsRegistrationErrorForCurrentAction() {
        let registrationErrors: [HotkeyAction: String] = [
            .browseFolder: "Could not register Folder preview"
        ]

        XCTAssertNil(
            HotkeyRecorderControlPresentation.rowIssueMessage(
                validationIssue: nil,
                registrationErrors: registrationErrors,
                action: .clipboard
            )
        )
        XCTAssertEqual(
            HotkeyRecorderControlPresentation.rowIssueMessage(
                validationIssue: nil,
                registrationErrors: registrationErrors,
                action: .browseFolder
            ),
            "Could not register Folder preview"
        )
        XCTAssertEqual(
            HotkeyRecorderControlPresentation.rowIssueMessage(
                validationIssue: "This shortcut is reserved for system use.",
                registrationErrors: registrationErrors,
                action: .browseFolder
            ),
            "This shortcut is reserved for system use."
        )
    }

    func testRegistrationFailurePresentationUsesActualFailedAction() {
        let error = HotkeyRegistryError.registrationFailed(
            .browseFolder,
            NSError(domain: "HotkeyTest", code: 7)
        )

        let errors = HotkeyRecorderControlPresentation.registrationErrors(
            from: error,
            changedAction: .clipboard
        )

        XCTAssertNil(errors[.clipboard])
        XCTAssertEqual(errors[.browseFolder], error.localizedDescription)
    }

    func testHotkeyRegistrySkipsReapplyingAlreadyRegisteredMap() {
        XCTAssertTrue(
            HotkeyRegistryApplyPlan.shouldSkipApply(
                next: [.clipboard: [.defaultClipboard]],
                configured: [.clipboard: [.defaultClipboard]],
                hasActiveHandles: true
            )
        )
        XCTAssertFalse(
            HotkeyRegistryApplyPlan.shouldSkipApply(
                next: [.clipboard: [.defaultClipboard]],
                configured: [.clipboard: [.defaultClipboard]],
                hasActiveHandles: false
            )
        )
    }

    func testRegistryRegistrationMapExcludesWindowActionsWhenDisabled() {
        let map: [HotkeyAction: [HotkeyDescriptor]] = [
            .clipboard: [.defaultClipboard],
            .windowLeftHalf: [HotkeyDescriptor(keyCode: UInt32(kVK_LeftArrow), modifiers: [.control, .option])]
        ]

        let active = HotkeyRegistryRegistrationPlan.activeMap(from: map, windowControlEnabled: false)

        XCTAssertEqual(active[.clipboard], [.defaultClipboard])
        XCTAssertNil(active[.windowLeftHalf])
    }

    func testRegistryRegistrationMapExcludesWindowActionsWhenPerformerIsUnavailable() {
        let descriptor = HotkeyDescriptor(keyCode: UInt32(kVK_LeftArrow), modifiers: [.control, .option])
        let map: [HotkeyAction: [HotkeyDescriptor]] = [
            .clipboard: [.defaultClipboard],
            .windowLeftHalf: [descriptor]
        ]

        let active = HotkeyRegistryRegistrationPlan.activeMap(
            from: map,
            windowControlEnabled: true,
            windowActionPerformerAvailable: false
        )

        XCTAssertEqual(active[.clipboard], [.defaultClipboard])
        XCTAssertNil(active[.windowLeftHalf])
    }

    func testRegistryRegistrationMapIncludesWindowActionsWhenEnabledAndPerformerIsAvailable() {
        let descriptor = HotkeyDescriptor(keyCode: UInt32(kVK_LeftArrow), modifiers: [.control, .option])
        let map: [HotkeyAction: [HotkeyDescriptor]] = [
            .clipboard: [.defaultClipboard],
            .windowLeftHalf: [descriptor]
        ]

        let active = HotkeyRegistryRegistrationPlan.activeMap(
            from: map,
            windowControlEnabled: true,
            windowActionPerformerAvailable: true
        )

        XCTAssertEqual(active[.clipboard], [.defaultClipboard])
        XCTAssertEqual(active[.windowLeftHalf], [descriptor])
    }

    func testValidationSkipsDisabledEmptyDescriptorArrays() {
        let map: [HotkeyAction: [HotkeyDescriptor]] = [
            .clipboard: [],
            .browseFolder: [.defaultFolder]
        ]

        let issue = HotkeyValidation.firstIssue(in: map, systemHotkeys: [])

        XCTAssertNil(issue)
    }

    func testMouseDownShowsRecorderPromptForKeyboardCapture() {
        var descriptor = HotkeyDescriptor.defaultClipboard
        let recorder = HotkeyRecorder.RecorderView(
            descriptor: Binding(
                get: { descriptor },
                set: { descriptor = $0 }
            )
        )
        recorder.frame = NSRect(x: 0, y: 0, width: 120, height: 28)

        let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 8, y: 8),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        )!
        recorder.mouseDown(with: event)

        XCTAssertEqual(recorder.visibleLabelText, "Press shortcut...")
        XCTAssertNotNil(recorder.keyMonitor)
    }

    func testRecorderPublishesKeyboardVisualizerStateWhileRecording() {
        var descriptor = HotkeyDescriptor.defaultClipboard
        var visualizerState = KeyboardShortcutVisualizerState.inactive
        let recorder = HotkeyRecorder.RecorderView(
            descriptor: Binding(
                get: { descriptor },
                set: { descriptor = $0 }
            ),
            visualizerState: Binding(
                get: { visualizerState },
                set: { visualizerState = $0 }
            )
        )
        recorder.frame = NSRect(x: 0, y: 0, width: 120, height: 28)

        recorder.mouseDown(with: mouseEvent())
        XCTAssertTrue(visualizerState.isRecording)

        recorder.flagsChanged(with: flagsChangedEvent([.option]))
        XCTAssertTrue(visualizerState.pressedKeys.contains(.genericOption))

        recorder.keyDown(with: keyEvent(keyCode: UInt16(kVK_ANSI_R), character: "r", timestamp: 0))
        XCTAssertTrue(visualizerState.isRecording)

        recorder.confirmPendingShortcut()
        XCTAssertFalse(visualizerState.isRecording)
    }

    func testModifierReleaseAfterCandidateKeepsPendingShortcutHighlighted() {
        var descriptor = HotkeyDescriptor.defaultClipboard
        var visualizerState = KeyboardShortcutVisualizerState.inactive
        let recorder = HotkeyRecorder.RecorderView(
            descriptor: Binding(
                get: { descriptor },
                set: { descriptor = $0 }
            ),
            visualizerState: Binding(
                get: { visualizerState },
                set: { visualizerState = $0 }
            )
        )
        recorder.frame = NSRect(x: 0, y: 0, width: 120, height: 28)
        recorder.mouseDown(with: mouseEvent())
        recorder.keyDown(
            with: NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.control, .option],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "r",
                charactersIgnoringModifiers: "r",
                isARepeat: false,
                keyCode: UInt16(kVK_ANSI_R)
            )!
        )

        recorder.flagsChanged(with: flagsChangedEvent([]))

        XCTAssertEqual(
            recorder.pendingDescriptor,
            HotkeyDescriptor(keyCode: UInt32(kVK_ANSI_R), modifiers: [.control, .option])
        )
        XCTAssertTrue(visualizerState.pressedKeys.contains(.genericControl))
        XCTAssertTrue(visualizerState.pressedKeys.contains(.genericOption))
        XCTAssertTrue(visualizerState.pressedKeys.contains(.keyCode(UInt16(kVK_ANSI_R))))
        XCTAssertEqual(recorder.visibleLabelText, "⌃⌥R")
        XCTAssertEqual(descriptor, .defaultClipboard)
    }

    func testResetPendingShortcutClearsCandidateButKeepsRecorderOpen() {
        var descriptor = HotkeyDescriptor.defaultClipboard
        var visualizerState = KeyboardShortcutVisualizerState.inactive
        let recorder = HotkeyRecorder.RecorderView(
            descriptor: Binding(
                get: { descriptor },
                set: { descriptor = $0 }
            ),
            visualizerState: Binding(
                get: { visualizerState },
                set: { visualizerState = $0 }
            )
        )
        recorder.frame = NSRect(x: 0, y: 0, width: 120, height: 28)
        recorder.mouseDown(with: mouseEvent())
        recorder.keyDown(with: keyEvent(keyCode: UInt16(kVK_ANSI_R), character: "r", timestamp: 0))

        recorder.resetPendingShortcut()

        XCTAssertNil(recorder.pendingDescriptor)
        XCTAssertNil(recorder.pendingIssueMessage)
        XCTAssertTrue(visualizerState.isRecording)
        XCTAssertTrue(visualizerState.pressedKeys.isEmpty)
        XCTAssertEqual(recorder.visibleLabelText, "Press shortcut...")
        XCTAssertEqual(descriptor, .defaultClipboard)
        XCTAssertNotNil(recorder.keyMonitor)
    }

    func testKeyDownAfterClickPreviewsShortcutUntilConfirmed() {
        var descriptor = HotkeyDescriptor.defaultClipboard
        let recorder = HotkeyRecorder.RecorderView(
            descriptor: Binding(
                get: { descriptor },
                set: { descriptor = $0 }
            )
        )
        recorder.frame = NSRect(x: 0, y: 0, width: 120, height: 28)
        recorder.mouseDown(with: mouseEvent())

        let keyEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.control, .option],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "r",
            charactersIgnoringModifiers: "r",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_R)
        )!
        recorder.keyDown(with: keyEvent)

        XCTAssertEqual(descriptor, .defaultClipboard)
        XCTAssertEqual(
            recorder.pendingDescriptor,
            HotkeyDescriptor(keyCode: UInt32(kVK_ANSI_R), modifiers: [.control, .option])
        )
        XCTAssertNil(recorder.pendingIssueMessage)
        XCTAssertEqual(recorder.visibleLabelText, "⌃⌥R")
        XCTAssertNotNil(recorder.keyMonitor)

        recorder.confirmPendingShortcut()

        XCTAssertEqual(
            descriptor,
            HotkeyDescriptor(keyCode: UInt32(kVK_ANSI_R), modifiers: [.control, .option])
        )
        XCTAssertEqual(recorder.visibleLabelText, "⌃⌥R")
        XCTAssertNil(recorder.keyMonitor)
    }

    func testResignFirstResponderDoesNotCancelActiveKeyboardMonitor() {
        var descriptor = HotkeyDescriptor.defaultClipboard
        let recorder = HotkeyRecorder.RecorderView(
            descriptor: Binding(
                get: { descriptor },
                set: { descriptor = $0 }
            )
        )
        recorder.frame = NSRect(x: 0, y: 0, width: 120, height: 28)
        recorder.mouseDown(with: mouseEvent())

        _ = recorder.resignFirstResponder()

        XCTAssertEqual(recorder.visibleLabelText, "Press shortcut...")
        XCTAssertNotNil(recorder.keyMonitor)
    }

    func testUpdatingDescriptorBindingWritesCapturedShortcutToCurrentState() {
        var staleDescriptor = HotkeyDescriptor.defaultClipboard
        var currentDescriptor = HotkeyDescriptor.defaultDownload
        let recorder = HotkeyRecorder.RecorderView(
            descriptor: Binding(
                get: { staleDescriptor },
                set: { staleDescriptor = $0 }
            )
        )
        recorder.frame = NSRect(x: 0, y: 0, width: 120, height: 28)
        recorder.updateDescriptorBinding(
            Binding(
                get: { currentDescriptor },
                set: { currentDescriptor = $0 }
            )
        )
        recorder.mouseDown(with: mouseEvent())

        let keyEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.control, .option],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "r",
            charactersIgnoringModifiers: "r",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_R)
        )!
        recorder.keyDown(with: keyEvent)

        XCTAssertEqual(staleDescriptor, .defaultClipboard)
        XCTAssertEqual(currentDescriptor, .defaultDownload)
        XCTAssertEqual(recorder.visibleLabelText, "⌃⌥R")

        recorder.confirmPendingShortcut()

        XCTAssertEqual(staleDescriptor, .defaultClipboard)
        XCTAssertEqual(
            currentDescriptor,
            HotkeyDescriptor(keyCode: UInt32(kVK_ANSI_R), modifiers: [.control, .option])
        )
        XCTAssertEqual(recorder.visibleLabelText, "⌃⌥R")
    }

    func testFlagsChangedBeforeKeyDownSuppliesModifierState() {
        var descriptor = HotkeyDescriptor.defaultClipboard
        let recorder = HotkeyRecorder.RecorderView(
            descriptor: Binding(
                get: { descriptor },
                set: { descriptor = $0 }
            )
        )
        recorder.frame = NSRect(x: 0, y: 0, width: 120, height: 28)
        recorder.mouseDown(with: mouseEvent())

        recorder.flagsChanged(with: flagsChangedEvent([.control, .option]))
        XCTAssertEqual(recorder.visibleLabelText, "⌃⌥…")

        let keyEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "r",
            charactersIgnoringModifiers: "r",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_R)
        )!
        recorder.keyDown(with: keyEvent)

        XCTAssertEqual(descriptor, .defaultClipboard)
        XCTAssertEqual(recorder.visibleLabelText, "⌃⌥R")
        XCTAssertNotNil(recorder.keyMonitor)

        recorder.confirmPendingShortcut()

        XCTAssertEqual(
            descriptor,
            HotkeyDescriptor(keyCode: UInt32(kVK_ANSI_R), modifiers: [.control, .option])
        )
        XCTAssertEqual(recorder.visibleLabelText, "⌃⌥R")
    }

    func testAccessibilityPressIgnoresImmediateActivationKey() {
        var descriptor = HotkeyDescriptor.defaultClipboard
        let recorder = HotkeyRecorder.RecorderView(
            descriptor: Binding(
                get: { descriptor },
                set: { descriptor = $0 }
            )
        )
        recorder.frame = NSRect(x: 0, y: 0, width: 120, height: 28)

        XCTAssertTrue(recorder.accessibilityPerformPress())
        recorder.keyDown(with: keyEvent(keyCode: UInt16(kVK_ANSI_I), character: "i", timestamp: 0))

        XCTAssertEqual(descriptor, .defaultClipboard)
        XCTAssertEqual(recorder.visibleLabelText, "Press shortcut...")

        recorder.keyDown(
            with: keyEvent(
                keyCode: UInt16(kVK_ANSI_R),
                character: "r",
                timestamp: ProcessInfo.processInfo.systemUptime + 1
            )
        )

        XCTAssertEqual(descriptor, .defaultClipboard)
        XCTAssertEqual(recorder.visibleLabelText, "R")

        recorder.confirmPendingShortcut()

        XCTAssertEqual(
            descriptor,
            HotkeyDescriptor(keyCode: UInt32(kVK_ANSI_R), modifiers: [])
        )
    }

    func testReturnConfirmsPendingShortcut() {
        var descriptor = HotkeyDescriptor.defaultClipboard
        let recorder = HotkeyRecorder.RecorderView(
            descriptor: Binding(
                get: { descriptor },
                set: { descriptor = $0 }
            )
        )
        recorder.frame = NSRect(x: 0, y: 0, width: 120, height: 28)
        recorder.mouseDown(with: mouseEvent())

        recorder.keyDown(with: keyEvent(keyCode: UInt16(kVK_ANSI_R), character: "r", timestamp: 0))
        recorder.keyDown(with: keyEvent(keyCode: UInt16(kVK_Return), character: "\r", timestamp: 0))

        XCTAssertEqual(
            descriptor,
            HotkeyDescriptor(keyCode: UInt32(kVK_ANSI_R), modifiers: [])
        )
        XCTAssertNil(recorder.keyMonitor)
    }

    func testCandidateConflictBlocksConfirmBeforeSaving() {
        var descriptor = HotkeyDescriptor.defaultClipboard
        let recorder = HotkeyRecorder.RecorderView(
            descriptor: Binding(
                get: { descriptor },
                set: { descriptor = $0 }
            ),
            candidateIssueMessage: { candidate in
                candidate == HotkeyDescriptor(keyCode: UInt32(kVK_ANSI_R), modifiers: [.control, .option])
                    ? "This shortcut is already used by Clipboard."
                    : nil
            }
        )
        recorder.frame = NSRect(x: 0, y: 0, width: 120, height: 28)
        recorder.mouseDown(with: mouseEvent())

        let keyEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.control, .option],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "r",
            charactersIgnoringModifiers: "r",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_R)
        )!
        recorder.keyDown(with: keyEvent)

        XCTAssertEqual(descriptor, .defaultClipboard)
        XCTAssertEqual(
            recorder.pendingDescriptor,
            HotkeyDescriptor(keyCode: UInt32(kVK_ANSI_R), modifiers: [.control, .option])
        )
        XCTAssertEqual(recorder.pendingIssueMessage, "This shortcut is already used by Clipboard.")

        recorder.confirmPendingShortcut()

        XCTAssertEqual(descriptor, .defaultClipboard)
        XCTAssertNotNil(recorder.keyMonitor)
    }

    func testRecordingPostsLifecycleNotifications() {
        var descriptor = HotkeyDescriptor.defaultClipboard
        let recorder = HotkeyRecorder.RecorderView(
            descriptor: Binding(
                get: { descriptor },
                set: { descriptor = $0 }
            )
        )
        recorder.frame = NSRect(x: 0, y: 0, width: 120, height: 28)
        var events: [Notification.Name] = []
        let startObserver = NotificationCenter.default.addObserver(
            forName: .hotkeyRecorderDidStartRecording,
            object: recorder,
            queue: nil
        ) { note in events.append(note.name) }
        let stopObserver = NotificationCenter.default.addObserver(
            forName: .hotkeyRecorderDidStopRecording,
            object: recorder,
            queue: nil
        ) { note in events.append(note.name) }
        defer {
            NotificationCenter.default.removeObserver(startObserver)
            NotificationCenter.default.removeObserver(stopObserver)
        }

        recorder.mouseDown(with: mouseEvent())
        recorder.keyDown(with: keyEvent(keyCode: UInt16(kVK_ANSI_R), character: "r", timestamp: 0))
        recorder.confirmPendingShortcut()

        XCTAssertEqual(events, [.hotkeyRecorderDidStartRecording, .hotkeyRecorderDidStopRecording])
    }

    func testEventTapTranslatorBuildsDescriptorFromCGFlags() {
        let descriptor = HotkeyRecorderEventTranslator.descriptor(
            keyCode: UInt16(kVK_Space),
            cgFlags: [.maskCommand],
            fallbackModifierFlags: []
        )

        XCTAssertEqual(descriptor, HotkeyDescriptor(keyCode: UInt32(kVK_Space), modifiers: [.command]))
    }

    func testModifierTapSinglePressPreviewsCommand() {
        var descriptor = HotkeyDescriptor.defaultClipboard
        let recorder = HotkeyRecorder.RecorderView(
            descriptor: Binding(get: { descriptor }, set: { descriptor = $0 })
        )
        recorder.frame = NSRect(x: 0, y: 0, width: 120, height: 28)
        recorder.mouseDown(with: mouseEvent())

        let flags = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x00000008)
        recorder.testApplyCGFlags(flags)

        XCTAssertEqual(recorder.pendingDescriptor?.modifierTap?.key, .command)
        XCTAssertEqual(recorder.pendingDescriptor?.modifierTap?.count, 1)
        XCTAssertEqual(recorder.visibleLabelText, "⌘")
    }

    func testModifierTapDoublePressPreviewsTimesTwo() {
        var descriptor = HotkeyDescriptor.defaultClipboard
        let recorder = HotkeyRecorder.RecorderView(
            descriptor: Binding(get: { descriptor }, set: { descriptor = $0 })
        )
        recorder.frame = NSRect(x: 0, y: 0, width: 120, height: 28)
        recorder.mouseDown(with: mouseEvent())

        let cmdFlags = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x00000008)
        recorder.testApplyCGFlags(cmdFlags)
        recorder.testApplyCGFlags([])
        recorder.testApplyCGFlags(cmdFlags)

        XCTAssertEqual(recorder.pendingDescriptor?.modifierTap?.count, 2)
        XCTAssertEqual(recorder.visibleLabelText, "⌘ ×2")
    }

    func testModifierTapValidationAllowsSave() {
        let descriptor = HotkeyDescriptor(modifierTap: .doubleTap(.command))
        let issue = HotkeyValidation.issue(
            forAppHotkey: descriptor,
            action: .clipboard,
            index: 0,
            appHotkeys: [:],
            dockShortcuts: [:]
        )
        XCTAssertNil(issue)
    }

    func testEventTapTranslatorFallsBackToTrackedModifierState() {
        let descriptor = HotkeyRecorderEventTranslator.descriptor(
            keyCode: UInt16(kVK_ANSI_R),
            cgFlags: [],
            fallbackModifierFlags: [.control, .option]
        )

        XCTAssertEqual(descriptor, HotkeyDescriptor(keyCode: UInt32(kVK_ANSI_R), modifiers: [.control, .option]))
    }

    private func mouseEvent() -> NSEvent {
        NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 8, y: 8),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        )!
    }

    private func flagsChangedEvent(_ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: UInt16(kVK_Control)
        )!
    }

    private func keyEvent(keyCode: UInt16, character: String, timestamp: TimeInterval) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: timestamp,
            windowNumber: 0,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: character,
            isARepeat: false,
            keyCode: keyCode
        )!
    }
}

private extension HotkeyRecorder.RecorderView {
    var visibleLabelText: String? {
        subviews.compactMap { $0 as? NSTextField }.first?.stringValue
    }

    var visibleLabelFrame: NSRect? {
        subviews.compactMap { $0 as? NSTextField }.first?.frame
    }
}
