import Core
import Platform
import SwiftUI

public struct FolderPreviewView: View {
    public enum Mode: String, CaseIterable, Identifiable {
        case files, grid, analyze
        public var id: String {
            rawValue
        }
    }

    @State private var inventory: FolderInventory?
    @State private var mode: Mode = .files
    @State private var currentURL: URL
    @State private var backStack: [URL] = []
    public let folderURL: URL
    public let onAction: ((PreviewAction) -> Void)?

    public init(folderURL: URL, onAction: ((PreviewAction) -> Void)? = nil) {
        self.folderURL = folderURL
        self.onAction = onAction
        _currentURL = State(initialValue: folderURL)
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    if let previous = backStack.popLast() { currentURL = previous }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(backStack.isEmpty)
                Text(currentURL.lastPathComponent).font(.title3).bold()
                if let inv = inventory {
                    Text("· \(inv.entries.count) items · \(byteCountFormatter.string(fromByteCount: inv.totalSize))")
                        .foregroundStyle(.secondary).font(.caption)
                    if inv.isPartial { Text("(partial)").foregroundStyle(.orange).font(.caption) }
                }
                Spacer()
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }.pickerStyle(.segmented).frame(width: 200)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            Group {
                if let inv = inventory {
                    switch mode {
                    case .files:
                        FolderFilesView(inventory: inv, onAction: onAction) { url in
                            backStack.append(currentURL)
                            currentURL = url
                        }
                    case .grid: FolderGridView(inventory: inv)
                    case .analyze: FolderAnalyzeView(inventory: inv)
                    }
                } else {
                    ProgressView("Scanning…").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .task(id: currentURL) {
            inventory = nil
            let maxEntries = AppGroupSettings.defaults.integer(forKey: "folderPreviewMaxEntries")
            let includeHidden = AppGroupSettings.defaults.bool(forKey: "folderPreviewIncludeHidden")
            inventory = try? await FolderEnumerator.enumerate(
                url: currentURL,
                maxEntries: maxEntries == 0 ? 50_000 : maxEntries,
                includeHidden: includeHidden
            )
            if let inv = inventory, autoSuggestGrid(inv) { mode = .grid }
        }
    }

    private func autoSuggestGrid(_ inv: FolderInventory) -> Bool {
        let imageCount = inv.breakdown[.images, default: 0]
        let nonFolderCount = inv.entries.filter { !$0.isDirectory }.count
        return nonFolderCount > 10 && Double(imageCount) / Double(nonFolderCount) >= 0.4
    }
}

public enum PreviewAction: Sendable {
    case open(URL)
    case copy(URL)
    case revealInFinder(URL)
}

private let byteCountFormatter: ByteCountFormatter = {
    let f = ByteCountFormatter()
    f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
    f.countStyle = .file
    return f
}()
