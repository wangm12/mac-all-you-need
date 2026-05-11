import AppKit
import SwiftUI

struct FileCard: View {
    let item: DockItem
    let loader: FileURLLoader
    let thumbnailLoader: FileThumbnailLoader
    @State private var urls: [URL] = []
    @State private var totalBytes: Int64?
    @State private var thumbnail: NSImage?
    @State private var thumbnailFailed = false

    var body: some View {
        ZStack(alignment: .bottom) {
            previewArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .padding(10)
        .task(id: item.id) {
            urls = await loader.urls(recordID: item.id) ?? []
            if urls.count == 1,
               let attrs = try? FileManager.default.attributesOfItem(atPath: urls[0].path),
               let size = attrs[.size] as? Int64,
               size < 100 * 1024 * 1024
            {
                totalBytes = size
            }
            // Quick Look thumbnail for the first file. Works for images,
            // PDFs, video posters, and most document types.
            thumbnail = nil
            thumbnailFailed = false
            if urls.count == 1, let url = urls.first {
                if let image = await thumbnailLoader.thumbnail(url: url, maxDim: 240) {
                    thumbnail = image
                } else {
                    thumbnailFailed = true
                }
            }
        }
    }

    /// Mirrors ImageCard's structure so the dock has a consistent visual:
    /// big preview filling the card, optional small footer for the file name.
    @ViewBuilder
    private var previewArea: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else if urls.count > 1 {
            HStack(spacing: -16) {
                ForEach(Array(urls.prefix(4).enumerated()), id: \.offset) { _, url in
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .frame(width: 56, height: 56)
                }
            }
        } else if !thumbnailFailed && urls.isEmpty {
            ProgressView().controlSize(.small)
        } else if let url = urls.first {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 96, maxHeight: 96)
        } else {
            Image(systemName: "doc.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var footer: some View {
        let displayCount = urls.isEmpty ? fallbackCount() : urls.count
        let primaryName = urls.first?.lastPathComponent ?? item.preview
        let label: String = {
            // Custom rename always wins, regardless of file count.
            if let custom = item.customLabel, !custom.isEmpty { return custom }
            if displayCount > 1 { return "\(displayCount) files" }
            return primaryName
        }()
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption)
                .lineLimit(2)
                .truncationMode(.middle)
            if displayCount == 1, let totalBytes {
                Text(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
    }

    private func fallbackCount() -> Int {
        if case let .file(count) = item.kind { return count }
        return 1
    }
}
