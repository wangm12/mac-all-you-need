import AppKit
import Core
import SwiftUI
import UI

struct QuickLookContent: View {
    let item: DockItem
    let imageLoader: ImageBlobLoader
    let fileLoader: FileURLLoader
    let xpc: any ClipboardXPCInteracting

    @State private var fullText: String?
    @State private var fileURLs: [URL] = []

    var body: some View {
        Group {
            switch item.kind {
            case .text, .rtf, .code:
                ScrollView {
                    Text(fullText ?? item.preview)
                        .font(.system(.body, design: kindIsCode ? .monospaced : .default))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .textSelection(.enabled)
                }
                .task(id: item.id) {
                    fullText = await xpc.bodyText(forID: item.id) ?? item.preview
                }

            case .image:
                FullImageView(item: item, loader: imageLoader)

            case .file:
                // If the file is an image (single URL with a recognised
                // image extension), inline-preview it rather than showing
                // its path as text — Space-to-preview is supposed to show
                // the actual content, especially for screenshot files
                // dropped from CleanShot etc.
                Group {
                    if fileURLs.count == 1, Self.isImageURL(fileURLs[0]) {
                        FileImagePreview(url: fileURLs[0])
                    } else if !fileURLs.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(fileURLs, id: \.self) { url in
                                    HStack(spacing: 6) {
                                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                            .resizable()
                                            .frame(width: 18, height: 18)
                                        Text(url.path)
                                            .textSelection(.enabled)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    .onTapGesture(count: 2) {
                                        NSWorkspace.shared.activateFileViewerSelecting([url])
                                    }
                                }
                            }
                            .padding(12)
                        }
                    } else {
                        ProgressView()
                    }
                }
                .task(id: item.id) {
                    fileURLs = await fileLoader.urls(recordID: item.id) ?? []
                }

            case let .link(url):
                VStack(spacing: 8) {
                    Text(url.host ?? "")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Link(url.absoluteString, destination: url)
                        .font(.body)
                }
                .padding(12)

            case .color:
                let nsColor: NSColor = {
                    if case let .color(color) = PreviewDetection.detect(item.preview) {
                        return color
                    }
                    return .gray
                }()
                let sRGB = nsColor.usingColorSpace(.sRGB) ?? nsColor
                let rgb = String(
                    format: "rgb(%d, %d, %d)",
                    Int(sRGB.redComponent * 255),
                    Int(sRGB.greenComponent * 255),
                    Int(sRGB.blueComponent * 255)
                )
                let hsl = String(
                    format: "hsl(%.0f, %.0f%%, %.0f%%)",
                    sRGB.hueComponent * 360,
                    sRGB.saturationComponent * 100,
                    sRGB.brightnessComponent * 100
                )

                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Text(item.preview)
                        .font(.system(.title3, design: .monospaced))
                    Text(rgb)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(hsl)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var kindIsCode: Bool {
        if case .code = item.kind {
            return true
        }
        return false
    }

    /// File extensions we render inline as images instead of showing the
    /// path. Anything else falls through to the file-list view.
    fileprivate static func isImageURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tiff", "tif", "bmp"].contains(ext)
    }
}

private struct FullImageView: View {
    let item: DockItem
    let loader: ImageBlobLoader

    @State private var image: NSImage?
    @State private var zoom: CGFloat = 1.0
    @State private var dataSize: Int?

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(zoom)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    zoom = max(0.25, min(8, value))
                                }
                        )
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 12) {
                if case let .image(width, height, _) = item.kind {
                    Text("\(width) × \(height)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let dataSize {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(dataSize), countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                HStack(spacing: 5) {
                    ShortcutChip(text: "⌘+", height: HotkeyChipPresentation.compactHeight)
                    ShortcutChip(text: "⌘−", height: HotkeyChipPresentation.compactHeight)
                    Text("zoom")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .task(id: item.id) {
            zoom = 1.0
            image = await loader.thumbnail(recordID: item.id, maxDim: 0)
            if let rep = image?.representations.first as? NSBitmapImageRep {
                dataSize = rep.pixelsWide * rep.pixelsHigh * 4
            } else {
                dataSize = nil
            }
        }
    }
}

/// Inline image preview for `.file` cards whose URL points to an image
/// file. Loads from disk async so a large screenshot doesn't block the
/// SwiftUI render. Same zoom gesture as `FullImageView` for consistency.
private struct FileImagePreview: View {
    let url: URL
    @State private var image: NSImage?
    @State private var zoom: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(zoom)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    zoom = max(0.25, min(8, value))
                                }
                        )
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 14, height: 14)
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("Open")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .onTapGesture {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 8)
        .task(id: url) {
            zoom = 1.0
            // Loaded off the main thread so a 12 MB CleanShot screenshot
            // doesn't lock up the dock while decoding.
            image = await Task.detached(priority: .userInitiated) {
                NSImage(contentsOf: url)
            }.value
        }
    }
}
