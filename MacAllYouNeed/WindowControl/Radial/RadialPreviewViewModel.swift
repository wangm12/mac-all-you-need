import Core
import CoreGraphics
import Foundation

/// Drives the screen-sized radial preview overlay. Mirrors the coordinator's
/// proposed frame so the live preview matches the eventual window placement.
@MainActor
final class RadialPreviewViewModel: ObservableObject {
    @Published var proposedFrame: CGRect?
    @Published var fullScreenBlend: CGFloat = 0
    @Published var previewOpacity: CGFloat = 0
    @Published var previewCornerRadius: CGFloat = 13

    func update(from coordinator: RadialMenuCoordinator, menuViewModel: RadialMenuViewModel, host: WindowControlCoordinator) {
        fullScreenBlend = menuViewModel.renderState.fullScreenBlend
        previewOpacity = menuViewModel.renderState.previewOpacity
        previewCornerRadius = menuViewModel.renderState.previewCornerRadius

        guard let cgFrame = coordinator.proposedFrame,
              coordinator.unavailability == nil,
              menuViewModel.renderState.previewOpacity > 0.01
        else {
            proposedFrame = nil
            return
        }

        let damped = menuViewModel.renderState.dampedPreviewFrame
        let frameForOverlay = damped.isNull || damped.isEmpty ? cgFrame : damped
        proposedFrame = host.appKitOverlayFrame(for: frameForOverlay)
    }
}
