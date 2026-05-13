import Foundation

public enum FolderPreviewFilter: Int, CaseIterable, Sendable {
    case all, folders, images, documents, media

    public var title: String {
        switch self {
        case .all: return "All"
        case .folders: return "Folders"
        case .images: return "Images"
        case .documents: return "Docs"
        case .media: return "Media"
        }
    }
}

public enum FolderPreviewDisplay {
    public static func sorted(_ entries: [FolderEntry]) -> [FolderEntry] {
        entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }

            let order = lhs.name.localizedStandardCompare(rhs.name)
            if order != .orderedSame {
                return order == .orderedAscending
            }

            return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }
    }

    public static func matches(
        kind: FolderEntryKind,
        isDirectory: Bool,
        filter: FolderPreviewFilter,
        includesFoldersAsContext: Bool = true
    ) -> Bool {
        if filter == .all {
            return true
        }
        if isDirectory {
            return includesFoldersAsContext || filter == .folders
        }

        switch filter {
        case .all:
            return true
        case .folders:
            return false
        case .images:
            return kind == .images
        case .documents:
            return kind == .documents || kind == .code || kind == .archives
        case .media:
            return kind == .videos || kind == .audio
        }
    }

    public static func displayKind(for entry: FolderEntry) -> String {
        if entry.isDirectory {
            return "Folder"
        }

        let ext = fileExtension(for: entry)
        switch entry.kind {
        case .images:
            return ext.map { "\($0) image" } ?? "Image"
        case .videos:
            return ext.map { "\($0) video" } ?? "Video"
        case .audio:
            return ext.map { "\($0) audio" } ?? "Audio"
        case .code:
            return sourceLabel(for: ext) ?? ext.map { "\($0) source" } ?? "Source"
        case .documents:
            return ext.map { "\($0) document" } ?? "Document"
        case .archives:
            return ext.map { "\($0) archive" } ?? "Archive"
        case .other:
            return ext.map { "\($0) file" } ?? "File"
        case .folder:
            return "Folder"
        }
    }

    public static func canGenerateThumbnail(for entry: FolderEntry) -> Bool {
        guard !entry.isDirectory else { return false }
        switch fileExtension(for: entry)?.lowercased() {
        case "png", "jpg", "jpeg", "heic", "gif", "webp", "tiff", "bmp", "avif", "svg",
             "pdf",
             "mp4", "mov", "mkv", "webm", "avi":
            return true
        default:
            return false
        }
    }

    private static func fileExtension(for entry: FolderEntry) -> String? {
        let ext = (entry.name as NSString).pathExtension
        guard !ext.isEmpty else { return nil }
        return ext.uppercased()
    }

    private static func sourceLabel(for ext: String?) -> String? {
        switch ext?.lowercased() {
        case "swift": return "Swift source"
        case "py": return "Python source"
        case "go": return "Go source"
        case "rs": return "Rust source"
        case "ts": return "TypeScript source"
        case "tsx": return "TSX source"
        case "js": return "JavaScript source"
        case "jsx": return "JSX source"
        case "java": return "Java source"
        case "rb": return "Ruby source"
        case "kt": return "Kotlin source"
        case "c", "h": return "C source"
        case "cpp", "mm", "m": return "C++ source"
        case "sh": return "Shell script"
        default: return nil
        }
    }
}
