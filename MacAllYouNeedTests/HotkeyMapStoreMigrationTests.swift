@testable import MacAllYouNeed
import Carbon.HIToolbox
import Platform
import XCTest

@MainActor
final class HotkeyMapStoreMigrationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test.hotkeymap.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testMigratesV1IntoV3WrappingDescriptorInArray() throws {
        let custom = HotkeyDescriptor.defaultClipboard
        let legacy: [String: HotkeyDescriptor] = [
            HotkeyAction.clipboard.rawValue: custom
        ]
        defaults.set(try JSONEncoder().encode(legacy), forKey: HotkeyMapStore.legacyKey)

        let map = HotkeyMapStore.load(from: defaults)

        XCTAssertEqual(map[.clipboard], [custom],
                       "V1 single-descriptor entry must be wrapped into a one-element array")
    }

    func testMigrationDeletesV1KeyAndPersistsV3() throws {
        let legacy: [String: HotkeyDescriptor] = [
            HotkeyAction.clipboard.rawValue: .defaultClipboard,
            "addDownload": .defaultDownload
        ]
        defaults.set(try JSONEncoder().encode(legacy), forKey: HotkeyMapStore.legacyKey)

        _ = HotkeyMapStore.load(from: defaults)

        XCTAssertNil(defaults.data(forKey: HotkeyMapStore.legacyKey),
                     "V1 key must be removed after one-shot migration")
        XCTAssertNotNil(defaults.data(forKey: HotkeyMapStore.v3Key),
                        "V3 key must be written so subsequent loads skip the migration path")
    }

    func testMigrationIsIdempotent() throws {
        let legacy: [String: HotkeyDescriptor] = [
            HotkeyAction.clipboard.rawValue: .defaultClipboard
        ]
        defaults.set(try JSONEncoder().encode(legacy), forKey: HotkeyMapStore.legacyKey)

        let first = HotkeyMapStore.load(from: defaults)
        let second = HotkeyMapStore.load(from: defaults)

        XCTAssertEqual(first[.clipboard], second[.clipboard])
        XCTAssertEqual(first[.browseFolder], second[.browseFolder])
    }

    func testMigrationIgnoresRemovedDownloadHotkey() throws {
        let legacy: [String: HotkeyDescriptor] = [
            HotkeyAction.clipboard.rawValue: .defaultClipboard,
            "addDownload": .defaultDownload
        ]
        defaults.set(try JSONEncoder().encode(legacy), forKey: HotkeyMapStore.legacyKey)

        let map = HotkeyMapStore.load(from: defaults)

        XCTAssertEqual(map[.clipboard], [.defaultClipboard])
        XCTAssertFalse(map.keys.map(\.rawValue).contains("addDownload"))
    }

    func testV2LoadIgnoresRemovedDownloadHotkey() throws {
        let v2: [String: [HotkeyDescriptor]] = [
            HotkeyAction.clipboard.rawValue: [.defaultClipboard],
            "addDownload": [.defaultDownload]
        ]
        defaults.set(try JSONEncoder().encode(v2), forKey: HotkeyMapStore.v2Key)

        let map = HotkeyMapStore.load(from: defaults)

        XCTAssertEqual(map[.clipboard], [.defaultClipboard])
        XCTAssertFalse(map.keys.map(\.rawValue).contains("addDownload"))
    }

    func testV2PresentTakesPrecedenceOverV1IfBothExist() throws {
        // Defensive: a corrupted state where both keys are present must not
        // silently revert to V1; V2 wins.
        let v2: [String: [HotkeyDescriptor]] = [
            HotkeyAction.clipboard.rawValue: [.defaultClipboard, .defaultDownload]
        ]
        let v1: [String: HotkeyDescriptor] = [
            HotkeyAction.clipboard.rawValue: .defaultFolder
        ]
        defaults.set(try JSONEncoder().encode(v2), forKey: HotkeyMapStore.v2Key)
        defaults.set(try JSONEncoder().encode(v1), forKey: HotkeyMapStore.legacyKey)

        let map = HotkeyMapStore.load(from: defaults)
        XCTAssertEqual(map[.clipboard], [.defaultClipboard, .defaultDownload])
    }

    func testSaveWritesV3Key() {
        HotkeyMapStore.save([.clipboard: []], to: defaults)

        XCTAssertNotNil(defaults.data(forKey: HotkeyMapStore.v3Key))
        XCTAssertNil(defaults.data(forKey: HotkeyMapStore.v2Key))
    }

    func testV3EmptyArrayDisablesClipboardHotkey() throws {
        let v3: [String: [HotkeyDescriptor]] = [
            HotkeyAction.clipboard.rawValue: []
        ]
        defaults.set(try JSONEncoder().encode(v3), forKey: HotkeyMapStore.v3Key)

        let map = HotkeyMapStore.load(from: defaults)

        XCTAssertEqual(map[.clipboard], [])
        XCTAssertEqual(map[.browseFolder], [.defaultFolder])
    }

    func testV2EmptyClipboardMigratesToDefaultClipboard() throws {
        let v2: [String: [HotkeyDescriptor]] = [
            HotkeyAction.clipboard.rawValue: []
        ]
        defaults.set(try JSONEncoder().encode(v2), forKey: HotkeyMapStore.v2Key)

        let map = HotkeyMapStore.load(from: defaults)

        XCTAssertEqual(map[.clipboard], [.defaultClipboard])
    }

    func testV2EmptyBrowseFolderMigratesToDefaultFolder() throws {
        let v2: [String: [HotkeyDescriptor]] = [
            HotkeyAction.browseFolder.rawValue: []
        ]
        defaults.set(try JSONEncoder().encode(v2), forKey: HotkeyMapStore.v2Key)

        let map = HotkeyMapStore.load(from: defaults)

        XCTAssertEqual(map[.browseFolder], [.defaultFolder])
    }

    func testV2MigrationPersistsV3AndRemovesV2() throws {
        let v2: [String: [HotkeyDescriptor]] = [
            HotkeyAction.clipboard.rawValue: [],
            HotkeyAction.browseFolder.rawValue: [.defaultDownload]
        ]
        defaults.set(try JSONEncoder().encode(v2), forKey: HotkeyMapStore.v2Key)

        _ = HotkeyMapStore.load(from: defaults)

        XCTAssertNotNil(defaults.data(forKey: HotkeyMapStore.v3Key))
        XCTAssertNil(defaults.data(forKey: HotkeyMapStore.v2Key))
    }

    func testV3UnknownKeysAreIgnored() throws {
        let v3: [String: [HotkeyDescriptor]] = [
            HotkeyAction.clipboard.rawValue: [.defaultClipboard],
            "unknownWindowThing": [.defaultDownload]
        ]
        defaults.set(try JSONEncoder().encode(v3), forKey: HotkeyMapStore.v3Key)

        let map = HotkeyMapStore.load(from: defaults)

        XCTAssertEqual(map[.clipboard], [.defaultClipboard])
        XCTAssertFalse(map.keys.map(\.rawValue).contains("unknownWindowThing"))
    }

    func testV3DeprecatedCommandShiftWindowDefaultsMigrateBackToControlOption() throws {
        let v3: [String: [HotkeyDescriptor]] = [
            HotkeyAction.windowLeftHalf.rawValue: [
                HotkeyDescriptor(keyCode: UInt32(kVK_LeftArrow), modifiers: [.command, .shift])
            ],
            HotkeyAction.windowRightHalf.rawValue: [
                HotkeyDescriptor(keyCode: UInt32(kVK_RightArrow), modifiers: [.command, .shift])
            ]
        ]
        defaults.set(try JSONEncoder().encode(v3), forKey: HotkeyMapStore.v3Key)

        let map = HotkeyMapStore.load(from: defaults)

        XCTAssertEqual(HotkeyAction.windowLeftHalf.defaultDescriptors, map[.windowLeftHalf])
        XCTAssertEqual(HotkeyAction.windowRightHalf.defaultDescriptors, map[.windowRightHalf])
    }

    func testWindowHotkeyActionsExposeExpectedDefaults() {
        XCTAssertEqual(
            HotkeyAction.windowLeftHalf.defaultDescriptors,
            [HotkeyDescriptor(keyCode: UInt32(kVK_LeftArrow), modifiers: [.control, .option])]
        )
        XCTAssertEqual(
            HotkeyAction.windowRightHalf.defaultDescriptors,
            [HotkeyDescriptor(keyCode: UInt32(kVK_RightArrow), modifiers: [.control, .option])]
        )
        XCTAssertEqual(
            HotkeyAction.windowTopHalf.defaultDescriptors,
            [HotkeyDescriptor(keyCode: UInt32(kVK_UpArrow), modifiers: [.control, .option])]
        )
        XCTAssertEqual(
            HotkeyAction.windowBottomHalf.defaultDescriptors,
            [HotkeyDescriptor(keyCode: UInt32(kVK_DownArrow), modifiers: [.control, .option])]
        )
        XCTAssertEqual(
            HotkeyAction.windowRestore.defaultDescriptors,
            [HotkeyDescriptor(keyCode: UInt32(kVK_ANSI_R), modifiers: [.control, .option])]
        )
        XCTAssertEqual(HotkeyAction.windowTopLeft.defaultDescriptors, [])
        XCTAssertNil(HotkeyAction.windowTopLeft.primaryDefaultDescriptor)
    }

    func testWindowConflictMessageUsesGroupedLabel() {
        let descriptor = HotkeyDescriptor(keyCode: UInt32(kVK_LeftArrow), modifiers: [.control, .option])

        let issue = HotkeyValidation.issue(
            forAppHotkey: descriptor,
            action: .clipboard,
            index: 0,
            appHotkeys: [.windowLeftHalf: [descriptor]],
            systemHotkeys: []
        )

        XCTAssertEqual(issue?.message, "This shortcut is already used by Window Layouts: Left half.")
    }

    func testVoiceShortcutValidationRejectsSystemReservedShortcut() {
        let descriptor = HotkeyDescriptor(keyCode: UInt32(kVK_Space), modifiers: [.command])

        let issue = HotkeyValidation.issue(forVoiceShortcut: descriptor, appHotkeys: [:])

        XCTAssertEqual(issue?.message, "This shortcut is reserved for system use.")
    }

    func testVoiceShortcutValidationRejectsExistingAppHotkeyConflict() {
        let descriptor = HotkeyDescriptor.defaultClipboard

        let issue = HotkeyValidation.issue(
            forVoiceShortcut: descriptor,
            appHotkeys: HotkeyMapStore.load(from: defaults),
            systemHotkeys: []
        )

        XCTAssertEqual(issue?.message, "This shortcut is already used by Open clipboard popup.")
    }

    func testFolderPreviewHotkeyLabelMatchesFinderQuickLookBehavior() {
        XCTAssertEqual(HotkeyAction.browseFolder.label, "Folder preview")
    }

    func testVoiceShortcutValidationAllowsUniqueShortcut() {
        let descriptor = HotkeyDescriptor(keyCode: UInt32(kVK_ANSI_Y), modifiers: [.control, .option])

        let issue = HotkeyValidation.issue(
            forVoiceShortcut: descriptor,
            appHotkeys: HotkeyMapStore.load(from: defaults),
            systemHotkeys: []
        )

        XCTAssertNil(issue)
    }

    func testAppHotkeyValidationRejectsSystemReservedShortcut() {
        let descriptor = HotkeyDescriptor(keyCode: UInt32(kVK_Space), modifiers: [.command])

        let issue = HotkeyValidation.issue(
            forAppHotkey: descriptor,
            action: .clipboard,
            index: 0,
            appHotkeys: HotkeyMapStore.load(from: defaults)
        )

        XCTAssertEqual(issue?.message, "This shortcut is reserved for system use.")
    }

    func testAppHotkeyValidationRejectsMacOSScreenshotShortcut() {
        let descriptor = HotkeyDescriptor(keyCode: UInt32(kVK_ANSI_5), modifiers: [.command, .shift])

        let issue = HotkeyValidation.issue(
            forAppHotkey: descriptor,
            action: .clipboard,
            index: 0,
            appHotkeys: HotkeyMapStore.load(from: defaults)
        )

        XCTAssertEqual(issue?.message, "This shortcut is reserved for system use.")
    }

    func testSystemSymbolicHotkeyParserIncludesEnabledStandardShortcuts() {
        let raw: [String: Any] = [
            "160": [
                "enabled": 1,
                "value": [
                    "type": "standard",
                    "parameters": [100, Int(kVK_ANSI_D), Int(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue)]
                ]
            ],
            "161": [
                "enabled": 0,
                "value": [
                    "type": "standard",
                    "parameters": [100, Int(kVK_ANSI_V), Int(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue)]
                ]
            ]
        ]

        let descriptors = SystemHotkeyConflictDetector.enabledSymbolicHotkeys(from: raw)

        XCTAssertTrue(descriptors.contains(.defaultDownload))
        XCTAssertFalse(descriptors.contains(.defaultClipboard))
    }

    func testAppHotkeyValidationRejectsEnabledSystemSymbolicHotkey() {
        let issue = HotkeyValidation.issue(
            forAppHotkey: .defaultDownload,
            action: .clipboard,
            index: 0,
            appHotkeys: HotkeyMapStore.load(from: defaults),
            systemHotkeys: [.defaultDownload]
        )

        XCTAssertEqual(issue?.message, "This shortcut is already used by macOS.")
    }

    func testAppHotkeyValidationRejectsExistingAppHotkeyConflict() {
        let issue = HotkeyValidation.issue(
            forAppHotkey: .defaultFolder,
            action: .clipboard,
            index: 0,
            appHotkeys: HotkeyMapStore.load(from: defaults),
            systemHotkeys: []
        )

        XCTAssertEqual(issue?.message, "This shortcut is already used by Folder preview.")
    }

    func testAppHotkeyValidationRejectsVoiceShortcutConflict() {
        let voiceShortcut = HotkeyDescriptor(keyCode: UInt32(kVK_ANSI_R), modifiers: [.control, .option])

        let issue = HotkeyValidation.issue(
            forAppHotkey: voiceShortcut,
            action: .clipboard,
            index: 0,
            appHotkeys: HotkeyMapStore.load(from: defaults),
            voiceShortcut: voiceShortcut,
            systemHotkeys: []
        )

        XCTAssertEqual(issue?.message, "This shortcut is already used by Voice dictation.")
    }

    func testModifierTapShortcutIsNotReservedForSystemUse() {
        let single = HotkeyDescriptor(modifierTap: .singleTap(.command))
        let double = HotkeyDescriptor(modifierTap: .doubleTap(.leftOption))

        XCTAssertNil(HotkeyValidation.issue(
            forAppHotkey: single,
            action: .clipboard,
            index: 0,
            appHotkeys: [:],
            dockShortcuts: [:]
        ))
        XCTAssertNil(HotkeyValidation.issue(
            forAppHotkey: double,
            action: .windowLeftHalf,
            index: 0,
            appHotkeys: [:],
            dockShortcuts: [:]
        ))
    }

    func testAppHotkeyValidationAllowsUnchangedCurrentSlot() {
        let issue = HotkeyValidation.issue(
            forAppHotkey: .defaultClipboard,
            action: .clipboard,
            index: 0,
            appHotkeys: HotkeyMapStore.load(from: defaults),
            systemHotkeys: []
        )

        XCTAssertNil(issue)
    }
}
