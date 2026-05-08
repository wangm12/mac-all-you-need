import AppKit
import SwiftUI

struct FileCard: View {
    let item: DockItem
    let loader: FileURLLoader
    @State private var urls: [URL] = []
    @State private var totalBytes: Int64?

    var body: some View {
        let displayCount: Int = urls.isEmpty ? fallbackCount() : urls.count
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let first = urls.first {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: first.path))
                        .resizable()
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(urls.first?.lastPathComponent ?? item.preview)
                        .font(.callout)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    if displayCount > 1 {
                        Text("\(displayCount) files")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else if let totalBytes {
                        Text(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
        .draggable(primaryDragURL)
        .task(id: item.id) {
            urls = await loader.urls(recordID: item.id) ?? []
            if urls.count == 1,
               let attrs = try? FileManager.default.attributesOfItem(atPath: urls[0].path),
               let size = attrs[.size] as? Int64,
               size < 100 * 1024 * 1024
            {
                totalBytes = size
            }
        }
    }

    private func fallbackCount() -> Int {
        if case let .file(count) = item.kind { return count }
        return 1
    }

    private var primaryDragURL: URL {
        urls.first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }
}
