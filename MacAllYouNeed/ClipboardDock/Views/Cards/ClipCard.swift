import SwiftUI

struct ClipCard: View {
    let item: DockItem
    let imageLoader: ImageBlobLoader
    let fileLoader: FileURLLoader
    let fileThumbnailLoader: FileThumbnailLoader
    let favicons: FaviconCache
    let cardBackground: Color

    var body: some View {
        VStack(spacing: 0) {
            CardHeader(item: item)
            Divider()
                .opacity(0.4)
            cardContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(cardBackground)
        .cornerRadius(10)
    }

    @ViewBuilder
    private var cardContent: some View {
        switch item.kind {
        case .text, .rtf:
            TextCard(item: item)
        case .image:
            ImageCard(item: item, loader: imageLoader)
        case .file:
            FileCard(item: item, loader: fileLoader, thumbnailLoader: fileThumbnailLoader)
        case .link:
            LinkCard(item: item, favicons: favicons)
        case .color:
            ColorCard(item: item)
        case .code:
            CodeCard(item: item)
        }
    }
}

/// Paste-style header: kind label + relative timestamp on the left,
/// source app icon on the right. Background is tinted with the average
/// color of the source app's icon so the dock has visible per-app rhythm.
private struct CardHeader: View {
    let item: DockItem

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(kindLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(timestampText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            appIcon
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                if let tint = headerTint {
                    Rectangle().fill(tint.opacity(0.35))
                }
            }
        }
    }

    @ViewBuilder
    private var appIcon: some View {
        if let app = item.sourceApp, let icon = app.icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .help(app.displayName)
        }
    }

    /// Synchronous tint extraction — AppIconColor.dominant runs in <1ms on
    /// a 32×32 bitmap and is cached by NSImage identity, so the colored
    /// header appears on the FIRST render frame instead of after a brief
    /// gray flash.
    private var headerTint: Color? {
        guard let icon = item.sourceApp?.icon,
              let nsColor = AppIconColor.dominant(of: icon)
        else { return nil }
        return Color(nsColor)
    }

    private var kindLabel: String {
        switch item.kind {
        case .text:
            return "Text"
        case .rtf:
            return "Rich Text"
        case .image(let w, let h, _):
            if w > 0 && h > 0 { return "Image · \(w)×\(h)" }
            return "Image"
        case .file(let count):
            return count > 1 ? "\(count) files" : "File"
        case .link:
            return "Link"
        case .color:
            return "Color"
        case .code(let language):
            return "Code · \(language)"
        }
    }

    private var timestampText: String {
        Self.relativeFormatter.localizedString(for: item.modified, relativeTo: Date())
    }

    /// Static so we don't construct a new formatter every render — Foundation
    /// formatters are heavyweight to allocate.
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}
