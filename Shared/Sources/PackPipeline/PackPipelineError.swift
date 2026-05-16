import Foundation

public enum PackPipelineError: Error, Equatable, Sendable {
    case networkFailed(String)
    case wholeZipShaMismatch(expected: String, actual: String)
    case fileShaMismatch(name: String, expected: String, actual: String)
    case unexpectedFile(name: String)
    case missingFile(name: String)
    case fileTooLarge(name: String, declaredMax: Int64, actual: Int64)
    case zipBomb(declaredSize: Int64, extractedSize: Int64)
    case zipSlipDetected(name: String)
    case symlinkInZip(name: String)
    case codesignFailed(name: String, reason: String)
    case quarantineRemovalFailed(name: String)
    case extractionFailed(reason: String)
    case destinationExists(URL)
    case cancelled
}

extension PackPipelineError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .networkFailed:
            return "The download failed. Check your internet connection and try again."
        case .wholeZipShaMismatch:
            return "The downloaded pack is corrupted. Please try again."
        case .fileShaMismatch(let name, _, _):
            return "The pack is corrupted (file \"\(name)\" failed verification). Please try again."
        case .unexpectedFile(let name):
            return "The pack contains an unexpected file (\"\(name)\") and was rejected for security."
        case .missingFile(let name):
            return "The pack is missing a required file (\"\(name)\"). Please try again."
        case .fileTooLarge(let name, _, _):
            return "The pack contains an oversized file (\"\(name)\") and was rejected."
        case .zipBomb:
            return "The pack was rejected because its contents are suspiciously large."
        case .zipSlipDetected(let name):
            return "The pack contains a path-traversal entry (\"\(name)\") and was rejected for security."
        case .symlinkInZip(let name):
            return "The pack contains a symbolic link (\"\(name)\") and was rejected for security."
        case .codesignFailed(let name, _):
            return "The code signature on \"\(name)\" is not valid. Only signed packs are accepted."
        case .quarantineRemovalFailed(let name):
            return "Could not clear the quarantine flag on \"\(name)\". Try running the app with Full Disk Access."
        case .extractionFailed(let reason):
            return "Extraction failed: \(reason)"
        case .destinationExists(let url):
            return "A pack is already installed at \"\(url.lastPathComponent)\". Uninstall it first."
        case .cancelled:
            return "The installation was cancelled."
        }
    }
}
