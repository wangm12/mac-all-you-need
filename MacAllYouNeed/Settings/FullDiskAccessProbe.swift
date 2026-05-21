import Foundation

/// Probes the live OS state of Full Disk Access for the current process.
///
/// macOS doesn't expose a public API to query FDA. The standard technique
/// is to try to read a known FDA-protected system file and infer the
/// permission from whether the read succeeds.
///
/// We use the system TCC database at
/// `/Library/Application Support/com.apple.TCC/TCC.db`. It exists on every
/// Mac (it's the file that stores TCC grants themselves) and is readable
/// only with Full Disk Access granted. Opening or reading without FDA
/// throws `EPERM`.
enum FullDiskAccessProbe {
    /// Cheap to call — opens a handle, reads one byte, closes. Safe to
    /// poll on a timer.
    static func isGranted() -> Bool {
        let url = URL(fileURLWithPath: "/Library/Application Support/com.apple.TCC/TCC.db")
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return false
        }
        defer { try? handle.close() }
        do {
            // Reading at least one byte is the conclusive test — `open()`
            // alone can succeed in some edge cases (e.g. when sandboxed
            // proxy reads happen) without real FDA.
            _ = try handle.read(upToCount: 1)
            return true
        } catch {
            return false
        }
    }
}
