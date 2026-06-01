import Core
import CoreGraphics
import Foundation

/// Observable bridge between `RadialMenuCoordinator` state and the SwiftUI
/// radial view hosted in the NSPanel.
@MainActor
final class RadialMenuViewModel: ObservableObject {
    @Published var isShown = false
    @Published var selection: RadialSelectionMath.Selection = .none
    @Published var proposedFrame: CGRect?
    @Published var showsNoTargetWarning = false

    var selectedRingIndex: Int? {
        if case let .ring(index) = selection { return index }
        return nil
    }

    var isCenterSelected: Bool {
        selection == .center
    }

    var isCloseZoneSelected: Bool {
        selection == .cancel
    }

    func update(from coordinator: RadialMenuCoordinator, hasTargetWindow: Bool) {
        isShown = coordinator.state != .idle
        selection = coordinator.selection
        proposedFrame = coordinator.proposedFrame
        showsNoTargetWarning = isShown && !hasTargetWindow
    }
}
