import AppKit
import SwiftUI

struct ImageCard: View {
    let item: DockItem
    let loader: ImageBlobLoader
    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if failed {
                Image(systemName: "photo")
                    .font(.system(size: 32))
                    .foregroundStyle(.tertiary)
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.1))
                    .overlay(ProgressView().controlSize(.small))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(10)
        .task(id: item.id) {
            let loadedImage = await loader.thumbnail(recordID: item.id, maxDim: 240)
            await MainActor.run {
                if let loadedImage {
                    image = loadedImage
                } else {
                    failed = true
                }
            }
        }
    }
}
