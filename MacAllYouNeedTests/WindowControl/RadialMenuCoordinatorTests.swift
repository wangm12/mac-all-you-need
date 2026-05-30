@testable import MacAllYouNeed
import Core
import CoreGraphics
import XCTest

@MainActor
final class FakeRadialActionPerformer: RadialActionPerforming {
    private(set) var performed: [WindowAction] = []
    func perform(action: WindowAction) { performed.append(action) }
}

@MainActor
final class FakeRadialFrameResolver: ProposedFrameResolving {
    func proposedFrame(for _: WindowAction) -> CGRect? {
        CGRect(x: 0, y: 0, width: 800, height: 600)
    }
}

final class RadialMenuCoordinatorTests: XCTestCase {
    @MainActor func testOpenSetsOpenState() {
        let coord = RadialMenuCoordinator(actionPerformer: FakeRadialActionPerformer(), frameResolver: FakeRadialFrameResolver())
        coord.open(at: CGPoint(x: 100, y: 100))
        if case let .open(center) = coord.state {
            XCTAssertEqual(center, CGPoint(x: 100, y: 100))
        } else {
            XCTFail("expected open state")
        }
    }

    @MainActor func testCommitCallsPerformer() {
        let performer = FakeRadialActionPerformer()
        let coord = RadialMenuCoordinator(actionPerformer: performer, frameResolver: FakeRadialFrameResolver())
        coord.open(at: .zero)
        coord.update(cursorAt: CGPoint(x: 0, y: -100)) // top = ring 0
        coord.commit()
        XCTAssertEqual(performer.performed.count, 1)
        XCTAssertEqual(performer.performed.first, .topHalf)
    }

    @MainActor func testCancelProducesNoAction() {
        let performer = FakeRadialActionPerformer()
        let coord = RadialMenuCoordinator(actionPerformer: performer, frameResolver: FakeRadialFrameResolver())
        coord.open(at: .zero)
        coord.cancel()
        XCTAssertEqual(performer.performed.count, 0)
        if case .cancelled = coord.state {} else { XCTFail("expected cancelled state") }
    }

    @MainActor func testNoSelectionCancelCommit() {
        let performer = FakeRadialActionPerformer()
        let coord = RadialMenuCoordinator(actionPerformer: performer, frameResolver: FakeRadialFrameResolver())
        coord.open(at: .zero)
        coord.update(cursorAt: CGPoint(x: 1, y: 0)) // within activation distance -> .none
        coord.commit()
        XCTAssertEqual(performer.performed.count, 0)
    }

    @MainActor func testUpdateResolvesProposedFrame() {
        let coord = RadialMenuCoordinator(actionPerformer: FakeRadialActionPerformer(), frameResolver: FakeRadialFrameResolver())
        coord.open(at: .zero)
        coord.update(cursorAt: CGPoint(x: 0, y: -100))
        XCTAssertEqual(coord.proposedFrame, CGRect(x: 0, y: 0, width: 800, height: 600))
    }
}
