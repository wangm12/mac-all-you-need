import Core
import Foundation
import UI

enum DockItemKind: Equatable, Hashable {
    case text
    case image(width: Int, height: Int, blobID: String)
    case file(count: Int)
    case link(URL)
    case color
    case code(language: String)
    case rtf
}

struct DockItem: Identifiable, Hashable {
    let id: String
    let modified: Date
    let kind: DockItemKind
    let preview: String
    let sourceApp: SourceApp?
    let isPinned: Bool

    init(from meta: ClipboardXPCMeta, sourceApp: SourceApp?, isPinned: Bool) {
        id = meta.id
        modified = meta.modified
        preview = meta.preview
        self.sourceApp = sourceApp
        self.isPinned = isPinned

        if let imageBlobID = meta.imageBlobID {
            kind = .image(width: meta.imageWidth, height: meta.imageHeight, blobID: imageBlobID)
        } else if meta.preview.hasPrefix("(") && meta.preview.contains("file") {
            let count = meta.preview.firstMatch(of: /\((\d+) file/)
                .flatMap { Int($0.output.1) } ?? 1
            kind = .file(count: count)
        } else if meta.preview == "(rich text)" {
            kind = .rtf
        } else {
            switch PreviewDetection.detect(meta.preview) {
            case .color:
                kind = .color
            case let .url(url):
                kind = .link(url)
            case let .code(language, _):
                kind = .code(language: language)
            case .plain:
                kind = .text
            }
        }
    }
}
