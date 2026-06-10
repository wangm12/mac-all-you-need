import AVKit
import SwiftUI

/// Plays a bundled onboarding clip when present; otherwise renders the SwiftUI fallback preview.
struct OnboardingLoopingMediaView<Fallback: View>: View {
    let resourceName: String
    let resourceExtension: String
    let accessibilityLabel: String
    @ViewBuilder let fallback: () -> Fallback

    var body: some View {
        Group {
            if let url = bundleURL {
                OnboardingVideoPlayerView(url: url)
            } else {
                fallback()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 192)
        .clipShape(RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
        )
        .accessibilityLabel(accessibilityLabel)
    }

    private var bundleURL: URL? {
        if let nested = Bundle.main.url(
            forResource: resourceName,
            withExtension: resourceExtension,
            subdirectory: "Onboarding"
        ) {
            return nested
        }
        return Bundle.main.url(forResource: resourceName, withExtension: resourceExtension)
    }
}

private struct OnboardingVideoPlayerView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> AVPlayerView {
        let player = AVQueuePlayer()
        let item = AVPlayerItem(url: url)
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: item)
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.showsFullScreenToggleButton = false
        view.player = player
        player.isMuted = true
        player.play()
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {}

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        nsView.player?.pause()
        coordinator.looper?.disableLooping()
        coordinator.looper = nil
    }

    final class Coordinator {
        var looper: AVPlayerLooper?
    }
}
