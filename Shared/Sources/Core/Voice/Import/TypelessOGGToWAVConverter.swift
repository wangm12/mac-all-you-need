import Foundation

public enum TypelessAudioConversionError: Error, Equatable {
    case ffmpegNotFound(URL)
    case conversionFailed(exitCode: Int32, oggPath: String)
    case emptyOutput(oggPath: String)
}

public protocol TypelessAudioConverting: Sendable {
    func convertOGGToWAV(oggURL: URL) throws -> Data
}

/// Converts Typeless `.ogg` recordings to mono 16 kHz WAV using vendored ffmpeg.
public struct FFmpegTypelessAudioConverter: TypelessAudioConverting {
    public let ffmpegURL: URL

    public init(ffmpegURL: URL) {
        self.ffmpegURL = ffmpegURL
    }

    public func convertOGGToWAV(oggURL: URL) throws -> Data {
        guard FileManager.default.isExecutableFile(atPath: ffmpegURL.path) else {
            throw TypelessAudioConversionError.ffmpegNotFound(ffmpegURL)
        }

        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = [
            "-nostdin",
            "-i", oggURL.path,
            "-f", "wav",
            "-ac", "1",
            "-ar", "16000",
            "-"
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw TypelessAudioConversionError.conversionFailed(
                exitCode: process.terminationStatus,
                oggPath: oggURL.path
            )
        }
        guard !data.isEmpty else {
            throw TypelessAudioConversionError.emptyOutput(oggPath: oggURL.path)
        }
        return data
    }
}
