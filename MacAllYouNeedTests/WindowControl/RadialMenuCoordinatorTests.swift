import Core
import CoreGraphics
@testable import MacAllYouNeed
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

    @MainActor func testCommitCallsPerformerForTopHalf() {
        let performer = FakeRadialActionPerformer()
        let coord = RadialMenuCoordinator(actionPerformer: performer, frameResolver: FakeRadialFrameResolver())
        coord.open(at: .zero)
        coord.update(cursorAt: CGPoint(x: 0, y: -50))
        coord.commit()
        XCTAssertEqual(performer.performed.count, 1)
        XCTAssertEqual(performer.performed.first, .topHalf)
    }

    @MainActor func testCommitCallsPerformerForFillScreen() async {
        let performer = FakeRadialActionPerformer()
        let coord = RadialMenuCoordinator(actionPerformer: performer, frameResolver: FakeRadialFrameResolver())
        coord.open(at: .zero)
        let far = CGPoint(x: 0, y: -140)
        coord.update(cursorAt: far)
        try? await Task.sleep(for: .milliseconds(200))
        coord.update(cursorAt: far)
        coord.commit()
        XCTAssertEqual(performer.performed.count, 1)
        XCTAssertEqual(performer.performed.first, .maximize)
        XCTAssertEqual(coord.selection, .fullScreen)
    }

    @MainActor func testCommitCallsPerformerForFillScreenLongPullRight() async {
        let performer = FakeRadialActionPerformer()
        let coord = RadialMenuCoordinator(actionPerformer: performer, frameResolver: FakeRadialFrameResolver())
        coord.open(at: .zero)
        let far = CGPoint(x: 140, y: 0)
        coord.update(cursorAt: far)
        try? await Task.sleep(for: .milliseconds(200))
        coord.update(cursorAt: far)
        coord.commit()
        XCTAssertEqual(performer.performed.count, 1)
        XCTAssertEqual(performer.performed.first, .maximize)
        XCTAssertEqual(coord.selection, .fullScreen)
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
        coord.commit()
        XCTAssertEqual(performer.performed.count, 0)
    }

    @MainActor func testKeyboardSelectFillScreen() {
        let performer = FakeRadialActionPerformer()
        let coord = RadialMenuCoordinator(actionPerformer: performer, frameResolver: FakeRadialFrameResolver())
        coord.open(at: .zero)
        coord.select(action: .maximize)
        XCTAssertEqual(coord.selection, .fullScreen)
        coord.commit()
        XCTAssertEqual(performer.performed.first, .maximize)
    }

    @MainActor func testUpdateResolvesProposedFrame() {
        let coord = RadialMenuCoordinator(actionPerformer: FakeRadialActionPerformer(), frameResolver: FakeRadialFrameResolver())
        coord.open(at: .zero)
        coord.update(cursorAt: CGPoint(x: 0, y: -50))
        XCTAssertEqual(coord.proposedFrame, CGRect(x: 0, y: 0, width: 800, height: 600))
    }

    @MainActor func testUnavailabilityBlocksCommit() {
        let performer = FakeRadialActionPerformer()
        let coord = RadialMenuCoordinator(actionPerformer: performer, frameResolver: FakeRadialFrameResolver())
        coord.open(at: .zero)
        coord.update(cursorAt: CGPoint(x: 0, y: -50))
        coord.setUnavailability(.noMovableWindow)
        coord.commit()
        XCTAssertEqual(performer.performed.count, 0)
    }

    @MainActor func testCannotResizeBlocksCommit() {
        let performer = FakeRadialActionPerformer()
        let coord = RadialMenuCoordinator(actionPerformer: performer, frameResolver: FakeRadialFrameResolver())
        coord.open(at: .zero)
        coord.update(cursorAt: CGPoint(x: 0, y: -50))
        coord.setUnavailability(.cannotResize)
        coord.commit()
        XCTAssertEqual(performer.performed.count, 0)
    }
}
