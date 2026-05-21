// CGEventTapAdoptionTests.swift
// Pins the (tap, place, options, runLoop) configs of the five call sites that
// will adopt CGEventTapController in a later wave. Each test constructs a
// controller with the exact arguments the call site uses and asserts the
// inspection properties match, so future adoption subagents can verify they
// haven't drifted the config.
import XCTest
import CoreGraphics
@testable import Platform

final class CGEventTapAdoptionTests: XCTestCase {

    // MARK: - 1. Shared/Sources/Platform/Hotkey/ModifierTapDispatcher.swift
    // tap: .cghidEventTap, place: .tailAppendEventTap, options: .listenOnly
    // runLoop: CFRunLoopGetMain() -> .main

    func testModifierTapDispatcherConfigRoundTrip() {
        let controller = CGEventTapController(
            tap: .cghidEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: 0,
            runLoop: .main,
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        )
        XCTAssertEqual(controller.installedTapLocation, .cghidEventTap)
        XCTAssertEqual(controller.installedTapPlacement, .tailAppendEventTap)
        XCTAssertEqual(controller.installedTapOptions, .listenOnly)
        XCTAssertEqual(controller.installedRunLoopTarget, .main)
    }

    // MARK: - 2. MacAllYouNeed/WindowControl/WindowControlEventTap.swift
    // tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap
    // runLoop: CFRunLoopGetMain() -> .main

    func testWindowControlEventTapConfigRoundTrip() {
        let controller = CGEventTapController(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: 0,
            runLoop: .main,
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        )
        XCTAssertEqual(controller.installedTapLocation, .cgSessionEventTap)
        XCTAssertEqual(controller.installedTapPlacement, .headInsertEventTap)
        XCTAssertEqual(controller.installedTapOptions, .defaultTap)
        XCTAssertEqual(controller.installedRunLoopTarget, .main)
    }

    // MARK: - 3. MacAllYouNeed/Settings/HotkeyRecorder.swift (RecorderView)
    // tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap
    // runLoop: CFRunLoopGetMain() -> .main

    func testHotkeyRecorderConfigRoundTrip() {
        let controller = CGEventTapController(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: 0,
            runLoop: .main,
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        )
        XCTAssertEqual(controller.installedTapLocation, .cghidEventTap)
        XCTAssertEqual(controller.installedTapPlacement, .headInsertEventTap)
        XCTAssertEqual(controller.installedTapOptions, .defaultTap)
        XCTAssertEqual(controller.installedRunLoopTarget, .main)
    }

    // MARK: - 4. Shared/Sources/Platform/Paste/SnippetExpander.swift
    // tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap
    // runLoop: CFRunLoopGetCurrent() -> .current(...)
    // NOTE: SnippetExpander is the only call site using .current instead of .main.

    func testSnippetExpanderConfigRoundTrip() {
        // SnippetExpander calls CFRunLoopAddSource(CFRunLoopGetCurrent(), ...).
        // We capture the current run loop at test time to mirror the call site's
        // intent. The adoption subagent must pass .current(CFRunLoopGetCurrent())
        // at the point of construction (which happens on the same thread as start()).
        let currentLoop = CFRunLoopGetCurrent()!
        let controller = CGEventTapController(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: 0,
            runLoop: .current(currentLoop),
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        )
        XCTAssertEqual(controller.installedTapLocation, .cgSessionEventTap)
        XCTAssertEqual(controller.installedTapPlacement, .headInsertEventTap)
        XCTAssertEqual(controller.installedTapOptions, .defaultTap)
        XCTAssertEqual(controller.installedRunLoopTarget, .current(currentLoop))
        // Confirm it is NOT .main (the only call site that differs from the others).
        XCTAssertNotEqual(controller.installedRunLoopTarget, .main)
    }

    // MARK: - 5. MacAllYouNeed/ClipboardDock/Window/DockWindowController.swift
    // tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap
    // runLoop: CFRunLoopGetMain() -> .main

    func testDockWindowControllerConfigRoundTrip() {
        let controller = CGEventTapController(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: 0,
            runLoop: .main,
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        )
        XCTAssertEqual(controller.installedTapLocation, .cghidEventTap)
        XCTAssertEqual(controller.installedTapPlacement, .headInsertEventTap)
        XCTAssertEqual(controller.installedTapOptions, .defaultTap)
        XCTAssertEqual(controller.installedRunLoopTarget, .main)
    }
}
