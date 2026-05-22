@testable import MacAllYouNeed
import Core
import XCTest

/// Golden tests for multi-select and action sequences.
/// Tests pin selection-state changes and the action commands emitted by
/// the presentation-layer logic without requiring live UI.
final class DownloadsListSelectionTests: XCTestCase {

    // MARK: - Fixtures

    private func makeRecords(count: Int = 5) -> [DownloadRecord] {
        (0 ..< count).map { i in
            DownloadRecord(
                url: "https://example.com/video-\(i)",
                title: "Video \(i)",
                destinationPath: "/tmp/video\(i).mp4",
                state: i == 3 ? .completed : .running
            )
        }
    }

    // MARK: - Single tap selects row

    func testSingleTapSelectsOnlyTappedRow() {
        let records = makeRecords()
        let id = records[1].id.rawValue

        var selectedIDs: Set<String> = []
        var anchorID: String? = nil

        DownloadsListSelectionController.applyTap(
            id: id,
            visibleRows: records,
            selectedIDs: &selectedIDs,
            anchorID: &anchorID,
            modifiers: []
        )

        XCTAssertEqual(selectedIDs, [id])
        XCTAssertEqual(anchorID, id)
    }

    // MARK: - Second tap on same row deselects

    func testSecondTapOnSameRowClearsSelection() {
        let records = makeRecords()
        let id = records[1].id.rawValue

        var selectedIDs: Set<String> = [id]
        var anchorID: String? = id

        DownloadsListSelectionController.applyTap(
            id: id,
            visibleRows: records,
            selectedIDs: &selectedIDs,
            anchorID: &anchorID,
            modifiers: []
        )

        XCTAssertTrue(selectedIDs.isEmpty)
        XCTAssertNil(anchorID)
    }

    // MARK: - Command-tap toggles row in/out of selection

    func testCommandTapAddsRowToExistingSelection() {
        let records = makeRecords()
        let id0 = records[0].id.rawValue
        let id2 = records[2].id.rawValue

        var selectedIDs: Set<String> = [id0]
        var anchorID: String? = id0

        DownloadsListSelectionController.applyTap(
            id: id2,
            visibleRows: records,
            selectedIDs: &selectedIDs,
            anchorID: &anchorID,
            modifiers: .command
        )

        XCTAssertEqual(selectedIDs, [id0, id2])
    }

    func testCommandTapRemovesAlreadySelectedRow() {
        let records = makeRecords()
        let id0 = records[0].id.rawValue
        let id2 = records[2].id.rawValue

        var selectedIDs: Set<String> = [id0, id2]
        var anchorID: String? = id0

        DownloadsListSelectionController.applyTap(
            id: id2,
            visibleRows: records,
            selectedIDs: &selectedIDs,
            anchorID: &anchorID,
            modifiers: .command
        )

        XCTAssertEqual(selectedIDs, [id0])
    }

    // MARK: - Shift-tap selects contiguous range

    func testShiftTapSelectsRangeFromAnchorToTarget() {
        let records = makeRecords(count: 5)
        let anchor = records[1].id.rawValue
        let target = records[4].id.rawValue
        let expected = Set(records[1 ... 4].map(\.id.rawValue))

        var selectedIDs: Set<String> = [anchor]
        var anchorID: String? = anchor

        DownloadsListSelectionController.applyTap(
            id: target,
            visibleRows: records,
            selectedIDs: &selectedIDs,
            anchorID: &anchorID,
            modifiers: .shift
        )

        XCTAssertEqual(selectedIDs, expected)
    }

    func testShiftTapFromHigherToLowerIndexSelectsCorrectRange() {
        let records = makeRecords(count: 5)
        let anchor = records[4].id.rawValue
        let target = records[1].id.rawValue
        let expected = Set(records[1 ... 4].map(\.id.rawValue))

        var selectedIDs: Set<String> = [anchor]
        var anchorID: String? = anchor

        DownloadsListSelectionController.applyTap(
            id: target,
            visibleRows: records,
            selectedIDs: &selectedIDs,
            anchorID: &anchorID,
            modifiers: .shift
        )

        XCTAssertEqual(selectedIDs, expected)
    }

    // MARK: - Select-all

    func testSelectAllSelectsEveryVisibleRow() {
        let records = makeRecords(count: 4)
        var selectedIDs: Set<String> = []
        var anchorID: String? = nil

        DownloadsListSelectionController.applySelectAll(
            visibleRows: records,
            selectedIDs: &selectedIDs,
            anchorID: &anchorID
        )

        XCTAssertEqual(selectedIDs, Set(records.map(\.id.rawValue)))
        XCTAssertEqual(anchorID, records.first?.id.rawValue)
    }

    // MARK: - Escape clears selection

    func testEscapeKeyWhenSelectionNonEmptyReturnsTrueAndClearsSelection() {
        let records = makeRecords()
        var selectedIDs: Set<String> = [records[0].id.rawValue, records[1].id.rawValue]
        var anchorID: String? = records[0].id.rawValue

        let consumed = DownloadsListSelectionController.applyEscape(
            selectedIDs: &selectedIDs,
            anchorID: &anchorID
        )

        XCTAssertTrue(consumed)
        XCTAssertTrue(selectedIDs.isEmpty)
        XCTAssertNil(anchorID)
    }

    func testEscapeKeyWhenSelectionEmptyReturnsFalse() {
        var selectedIDs: Set<String> = []
        var anchorID: String? = nil

        let consumed = DownloadsListSelectionController.applyEscape(
            selectedIDs: &selectedIDs,
            anchorID: &anchorID
        )

        XCTAssertFalse(consumed)
    }

    // MARK: - DownloadJobRowActionPresentation state -> command mapping

    func testPrimaryActionTitlesMatchExpectedCommands() {
        XCTAssertEqual(DownloadJobRowActionPresentation.primaryActionTitle(for: .running), "Pause")
        XCTAssertEqual(DownloadJobRowActionPresentation.primaryActionTitle(for: .paused), "Resume")
        XCTAssertEqual(DownloadJobRowActionPresentation.primaryActionTitle(for: .queued), "Cancel")
        XCTAssertEqual(DownloadJobRowActionPresentation.primaryActionTitle(for: .completed), "Open Folder")
        XCTAssertEqual(DownloadJobRowActionPresentation.primaryActionTitle(for: .failed), "Retry")
    }

    func testOnlyFailedStateIsMarkedRetryable() {
        XCTAssertTrue(DownloadJobRowActionPresentation.isRetryable(.failed))
        XCTAssertFalse(DownloadJobRowActionPresentation.isRetryable(.running))
        XCTAssertFalse(DownloadJobRowActionPresentation.isRetryable(.queued))
        XCTAssertFalse(DownloadJobRowActionPresentation.isRetryable(.completed))
        XCTAssertFalse(DownloadJobRowActionPresentation.isRetryable(.paused))
    }

    func testPrimaryActionSymbolsMatchIntendedSFSymbols() {
        XCTAssertEqual(DownloadJobRowActionPresentation.primaryActionSymbol(for: .running), "pause.fill")
        XCTAssertEqual(DownloadJobRowActionPresentation.primaryActionSymbol(for: .paused), "play.fill")
        XCTAssertEqual(DownloadJobRowActionPresentation.primaryActionSymbol(for: .queued), "xmark")
        XCTAssertEqual(DownloadJobRowActionPresentation.primaryActionSymbol(for: .completed), "folder")
        XCTAssertEqual(DownloadJobRowActionPresentation.primaryActionSymbol(for: .failed), "arrow.counterclockwise")
    }
}
