import XCTest
@testable import Core

final class OrganizerPreferenceStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "OrganizerPrefTest-\(UUID())"
        return UserDefaults(suiteName: suite)!
    }

    func testSaveAndLoadCorrections() {
        let store = OrganizerPreferenceStore(defaults: makeDefaults())
        XCTAssertTrue(store.loadCorrections().isEmpty)
        store.saveCorrection(FolderCorrection(originalName: "IMG_1", correctedName: "Invoice", folderPath: "/tmp"))
        let loaded = store.loadCorrections()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.correctedName, "Invoice")
    }

    func testSaveAndLoadBookmark() {
        let store = OrganizerPreferenceStore(defaults: makeDefaults())
        XCTAssertNil(store.loadBookmark(forKey: "downloads"))
        let data = Data([1, 2, 3])
        store.saveBookmark(data: data, forKey: "downloads")
        XCTAssertEqual(store.loadBookmark(forKey: "downloads"), data)
    }
}
