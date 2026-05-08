@testable import MacAllYouNeed
import AppKit
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
        let custom = ShortcutBinding(keyCode: 11, modifierMask: NSEvent.ModifierFlags.command.rawValue)

        registry.setBindings([custom], for: .togglePin)
        XCTAssertEqual(registry.bindings(for: .togglePin), [custom])

        let secondRegistry = ShortcutRegistry()
        XCTAssertEqual(secondRegistry.bindings(for: .togglePin), [custom])
    }

    func testAddBindingAppendsToExisting() {
        let registry = ShortcutRegistry()
        let extra = ShortcutBinding(keyCode: 11, modifierMask: NSEvent.ModifierFlags.command.rawValue)

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

    func testReservedKeysAreRejectedForOtherActions() {
        let registry = ShortcutRegistry()
        let escapeForPin = ShortcutBinding(keyCode: 53, modifierMask: 0)

        XCTAssertThrowsError(try registry.validate(escapeForPin, for: .togglePin))
    }

    func testReservedKeyAcceptedForItsConventionalAction() {
        let registry = ShortcutRegistry()
        let escapeForDismiss = ShortcutBinding(keyCode: 53, modifierMask: 0)

        XCTAssertNoThrow(try registry.validate(escapeForDismiss, for: .dismiss))
    }
}
