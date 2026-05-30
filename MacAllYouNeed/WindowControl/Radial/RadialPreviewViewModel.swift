import Core
import CoreGraphics
import Foundation

/// Drives the screen-sized radial preview overlay. Mirrors the coordinator's
/// proposed frame so the live preview matches the eventual window placement.
@MainActor
final class RadialPreviewViewModel: ObservableObject {
    @Published var proposedFrame: CGRect?

    func update(from coordinator: RadialMenuCoordinator) {
        proposedFrame = coordinator.proposedFrame
    }
}
