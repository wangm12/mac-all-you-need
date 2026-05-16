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
