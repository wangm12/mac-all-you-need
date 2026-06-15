import CoreGraphics
import Foundation

public struct WindowSnapshot: Equatable, Sendable {
    public let frame: CGRect
    public let isResizable: Bool
    public let isMovable: Bool
    public let isSupportedForWindowControl: Bool
    public let enhancedUserInterfaceEnabled: Bool?

    public init(
        frame: CGRect,
        isResizable: Bool,
        isMovable: Bool,
        isSupportedForWindowControl: Bool,
        enhancedUserInterfaceEnabled: Bool?
    ) {
        self.frame = frame
        self.isResizable = isResizable
        self.isMovable = isMovable
        self.isSupportedForWindowControl = isSupportedForWindowControl
        self.enhancedUserInterfaceEnabled = enhancedUserInterfaceEnabled
    }
}

public extension WindowMovableElement {
    func snapshot() -> WindowSnapshot {
        WindowSnapshot(
            frame: frame,
            isResizable: isResizable,
            isMovable: isMovable,
            isSupportedForWindowControl: isSupportedForWindowControl,
            enhancedUserInterfaceEnabled: enhancedUserInterfaceEnabled
        )
    }
}
