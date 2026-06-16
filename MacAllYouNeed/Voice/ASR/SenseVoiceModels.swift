import FluidAudio
import Foundation

/// Manages the on-disk lifecycle of the SenseVoice Small MLX model.
/// Model source: https://huggingface.co/mlx-community/SenseVoiceSmall
enum SenseVoiceModels {
    static let huggingFaceRepo = "mlx-community/SenseVoiceSmall"

    /// Files that must all be present for the model to be usable.
    /// Verified against the actual HuggingFace repo contents.
    static let requiredFiles = [
        "config.json",
        "model.safetensors",
        "am.mvn",
        "chn_jpn_yue_eng_ko_spectok.bpe.model",
    ]

    static func defaultCacheDirectory() -> URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("com.macallyouneed.shared")
            .appendingPathComponent("models")
            .appendingPathComponent("sense-voice-small")
    }

    static func modelsExist(at directory: URL) -> Bool {
        requiredFiles.allSatisfy { file in
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(file).path
            )
        }
    }

    @discardableResult
    static func download(
        progressHandler: DownloadUtils.ProgressHandler? = nil
    ) async throws -> URL {
        let directory = defaultCacheDirectory()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        let baseURL = URL(string: "https://huggingface.co")!
        let total = requiredFiles.count
        for (index, file) in requiredFiles.enumerated() {
            let destination = directory.appendingPathComponent(file)
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                continue
            }
            let fileURL = baseURL
                .appendingPathComponent(huggingFaceRepo)
                .appendingPathComponent("resolve/main")
                .appendingPathComponent(file)

            let (tempURL, response) = try await URLSession.shared.download(from: fileURL)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode)
            {
                throw URLError(.badServerResponse)
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)

            progressHandler?(
                DownloadUtils.DownloadProgress(
                    fractionCompleted: Double(index + 1) / Double(total),
                    phase: .downloading(completedFiles: index + 1, totalFiles: total)
                )
            )
        }
        return directory
    }
}
