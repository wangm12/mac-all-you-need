import Foundation

enum MAYNByteCountFormatting {
    static func string(for bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
