import Foundation

public enum ProgressParser {
    public static func parse(line: String) -> DownloadProgress? {
        guard line.hasPrefix("[download]") else { return nil }
        let pctRegex = #/(\d+(?:\.\d+)?)%\s+of/#
        guard let m = try? pctRegex.firstMatch(in: line),
              let pct = Double(String(m.output.1)) else { return nil }
        let speed = parseSpeed(line)
        let eta = parseETA(line)
        let total = parseTotalBytes(line)
        let downloaded = total.map { Int64(Double($0) * pct / 100.0) }
        return DownloadProgress(
            fraction: pct / 100.0, speedBytesPerSec: speed,
            etaSeconds: eta, downloadedBytes: downloaded, totalBytes: total
        )
    }

    private static func parseSpeed(_ line: String) -> Double? {
        let r = #/at\s+(\d+(?:\.\d+)?)(KiB|MiB|GiB|B)\/s/#
        guard let m = try? r.firstMatch(in: line), let val = Double(String(m.output.1)) else { return nil }
        switch String(m.output.2) {
        case "KiB": return val * 1024
        case "MiB": return val * 1024 * 1024
        case "GiB": return val * 1024 * 1024 * 1024
        default: return val
        }
    }

    private static func parseETA(_ line: String) -> Int? {
        let r = #/ETA\s+(\d+):(\d+)/#
        guard let m = try? r.firstMatch(in: line),
              let mm = Int(String(m.output.1)), let ss = Int(String(m.output.2)) else { return nil }
        return mm * 60 + ss
    }

    private static func parseTotalBytes(_ line: String) -> Int64? {
        let r = #/of\s+(\d+(?:\.\d+)?)(KiB|MiB|GiB|B)/#
        guard let m = try? r.firstMatch(in: line), let val = Double(String(m.output.1)) else { return nil }
        let bytes: Double = switch String(m.output.2) {
        case "KiB": val * 1024
        case "MiB": val * 1024 * 1024
        case "GiB": val * 1024 * 1024 * 1024
        default: val
        }
        return Int64(bytes)
    }
}
