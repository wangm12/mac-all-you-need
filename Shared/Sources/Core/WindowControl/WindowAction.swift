import Foundation

public enum WindowAction: String, CaseIterable, Codable, Sendable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case maximize
    case almostMaximize
    case center
    case restore
    case nextDisplay
    case previousDisplay
    case nextSpace
    case previousSpace

    public var title: String {
        switch self {
        case .leftHalf:
            "Left half"
        case .rightHalf:
            "Right half"
        case .topHalf:
            "Top half"
        case .bottomHalf:
            "Bottom half"
        case .topLeft:
            "Top left"
        case .topRight:
            "Top right"
        case .bottomLeft:
            "Bottom left"
        case .bottomRight:
            "Bottom right"
        case .maximize:
            "Maximize"
        case .almostMaximize:
            "Almost maximize"
        case .center:
            "Center"
        case .restore:
            "Restore"
        case .nextDisplay:
            "Next display"
        case .previousDisplay:
            "Previous display"
        case .nextSpace:
            "Next space"
        case .previousSpace:
            "Previous space"
        }
    }

    public var symbolName: String {
        switch self {
        case .leftHalf:
            "rectangle.lefthalf.filled"
        case .rightHalf:
            "rectangle.righthalf.filled"
        case .topHalf:
            "rectangle.tophalf.filled"
        case .bottomHalf:
            "rectangle.bottomhalf.filled"
        case .topLeft:
            "rectangle.topthird.inset.filled"
        case .topRight:
            "rectangle.topthird.inset.filled"
        case .bottomLeft:
            "rectangle.bottomthird.inset.filled"
        case .bottomRight:
            "rectangle.bottomthird.inset.filled"
        case .maximize:
            "arrow.up.left.and.arrow.down.right"
        case .almostMaximize:
            "rectangle.inset.filled"
        case .center:
            "rectangle.center.inset.filled"
        case .restore:
            "arrow.uturn.backward"
        case .nextDisplay:
            "rectangle.portrait.arrowtriangle.2.outward"
        case .previousDisplay:
            "rectangle.portrait.arrowtriangle.2.inward"
        case .nextSpace:
            "square.grid.3x1.below.line.grid.1x2"
        case .previousSpace:
            "square.grid.3x1.left.filled.below.line.grid.1x2"
        }
    }

    public static var mvpActions: [WindowAction] {
        allCases
    }
}
