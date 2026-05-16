import FeatureCore
import SwiftUI

enum DownloaderDescriptor {
    static func descriptor() -> FeatureDescriptor {
        FeatureDescriptor(
            id: .downloader,
            displayName: "Video Downloader",
            icon: "arrow.down.circle",
            summary: "Universal video downloader (yt-dlp + ffmpeg).",
            detailDescription: "Paste any video URL and the downloader handles formats, fragments, cookies, and re-encoding.",
            assetPacks: [AssetPack(id: "downloader", bundledManifestKey: "downloader")],
            activator: NoopFeatureActivator()
        )
    }
}
