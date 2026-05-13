@testable import MacAllYouNeed
import AppKit
import Carbon.HIToolbox
import Platform
import SwiftUI
import XCTest

@MainActor
final class HotkeyRecorderTests: XCTestCase {
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

    func testKeyDownAfterClickUpdatesDescriptorAndLabel() {
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

        XCTAssertEqual(
            descriptor,
            HotkeyDescriptor(keyCode: UInt32(kVK_ANSI_R), modifiers: [])
        )
        XCTAssertEqual(recorder.visibleLabelText, "R")
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

        XCTAssertEqual(events, [.hotkeyRecorderDidStartRecording, .hotkeyRecorderDidStopRecording])
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
}
