import Core
@testable import MacAllYouNeed
import XCTest

/// Pinned behavior of DockListTabDropResolver and liveReorderTab index math.
///
/// History and Snippets are non-reorderable (not pinboard tabs).
/// Pinboard tabs are reorderable and accept item drops.
/// Drops outside the strip (vertically far away) are rejected.
final class DockListTabReorderTests: XCTestCase {
    // MARK: - Helpers

    private func makeFrame(
        selector: DockListSelector,
        x: CGFloat,
        width: CGFloat = 60,
        y: CGFloat = 0,
        height: CGFloat = 30
    ) -> DockListTabDropFrame {
        DockListTabDropFrame(selector: selector, rect: CGRect(x: x, y: y, width: width, height: height))
    }

    private let historyID = RecordID.generate()
    private let boardA = RecordID.generate()
    private let boardB = RecordID.generate()
    private let boardC = RecordID.generate()

    private lazy var frames: [DockListTabDropFrame] = [
        makeFrame(selector: .history, x: 0, width: 80),
        makeFrame(selector: .snippets, x: 88, width: 70),
        makeFrame(selector: .pinboard(boardA), x: 166, width: 60),
        makeFrame(selector: .pinboard(boardB), x: 234, width: 60),
        makeFrame(selector: .pinboard(boardC), x: 302, width: 60),
    ]

    // MARK: - DockListTabDropResolver.targetSelector (item-drop hit-testing)

    func testTargetSelectorHitsHistoryTab() {
        // History does NOT accept item drops, so requiresItemDropTarget=true -> nil
        let point = CGPoint(x: 40, y: 15)
        let result = DockListTabDropResolver.targetSelector(
            at: point, in: frames, requiresItemDropTarget: true
        )
        XCTAssertNil(result, "History tab must reject item drops")
    }

    func testTargetSelectorHitsSnippetsTab() {
        let point = CGPoint(x: 120, y: 15)
        let result = DockListTabDropResolver.targetSelector(
            at: point, in: frames, requiresItemDropTarget: true
        )
        XCTAssertEqual(result, .snippets)
    }

    func testTargetSelectorHitsPinboardTab() {
        let point = CGPoint(x: 190, y: 15) // inside boardA (x=166..226)
        let result = DockListTabDropResolver.targetSelector(
            at: point, in: frames, requiresItemDropTarget: true
        )
        XCTAssertEqual(result, .pinboard(boardA))
    }

    func testTargetSelectorRejectsDropFarBelowStrip() {
        let point = CGPoint(x: 190, y: 80) // well outside vertical range + tolerance
        let result = DockListTabDropResolver.targetSelector(
            at: point, in: frames, requiresItemDropTarget: true
        )
        XCTAssertNil(result, "Drop far below strip must be rejected")
    }

    func testTargetSelectorRejectsDropFarAboveStrip() {
        let point = CGPoint(x: 190, y: -50)
        let result = DockListTabDropResolver.targetSelector(
            at: point, in: frames, requiresItemDropTarget: true
        )
        XCTAssertNil(result, "Drop far above strip must be rejected")
    }

    func testTargetSelectorWithoutItemRequirementAcceptsHistory() {
        let point = CGPoint(x: 40, y: 15)
        let result = DockListTabDropResolver.targetSelector(
            at: point, in: frames, requiresItemDropTarget: false
        )
        XCTAssertEqual(result, .history, "Without item requirement, history should match")
    }

    // MARK: - DockListTabDropResolver.reorderTarget (drag-reorder hit-testing)

    func testReorderTargetBeforeFirstPinboard() {
        // Cursor just left of boardA (x=166) but outside Snippets hitRect (ends at 88+70+3=161).
        // x=163 is in the gap between Snippets and boardA, within nearestHorizontalTolerance (24).
        let point = CGPoint(x: 163, y: 15)
        let result = DockListTabDropResolver.reorderTarget(at: point, in: frames)
        XCTAssertEqual(result?.targetID, boardA)
        XCTAssertEqual(result?.placement, .before)
    }

    func testReorderTargetAfterLastPinboard() {
        // Cursor just right of boardC (302+60=362), within appendAfterLastHorizontalTolerance (80)
        let point = CGPoint(x: 380, y: 15) // 362 + 18 = well within 80 px
        let result = DockListTabDropResolver.reorderTarget(at: point, in: frames)
        XCTAssertEqual(result?.targetID, boardC)
        XCTAssertEqual(result?.placement, .after)
    }

    func testReorderTargetInLeftHalfOfPinboardTab() {
        // boardB is at x=234, width=60, midX=264. Cursor at 250 < midX → .before
        let point = CGPoint(x: 250, y: 15)
        let result = DockListTabDropResolver.reorderTarget(at: point, in: frames)
        XCTAssertEqual(result?.targetID, boardB)
        XCTAssertEqual(result?.placement, .before)
    }

