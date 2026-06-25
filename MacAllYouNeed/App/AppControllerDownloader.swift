import AppKit
import Foundation

extension AppController {
    /// Handles `mayn://companion/...` opened by the Chrome extension to cold-launch
    /// the app and/or enqueue a download.
    func handleCompanionURL(_ url: URL) {
        guard let action = CompanionDownloadDeepLink.parse(url) else { return }
        Task { @MainActor in
            await downloader.startDispatchServer()
            switch action {
            case .wake:
                break
            case let .download(payload):
                await downloader.enqueue(
                    url: payload.url,
                    title: payload.title,
                    mediaType: payload.mediaType,
                    referer: payload.referer,
                    pageURL: payload.pageURL,
                    douyinAwemeID: payload.awemeID
                )
            }
        }
    }
}
