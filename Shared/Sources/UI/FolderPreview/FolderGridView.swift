import Core
import Platform
import SwiftUI

struct FolderGridView: View {
    let entries: [FolderEntry]
    @State private var thumbs: [String: NSImage] = [:]
    private let svc = ThumbnailService(
        cacheRoot: AppGroup.containerURL().appendingPathComponent("thumbnails")
    )

    var body: some View {
        Group {
            if entries.isEmpty {
                FolderPreviewStateView(
                    symbol: "photo.on.rectangle.angled",
                    title: "No image files",
                    message: "Files view still includes the full folder contents."
                )
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 112, maximum: 140), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(entries) { entry in
                            VStack(alignment: .leading, spacing: 6) {
                                ZStack {
                                    FolderPreviewUI.fill
                                    if let img = thumbs[entry.path] {
                                        Image(nsImage: img)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    } else {
                                        Image(systemName: "photo")
                                            .font(.system(size: 22))
                                            .foregroundStyle(FolderPreviewUI.muted)
                                    }
                                }
                                .frame(height: 94)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(FolderPreviewUI.border, lineWidth: 1)
                                )

                                Text(entry.name)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .padding(7)
                            .background(FolderPreviewUI.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(FolderPreviewUI.border, lineWidth: 1)
                            )
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
                    .padding(12)
                }
                .background(FolderPreviewUI.background)
            }
        }
    }
}
