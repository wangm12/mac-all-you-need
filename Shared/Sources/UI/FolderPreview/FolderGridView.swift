import Core
import Platform
import SwiftUI

struct FolderGridView: View {
    let inventory: FolderInventory
    @State private var thumbs: [String: NSImage] = [:]
    private let svc = ThumbnailService(
        cacheRoot: AppGroup.containerURL().appendingPathComponent("thumbnails")
    )

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(minimum: 110), spacing: 8), count: 5),
                spacing: 8
            ) {
                ForEach(inventory.entries.filter { $0.kind == .images }) { entry in
                    VStack(spacing: 4) {
                        if let img = thumbs[entry.path] {
                            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Color.gray.opacity(0.1)
                        }
                        Text(entry.name).font(.caption).lineLimit(1)
                    }
                    .frame(width: 110, height: 130)
                    .task {
                        if thumbs[entry.path] == nil {
                            thumbs[entry.path] = try? await svc.thumbnail(
                                for: URL(fileURLWithPath: entry.path),
                                size: CGSize(width: 220, height: 220)
                            )
                        }
                    }
                }
            }
            .padding(8)
        }
    }
}