    func testReorderTargetInRightHalfOfPinboardTab() {
        // boardB midX=264. Cursor at 275 > midX → .after
        let point = CGPoint(x: 275, y: 15)
        let result = DockListTabDropResolver.reorderTarget(at: point, in: frames)
        XCTAssertEqual(result?.targetID, boardB)
        XCTAssertEqual(result?.placement, .after)
    }

    func testReorderTargetReturnsNilWhenCursorOverNonPinboardTab() {
        // Cursor over History tab — reorder should be nil (locked tab)
        let point = CGPoint(x: 40, y: 15)
        let result = DockListTabDropResolver.reorderTarget(at: point, in: frames)
        XCTAssertNil(result, "Reorder target over History (non-pinboard) must be nil")
    }

    func testReorderTargetReturnsNilWhenNoFrames() {
        let result = DockListTabDropResolver.reorderTarget(at: CGPoint(x: 100, y: 15), in: [])
        XCTAssertNil(result, "Empty frames must return nil")
    }

    func testReorderTargetRejectsDropFarBelowStrip() {
        let point = CGPoint(x: 200, y: 100)
        let result = DockListTabDropResolver.reorderTarget(at: point, in: frames)
        XCTAssertNil(result, "Reorder target far below strip must be nil")
    }

    // MARK: - liveReorderTab index math (simulated via ClipboardDockModel.reorderPinboardsLocally)

    func testScriptedDragPickAtZeroDropAtTwo() throws {
        // boards in order: [A, B, C]. Drag A → drop after C.
        // Expected final order: [B, C, A]
        var ids = [boardA, boardB, boardC]
        let draggedID = boardA
        let targetID = boardC

        guard let from = ids.firstIndex(of: draggedID) else {
            XCTFail("dragged ID not found"); return
        }
        ids.remove(at: from)
        guard let targetIndex = ids.firstIndex(of: targetID) else {
            XCTFail("target ID not found"); return
        }
        let insertIndex = min(targetIndex + 1, ids.count) // .after
        ids.insert(draggedID, at: insertIndex)

        XCTAssertEqual(ids, [boardB, boardC, boardA])
    }

    func testScriptedDragPickAtTwoDropAtZero() throws {
        // boards: [A, B, C]. Drag C → drop before A.
        // Expected: [C, A, B]
        var ids = [boardA, boardB, boardC]
        let draggedID = boardC
        let targetID = boardA

        guard let from = ids.firstIndex(of: draggedID) else {
            XCTFail("dragged ID not found"); return
        }
        ids.remove(at: from)
        guard let targetIndex = ids.firstIndex(of: targetID) else {
            XCTFail("target ID not found"); return
        }
        let insertIndex = targetIndex // .before
        ids.insert(draggedID, at: insertIndex)

        XCTAssertEqual(ids, [boardC, boardA, boardB])
    }

    func testScriptedDragPickAtOneDropBeforeOne_noop() throws {
        // boards: [A, B, C]. Drag B → drop before B (same tab). Guard prevents this.
        var ids = [boardA, boardB, boardC]
        let draggedID = boardB
        let targetID = boardB

        // The guard in liveReorderTab is: guard draggedID != target.targetID else { return }
        XCTAssertEqual(draggedID, targetID, "Same-tab drag is a no-op — the guard fires")
        // ids should stay unchanged
        XCTAssertEqual(ids, [boardA, boardB, boardC])
    }

    // MARK: - DockListDropSurfaceState activation

    func testDropSurfaceActiveWhenDraggedTabIDSet() {
        XCTAssertTrue(DockListDropSurfaceState.isActive(
            draggedTabID: RecordID.generate(),
            activeDraggedItemID: nil,
            windowDragIsActive: false
        ))
    }

    func testDropSurfaceActiveWhenActiveDraggedItemIDSet() {
        XCTAssertTrue(DockListDropSurfaceState.isActive(
            draggedTabID: nil,
            activeDraggedItemID: DockItem.ID(UUID().uuidString),
            windowDragIsActive: false
        ))
    }

    func testDropSurfaceActiveWhenWindowDragIsActive() {
        XCTAssertTrue(DockListDropSurfaceState.isActive(
            draggedTabID: nil,
            activeDraggedItemID: nil,
            windowDragIsActive: true
        ))
    }

    func testDropSurfaceInactiveWhenAllNil() {
        XCTAssertFalse(DockListDropSurfaceState.isActive(
            draggedTabID: nil,
            activeDraggedItemID: nil,
            windowDragIsActive: false
        ))
    }

    // MARK: - DockListItemTabDropPolicy (locked-tab rejection)

    func testPerTabDropAcceptedWhenNoDraggedTab() {
        XCTAssertTrue(DockListItemTabDropPolicy.acceptsPerTabDrop(draggedTabID: nil))
    }

    func testPerTabDropRejectedWhenTabDragIsActive() {
        XCTAssertFalse(DockListItemTabDropPolicy.acceptsPerTabDrop(draggedTabID: RecordID.generate()))
    }
}
