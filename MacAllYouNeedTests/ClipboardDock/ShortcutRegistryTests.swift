@testable import MacAllYouNeed
import AppKit
import Platform
import XCTest

@MainActor
final class ShortcutRegistryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        let suite = "test.shortcuts.\(UUID().uuidString)"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        ShortcutRegistry.testSuite = suite
    }

    override func tearDown() {
        ShortcutRegistry.testSuite = nil
        super.tearDown()
    }

    func testReturnsDefaultBindingForUnconfiguredAction() {
        let registry = ShortcutRegistry()
        let bindings = registry.bindings(for: .focusSearch)
        XCTAssertEqual(bindings, ShortcutDefaults.defaultBindings(for: .focusSearch))
    }

    func testSetAndPersistBinding() {
        let registry = ShortcutRegistry()
        let custom = HotkeyDescriptor(keyCode: 11, modifiers: [.command])

        registry.setBindings([custom], for: .togglePin)
        XCTAssertEqual(registry.bindings(for: .togglePin), [custom])

        let secondRegistry = ShortcutRegistry()
        XCTAssertEqual(secondRegistry.bindings(for: .togglePin), [custom])
    }

    func testAddBindingAppendsToExisting() {
        let registry = ShortcutRegistry()
        let extra = HotkeyDescriptor(keyCode: 11, modifiers: [.command])

        registry.addBinding(extra, for: .togglePin)

        XCTAssertTrue(registry.bindings(for: .togglePin).contains(extra))
        XCTAssertGreaterThanOrEqual(registry.bindings(for: .togglePin).count, 2)
    }

    func testResetRestoresDefaults() {
        let registry = ShortcutRegistry()

        registry.setBindings([], for: .togglePin)
        XCTAssertTrue(registry.bindings(for: .togglePin).isEmpty)

        registry.reset(action: .togglePin)
        XCTAssertEqual(registry.bindings(for: .togglePin), ShortcutDefaults.defaultBindings(for: .togglePin))
    }

    func testReservedKeysAreRejectedForOtherActions() throws {
        let registry = ShortcutRegistry()
        let escapeForPin = HotkeyDescriptor(keyCode: 53, modifiers: [])

        XCTAssertThrowsError(try registry.validate(escapeForPin, for: .togglePin))
    }

    func testReservedKeyAcceptedForItsConventionalAction() throws {
        let registry = ShortcutRegistry()
        let escapeForDismiss = HotkeyDescriptor(keyCode: 53, modifiers: [])

        XCTAssertNoThrow(try registry.validate(escapeForDismiss, for: .dismiss))
    }

    func testMigratesLegacyShortcutBindingPayload() {
        let suite = "test.shortcuts.legacy.\(UUID().uuidString)"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        ShortcutRegistry.testSuite = suite
        let defaults = UserDefaults(suiteName: suite)!
        let legacy = [LegacyShortcutBinding(keyCode: 11, modifierMask: NSEvent.ModifierFlags.command.rawValue)]
        let data = try! JSONEncoder().encode(legacy)
        defaults.set(data, forKey: "shortcut.togglePin")

        let registry = ShortcutRegistry()
        XCTAssertEqual(
            registry.bindings(for: .togglePin),
            [HotkeyDescriptor(keyCode: 11, modifiers: [.command])]
        )
    }

    func testModifierTapBindingRoundTrip() throws {
        let registry = ShortcutRegistry()
        let doubleCommand = HotkeyDescriptor(modifierTap: .doubleTap(.command))
        try registry.validate(doubleCommand, for: .focusSearch)
        registry.setBindings([doubleCommand], for: .focusSearch)
        XCTAssertEqual(registry.modifierTapBindings(for: .focusSearch), [doubleCommand])
    }
}
