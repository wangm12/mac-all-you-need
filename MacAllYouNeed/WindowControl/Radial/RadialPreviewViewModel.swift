import Core
import CoreGraphics
import Foundation

/// Drives the screen-sized radial preview overlay. Mirrors the coordinator's
/// proposed frame so the live preview matches the eventual window placement.
@MainActor
final class RadialPreviewViewModel: ObservableObject {
    @Published var proposedFrame: CGRect?

    func update(from coordinator: RadialMenuCoordinator, host: WindowControlCoordinator) {
        guard let cgFrame = coordinator.proposedFrame else {
            proposedFrame = nil
            return
        }
        proposedFrame = host.appKitOverlayFrame(for: cgFrame)
    }
}
