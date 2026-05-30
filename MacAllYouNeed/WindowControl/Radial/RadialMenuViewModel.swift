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

    var selectedRingIndex: Int? {
        if case let .ring(index) = selection { return index }
        return nil
    }

    var isCenterSelected: Bool {
        selection == .center
    }

    func update(from coordinator: RadialMenuCoordinator) {
        isShown = coordinator.state != .idle
        selection = coordinator.selection
        proposedFrame = coordinator.proposedFrame
    }
}
