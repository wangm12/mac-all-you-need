import AppKit
import Combine
import Foundation
import MediaPlayer

/// Now Playing state (DockDoor `MediaRemoteService` GPL-free subset).
@MainActor
final class DockMediaRemoteService: ObservableObject {
    static let shared = DockMediaRemoteService()

    @Published private(set) var title: String = ""
    @Published private(set) var artist: String = ""
    @Published private(set) var album: String = ""
    @Published private(set) var artwork: NSImage?
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    private var observers: [NSObjectProtocol] = []
    private var isActive = false

    var hasActiveMedia: Bool { !title.isEmpty }

    private init() {}

    func activate() {
        guard !isActive else { return }
        isActive = true
        refreshFromNowPlayingCenter()
        let center = DistributedNotificationCenter.default()
        let names = [
            "com.apple.Music.playerInfo",
            "com.spotify.client.PlaybackStateChanged",
            "com.apple.itunesmq.playbackStateChanged",
        ]
        for name in names {
            let token = center.addObserver(
                forName: NSNotification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.refreshFromNowPlayingCenter() }
            }
            observers.append(token)
        }
    }

    func deactivate() {
        isActive = false
        let center = DistributedNotificationCenter.default()
        for token in observers {
            center.removeObserver(token)
        }
        observers.removeAll()
    }

    func togglePlayPause() { postMediaKey(16) }
    func nextTrack() { postMediaKey(17) }
    func previousTrack() { postMediaKey(18) }

    private func refreshFromNowPlayingCenter() {
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        title = info?[MPMediaItemPropertyTitle] as? String ?? ""
        artist = info?[MPMediaItemPropertyArtist] as? String ?? ""
        album = info?[MPMediaItemPropertyAlbumTitle] as? String ?? ""
        duration = info?[MPMediaItemPropertyPlaybackDuration] as? TimeInterval ?? 0
        elapsedTime = info?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? TimeInterval ?? 0
        isPlaying = (info?[MPNowPlayingInfoPropertyPlaybackRate] as? Double ?? 0) > 0
        if let art = info?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork {
            artwork = art.image(at: CGSize(width: 128, height: 128))
        } else {
            artwork = nil
        }
    }

    private func postMediaKey(_ keyCode: Int) {
        let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: false)
        keyDown?.flags = .maskSecondaryFn
        keyUp?.flags = .maskSecondaryFn
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
