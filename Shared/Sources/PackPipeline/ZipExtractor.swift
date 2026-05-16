import Foundation

public enum ZipExtractor {
    public struct Result {
        public let extractedFiles: [String]
    }

    public static func extract(
        zipFileURL: URL,
        into destinationDir: URL,
        allowedFiles: Set<String>,
        maxTotalBytes: Int64
    ) throws -> Result {
        // 1. List entries via `unzip -Z1`
        let listing = try runUnzip(["-Z1", zipFileURL.path])
        let entries = listing.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }

        // 2. Validate each entry name: no zip-slip paths, must be in allowlist.
        for name in entries {
            if name.hasPrefix("/") || name.contains("..") {
                throw PackPipelineError.zipSlipDetected(name: name)
            }
            guard allowedFiles.contains(name) else {
                throw PackPipelineError.unexpectedFile(name: name)
            }
        }

        // 3. Detect symlinks via `unzip -Z` (entry lines start with 'l' for symlinks).
        let symlinkListing = (try? runUnzip(["-Z", zipFileURL.path])) ?? ""
        for line in symlinkListing.split(whereSeparator: \.isNewline) {
            let lineStr = String(line)
            // Only check lines that look like entry lines (not header/footer).
            // Entry lines start with the permission string: 'l' for symlink.
            guard lineStr.hasPrefix("l") else { continue }
            // Entry name is the last whitespace-separated token.
            let parts = lineStr.split(separator: " ").map(String.init)
            let name = parts.last ?? "<unknown>"
            throw PackPipelineError.symlinkInZip(name: name)
        }

        // 4. Extract into destinationDir.
        let fm = FileManager.default
        try fm.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        _ = try runUnzip(["-q", "-o", zipFileURL.path, "-d", destinationDir.path])

        // 5. Zip bomb: verify total extracted size against maxTotalBytes.
        var totalExtracted: Int64 = 0
        for name in entries {
            let url = destinationDir.appendingPathComponent(name)
            let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
            totalExtracted += size
            if totalExtracted > maxTotalBytes {
                try? fm.removeItem(at: destinationDir)
                throw PackPipelineError.zipBomb(declaredSize: maxTotalBytes, extractedSize: totalExtracted)
            }
        }

        return Result(extractedFiles: entries)
    }

    // Runs /usr/bin/unzip and returns stdout. Throws extractionFailed on non-zero exit.
    // Note: unzip exit code 1 means "warnings" (e.g. nothing to do) — treat it as OK too.
    private static func runUnzip(_ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        // unzip exit codes: 0=success, 1=warnings, 2=generic error, 11=no match found.
        // We treat 0 and 1 as success.
        if process.terminationStatus > 1 {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8) ?? ""
            throw PackPipelineError.extractionFailed(reason: "unzip exited \(process.terminationStatus): \(errStr)\(output)")
        }
        return output
    }
}
