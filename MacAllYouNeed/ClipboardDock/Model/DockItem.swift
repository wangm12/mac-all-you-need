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
    let customLabel: String?
    let sourceApp: SourceApp?
    let isPinned: Bool
    /// Smart Text detection JSON from the store (migration 008). Nil when the
    /// record predates Smart Text or the feature was disabled at capture.
    let detectedTypeJSON: String?
    /// Background Vision OCR text for image records, when available.
    let ocrText: String?

    /// What the card should actually show — user-set rename takes precedence
    /// over the auto-generated preview when present.
    var displayLabel: String {
        if let customLabel, !customLabel.isEmpty { return customLabel }
        return preview
    }

    /// Decoded Smart Text detection, lazily parsed from `detectedTypeJSON`.
    var detection: Detection? {
        guard let json = detectedTypeJSON else { return nil }
        return try? Detection.decode(json: json)
    }

    /// Inline calculation result, when the detection found one.
    var calculation: CalculationResult? { detection?.calculation }

    /// Number of tracking parameters that would be stripped by the link cleaner.
    var trackerCount: Int { detection?.linkClean?.removedCount ?? 0 }

    /// Whether this record has indexable OCR text.
    var hasOCRText: Bool { !(ocrText ?? "").isEmpty }

    /// The "smart result" value for Cmd+Shift+C.
    /// Priority: calculation value → cleaned link URL → OCR text.
    /// Returns nil when no smart content is available.
    var smartCopyValue: String? {
        if let v = calculation?.value { return v }
        if let c = detection?.linkClean?.cleaned { return c }
        if let o = ocrText, !o.isEmpty { return o }
        return nil
    }

    /// Lowercased detected type name for `/type:` filtering (e.g. "url",
    /// "email", "code"). Nil when no detection is present.
    var detectedTypeName: String? {
        guard let type = detection?.type else { return nil }
        switch type {
        case .plain: return "plain"
        case .email: return "email"
        case .url: return "url"
        case .phone: return "phone"
        case .jwt: return "jwt"
        case .color: return "color"
        case .code: return "code"
        }
    }

    init(from meta: ClipboardXPCMeta, sourceApp: SourceApp?, isPinned: Bool) {
        id = meta.id
        modified = meta.modified
        preview = meta.preview
        customLabel = meta.customLabel
        detectedTypeJSON = meta.detectedTypeJSON
        ocrText = meta.ocrText
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
