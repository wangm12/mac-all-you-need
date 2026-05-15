@testable import MacAllYouNeed
import XCTest

final class SettingsExclusionListTests: XCTestCase {
    func testNormalizedBundleIDsTrimDedupeAndSort() {
        let normalized = SettingsExclusionList.normalizedBundleIDs([
            "  com.apple.Notes  ",
            "com.apple.TextEdit",
            "",
            "com.apple.Notes"
        ])

        XCTAssertEqual(normalized, ["com.apple.Notes", "com.apple.TextEdit"])
    }

    func testNormalizedRegexPatternsTrimDedupePreserveFirstSeenOrder() {
        let normalized = SettingsExclusionList.normalizedRegexPatterns([
            "  \\d{16}  ",
            "[A-Z]+",
            "\\d{16}",
            ""
        ])

        XCTAssertEqual(normalized, ["\\d{16}", "[A-Z]+"])
    }

    func testApplicationBundleURLsExtractBundleIDsAndIgnoreInvalidBundles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExclusionApps-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let notes = try makeAppBundle(root: root, name: "Notes", bundleID: "com.apple.Notes")
        let textEdit = try makeAppBundle(root: root, name: "TextEdit", bundleID: "com.apple.TextEdit")
        let invalid = root.appendingPathComponent("Invalid.app", isDirectory: true)
        try FileManager.default.createDirectory(at: invalid, withIntermediateDirectories: true)

        let bundleIDs = SettingsExclusionList.bundleIDs(fromApplicationURLs: [
            notes,
            invalid,
            textEdit,
            notes
        ])

        XCTAssertEqual(bundleIDs, ["com.apple.Notes", "com.apple.TextEdit"])
    }

    func testFriendlyAppNameUsesKnownFallbacksAndReadableBundleParts() {
        XCTAssertEqual(SettingsExclusionList.friendlyAppName(forBundleID: "com.bitwarden.desktop"), "Bitwarden")
        XCTAssertEqual(SettingsExclusionList.friendlyAppName(forBundleID: "com.lastpass.LastPass"), "LastPass")
        XCTAssertEqual(SettingsExclusionList.friendlyAppName(forBundleID: "com.example.SomeApp"), "SomeApp")
    }

    func testSensitiveTextPresetsExtractSelectionAndCustomPatterns() {
        let patterns = SensitiveTextPreset.creditCards.patterns + ["^internal-secret-"]

        XCTAssertEqual(SensitiveTextPreset.selectedIDs(in: patterns), [.creditCards])
        XCTAssertEqual(SensitiveTextPreset.customPatterns(from: patterns), ["^internal-secret-"])
    }

    func testSensitiveTextPresetsBuildNormalizedPatternList() {
        let patterns = SensitiveTextPreset.patterns(
            selectedIDs: [.privateKeys, .apiKeys],
            customPatterns: ["  ^internal-secret-  ", ""]
        )

        XCTAssertEqual(
            patterns,
            SettingsExclusionList.normalizedRegexPatterns(
                SensitiveTextPreset.apiKeys.patterns +
                    SensitiveTextPreset.privateKeys.patterns +
                    ["^internal-secret-"]
            )
        )
    }

    private func makeAppBundle(root: URL, name: String, bundleID: String) throws -> URL {
        let contents = root
            .appendingPathComponent("\(name).app", isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = contents.appendingPathComponent("Info.plist")
        let data = try PropertyListSerialization.data(
            fromPropertyList: [
                "CFBundleIdentifier": bundleID,
                "CFBundleName": name
            ],
            format: .xml,
            options: 0
        )
        try data.write(to: plist)
        return contents.deletingLastPathComponent()
    }
}
