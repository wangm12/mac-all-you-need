import Cocoa
import Core
import Quartz

class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let url = request.fileURL
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let fallback = AppGroup.isUsingFallbackContainer() ? " (FALLBACK - entitlement missing)" : ""
        let body = if isDirectory {
            "Folder preview placeholder for \(url.lastPathComponent)\nContainer: \(AppGroup.containerURL().path)\(fallback)"
        } else {
            "Archive preview placeholder for \(url.lastPathComponent)\nContainer: \(AppGroup.containerURL().path)\(fallback)"
        }

        return QLPreviewReply(dataOfContentType: .plainText, contentSize: .zero) { _ in
            body.data(using: .utf8) ?? Data()
        }
    }
}
