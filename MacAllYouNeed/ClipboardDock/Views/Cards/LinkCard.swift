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
            Text(item.preview)
                .font(.callout)
                .lineLimit(3)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
        .task(id: item.id) {
            guard let url else { return }
            favicon = await favicons.favicon(for: url)
        }
    }
}
