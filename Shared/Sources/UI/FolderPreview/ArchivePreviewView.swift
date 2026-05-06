import Platform
import SwiftUI

public struct ArchivePreviewView: View {
    public let archiveURL: URL
    @State private var entries: [ArchiveEntry] = []
    @State private var error: String?

    public init(archiveURL: URL) { self.archiveURL = archiveURL }

    public var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("🗄️ \(archiveURL.lastPathComponent)").font(.title3).bold()
                Spacer()
                Text("\(entries.count) entries").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            if let error {
                Text(error).foregroundStyle(.red).padding()
            } else {
                List(entries, id: \.path) { entry in
                    HStack {
                        Image(systemName: entry.isDirectory ? "folder" : "doc")
                        Text(entry.path).lineLimit(1)
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: entry.uncompressedSize, countStyle: .file))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task(id: archiveURL) {
            do {
                entries = try LibArchiveBackend().list(archiveURL: archiveURL, limits: .default)
            } catch {
                self.error = "Could not read archive: \(error.localizedDescription)"
            }
        }
    }
}
