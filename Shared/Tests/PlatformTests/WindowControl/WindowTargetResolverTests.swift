import CoreGraphics
@testable import Platform
import XCTest

final class WindowTargetResolverTests: XCTestCase {
    func testMatchesTopmostCGWindowToAXCandidateByPIDAndFrameTolerance() {
        let resolver = WindowTargetResolver(
            ownBundleIdentifier: "com.macallyouneed",
            visibleFrames: [CGRect(x: 0, y: 0, width: 1440, height: 875)]
        )
        let top = window(id: 10, pid: 200, bounds: CGRect(x: 100, y: 100, width: 800, height: 600))
        let behind = window(id: 11, pid: 201, bounds: CGRect(x: 100, y: 100, width: 800, height: 600))
        let candidate = FakeTargetElement(
            processIdentifier: 200,
            frame: CGRect(x: 101, y: 99, width: 800, height: 600)
        )

        let target = resolver.resolveTopmostWindow(
            at: CGPoint(x: 200, y: 200),
            windows: [top, behind],
            candidates: [candidate]
        )

        XCTAssertEqual(target?.windowID, 10)
        XCTAssertTrue(target?.element === candidate)
    }

    func testIgnoresDesktopNonLayerZeroOwnBundleAndMenuBarWindows() {
        let resolver = WindowTargetResolver(
            ownBundleIdentifier: "com.macallyouneed",
            visibleFrames: [CGRect(x: 0, y: 0, width: 1440, height: 875)]
        )
        let desktop = window(id: 1, pid: 200, isDesktopElement: true)
        let overlay = window(id: 2, pid: 201, ownerBundleIdentifier: "com.macallyouneed")
        let nonLayerZero = window(id: 3, pid: 202, layer: 25)
        let normal = window(id: 4, pid: 203)
        let menuBarWindow = window(
            id: 5,
            pid: 203,
            bounds: CGRect(x: 0, y: 870, width: 500, height: 60)
        )
        let candidate = FakeTargetElement(processIdentifier: 203)

        let menuBarTarget = resolver.resolveTopmostWindow(
            at: CGPoint(x: 50, y: 890),
            windows: [menuBarWindow],
            candidates: [FakeTargetElement(processIdentifier: 203, frame: menuBarWindow.bounds)]
        )
        let normalTarget = resolver.resolveTopmostWindow(
            at: CGPoint(x: 50, y: 50),
            windows: [desktop, overlay, nonLayerZero, normal],
            candidates: [candidate]
        )

        XCTAssertNil(menuBarTarget)
        XCTAssertEqual(normalTarget?.windowID, 4)
    }

    func testReturnsNilWhenFrameMatchIsAmbiguous() {
        let resolver = WindowTargetResolver(
            ownBundleIdentifier: "com.macallyouneed",
            visibleFrames: [CGRect(x: 0, y: 0, width: 1440, height: 875)]
        )
        let metadata = window(id: 10, pid: 200, bounds: CGRect(x: 100, y: 100, width: 800, height: 600))
        let first = FakeTargetElement(processIdentifier: 200, frame: metadata.bounds)
        let second = FakeTargetElement(processIdentifier: 200, frame: metadata.bounds)

        let target = resolver.resolveTopmostWindow(
            at: CGPoint(x: 200, y: 200),
            windows: [metadata],
            candidates: [first, second]
        )

        XCTAssertNil(target)
    }

    func testReturnsNilWhenCandidateFrameIsOutsideTolerance() {
        let resolver = WindowTargetResolver(
            ownBundleIdentifier: "com.macallyouneed",
            visibleFrames: [CGRect(x: 0, y: 0, width: 1440, height: 875)],
            frameTolerance: 4
        )
        let metadata = window(id: 10, pid: 200, bounds: CGRect(x: 100, y: 100, width: 800, height: 600))
        let candidate = FakeTargetElement(
            processIdentifier: 200,
            frame: CGRect(x: 110, y: 100, width: 800, height: 600)
        )

        let target = resolver.resolveTopmostWindow(
            at: CGPoint(x: 200, y: 200),
            windows: [metadata],
            candidates: [candidate]
        )

        XCTAssertNil(target)
    }

    private func window(
        id: CGWindowID,
        pid: pid_t,
        bounds: CGRect = CGRect(x: 0, y: 0, width: 500, height: 500),
        layer: Int = 0,
        ownerBundleIdentifier: String = "com.example.App",
        isDesktopElement: Bool = false
    ) -> WindowTargetWindowInfo {
        WindowTargetWindowInfo(
            windowID: id,
            processIdentifier: pid,
            bounds: bounds,
            layer: layer,
            ownerBundleIdentifier: ownerBundleIdentifier,
            isDesktopElement: isDesktopElement
        )
    }
}

private final class FakeTargetElement: WindowTargetElement {
    let processIdentifier: pid_t
    var frame: CGRect
    let isResizable = true
    let isMovable = true
    let isSupportedForWindowControl = true
    let enhancedUserInterfaceEnabled: Bool? = nil

    init(processIdentifier: pid_t, frame: CGRect = CGRect(x: 0, y: 0, width: 500, height: 500)) {
        self.processIdentifier = processIdentifier
        self.frame = frame
    }

    func setEnhancedUserInterfaceEnabled(_ enabled: Bool) -> Bool { true }
    func setPosition(_ position: CGPoint) -> Bool { true }
    func setSize(_ size: CGSize) -> Bool { true }
}
