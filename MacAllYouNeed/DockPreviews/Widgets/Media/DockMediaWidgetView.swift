import SwiftUI

/// Now Playing dock widget (DockDoor `MediaControlsEmbeddedView` subset).
struct DockMediaWidgetView: View {
    @ObservedObject private var media = DockMediaRemoteService.shared

    var body: some View {
        HStack(spacing: 12) {
            artworkView
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(media.title.isEmpty ? "Not Playing" : media.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(media.artist.isEmpty ? "Open Music or Spotify" : media.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 16) {
                    Button { media.previousTrack() } label: {
                        Image(systemName: "backward.fill")
                    }
                    .buttonStyle(.plain)
                    Button { media.togglePlayPause() } label: {
                        Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.plain)
                    Button { media.nextTrack() } label: {
                        Image(systemName: "forward.fill")
                    }
                    .buttonStyle(.plain)
                }
                .font(.title3)
            }
            Spacer()
        }
        .frame(minWidth: 280)
        .padding(4)
        .onAppear { media.activate() }
        .onDisappear { media.deactivate() }
    }

    @ViewBuilder
    private var artworkView: some View {
        if let artwork = media.artwork {
            Image(nsImage: artwork)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Color.primary.opacity(0.08)
                Image(systemName: "music.note")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
