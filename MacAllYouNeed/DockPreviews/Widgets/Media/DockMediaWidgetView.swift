import SwiftUI

/// Now Playing dock widget with progress bar and artwork tint (DockDoor MediaControlsEmbeddedView parity).
struct DockMediaWidgetView: View {
    var compact: Bool = false
    @ObservedObject private var media = DockMediaRemoteService.shared
    @State private var dominantColor: Color = .accentColor

    var body: some View {
        Group {
            if media.title.isEmpty, !media.hasActiveMedia {
                DockMediaControlsSkeleton()
            } else if compact {
                compactContent
            } else {
                fullContent
            }
        }
        .onAppear {
            media.activate()
            updateDominantColor()
        }
        .onDisappear { media.deactivate() }
        .onChange(of: media.artwork) { _ in updateDominantColor() }
    }

    private var fullContent: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                    transportControls
                }
                Spacer()
            }

            if media.duration > 0 {
                progressBar
                    .padding(.top, 8)
            }
        }
        .frame(minWidth: 280)
        .padding(4)
    }

    private var compactContent: some View {
        HStack(spacing: 10) {
            artworkView
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(media.title.isEmpty ? "Not Playing" : media.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(media.artist)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            transportControls
                .font(.body)
        }
        .frame(minWidth: 220)
        .padding(4)
    }

    private var transportControls: some View {
        HStack(spacing: compact ? 10 : 16) {
            Button { media.previousTrack() } label: {
                Image(systemName: "backward.fill")
            }
            .buttonStyle(.plain)
            Button { media.togglePlayPause() } label: {
                Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: compact ? 16 : 20)
            }
            .buttonStyle(.plain)
            Button { media.nextTrack() } label: {
                Image(systemName: "forward.fill")
            }
            .buttonStyle(.plain)
        }
        .font(compact ? .body : .title3)
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

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.15))
                    .frame(height: 3)
                Capsule()
                    .fill(dominantColor)
                    .frame(
                        width: media.duration > 0
                            ? geo.size.width * CGFloat(media.elapsedTime / media.duration)
                            : 0,
                        height: 3
                    )
            }
        }
        .frame(height: 3)
    }

    private func updateDominantColor() {
        guard let artwork = media.artwork else {
            dominantColor = .accentColor
            return
        }
        Task.detached(priority: .utility) {
            let color = dominantColorFrom(artwork)
            await MainActor.run { dominantColor = color }
        }
    }

    private func dominantColorFrom(_ image: NSImage) -> Color {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .accentColor
        }
        let size = CGSize(width: 8, height: 8)
        let ctx = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        ctx?.draw(cgImage, in: CGRect(origin: .zero, size: size))
        guard let data = ctx?.data else { return .accentColor }
        let ptr = data.bindMemory(to: UInt8.self, capacity: Int(size.width * size.height) * 4)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        let pixels = Int(size.width * size.height)
        for i in 0..<pixels {
            r += CGFloat(ptr[i * 4]) / 255
            g += CGFloat(ptr[i * 4 + 1]) / 255
            b += CGFloat(ptr[i * 4 + 2]) / 255
        }
        return Color(red: r / CGFloat(pixels), green: g / CGFloat(pixels), blue: b / CGFloat(pixels))
    }
}
