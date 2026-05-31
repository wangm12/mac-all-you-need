import AppKit
import SwiftUI

struct LinkCard: View {
    let item: DockItem
    let favicons: FaviconCache
    @State private var favicon: NSImage?

    var body: some View {
        let url: URL? = {
            if case let .link(url) = item.kind { return url }
            return nil
        }()
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let favicon {
                    Image(nsImage: favicon)
                        .resizable()
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "link")
                        .foregroundStyle(.secondary)
                }
                Text(url?.host ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(item.displayLabel)
                .font(.callout)
                .lineLimit(3)
            if item.trackerCount > 0 {
                trackerRow
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
        .task(id: item.id) {
            guard let url else { return }
            favicon = await favicons.favicon(for: url)
        }
    }

    private var trackerRow: some View {
        HStack(spacing: 6) {
            StatusPill(
                text: "\(item.trackerCount) tracker\(item.trackerCount == 1 ? "" : "s")",
                kind: .warning
            )
            if let cleaned = item.detection?.linkClean?.cleaned {
                MAYNButton("Copy clean link") {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(cleaned, forType: .string)
                }
            }
        }
    }
}
