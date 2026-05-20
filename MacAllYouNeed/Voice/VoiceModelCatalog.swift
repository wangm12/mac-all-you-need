import AppKit
import FluidAudio
import Foundation

enum VoiceModelRuntime: String, Codable, Equatable, Identifiable {
    case qwenCoreML
    case parakeetCoreML
    case whisperKit
    case mlxExperimental
    case groq
    case elevenLabs
    case openAITranscribe
    case deepgram
    case anthropic
    case openAICompatible
    case ollama

    var id: String { rawValue }
}

private extension VoiceASRProviderKind {
    var voiceModelRuntime: VoiceModelRuntime {
        switch self {
        case .local:
            .qwenCoreML
        case .groq:
            .groq
        case .elevenLabs:
            .elevenLabs
        case .openAITranscribe:
            .openAITranscribe
        case .deepgram:
            .deepgram
        }
    }
}

enum VoiceModelCategory: String, Codable, Equatable {
    case localASR
    case cloudASR
    case cleanupLLM
}

struct VoiceModelDescriptor: Identifiable, Equatable {
    let id: String
    let category: VoiceModelCategory
    let runtime: VoiceModelRuntime
    let title: String
    let subtitle: String
    let diskLabel: String?
    let requiresOSLabel: String?
    let localASRModelID: VoiceASRModelID?
    let cloudASRModelID: VoiceCloudASRModelID?
    let groqASRModelID: GroqASRModelID?
}

enum VoiceModelInstallState: Equatable {
    case notInstalled
    case installed
    case downloading(progress: Double?)
    case selected
    case unsupported
    case failed(reason: String)
}

enum VoiceModelCatalog {
    static let localASRModels: [VoiceModelDescriptor] = [
        VoiceModelDescriptor(
            id: "qwenCoreML.qwen3-asr-0.6b-f32",
            category: .localASR,
            runtime: .qwenCoreML,
            title: "Qwen3-ASR 0.6B f32",
            subtitle: "Default mixed Chinese/English model. Best current quality/latency balance in this app.",
            diskLabel: "~1.75 GB",
            requiresOSLabel: "macOS 15+",
            localASRModelID: .qwen3ASR06BF32,
            cloudASRModelID: nil,
            groqASRModelID: nil
        ),
        VoiceModelDescriptor(
            id: "qwenCoreML.qwen3-asr-0.6b-int8",
            category: .localASR,
            runtime: .qwenCoreML,
            title: "Qwen3-ASR 0.6B int8",
            subtitle: "Lower-memory Qwen3-ASR build. Good for keeping dictation resident while other tools run.",
            diskLabel: "~900 MB",
            requiresOSLabel: "macOS 15+",
            localASRModelID: .qwen3ASR06BInt8,
            cloudASRModelID: nil,
            groqASRModelID: nil
        ),
        VoiceModelDescriptor(
            id: "parakeetCoreML.parakeet-tdt-0.6b-v3",
            category: .localASR,
            runtime: .parakeetCoreML,
            title: "Parakeet TDT 0.6B v3",
            subtitle: "Fast local Parakeet model for English and European-language dictation.",
            diskLabel: "~850 MB",
            requiresOSLabel: "Apple Silicon",
            localASRModelID: .parakeetTDT06BV3,
            cloudASRModelID: nil,
            groqASRModelID: nil
        ),
        VoiceModelDescriptor(
            id: "whisperKit.whisper-large-v3-turbo",
            category: .localASR,
            runtime: .whisperKit,
            title: "WhisperKit large-v3 turbo",
            subtitle: "Planned universal local fallback runtime for broad multilingual coverage.",
            diskLabel: nil,
            requiresOSLabel: "Not packaged",
            localASRModelID: nil,
            cloudASRModelID: nil,
            groqASRModelID: nil
        ),
        VoiceModelDescriptor(
            id: "mlxExperimental.qwen3-asr-1.7b",
            category: .localASR,
            runtime: .mlxExperimental,
            title: "Qwen3-ASR 1.7B MLX",
            subtitle: "Experimental local runtime; hidden from selection until packaging, memory, and latency are proven.",
            diskLabel: nil,
            requiresOSLabel: "Experimental",
            localASRModelID: nil,
            cloudASRModelID: nil,
            groqASRModelID: nil
        )
    ]

    static let cloudASRModels: [VoiceModelDescriptor] = VoiceCloudASRModelID.allCases.map { modelID in
        VoiceModelDescriptor(
            id: modelID.rawValue,
            category: .cloudASR,
            runtime: modelID.providerKind.voiceModelRuntime,
            title: modelID.title,
            subtitle: modelID.subtitle,
            diskLabel: nil,
            requiresOSLabel: nil,
            localASRModelID: nil,
            cloudASRModelID: modelID,
            groqASRModelID: modelID.groqModelID
        )
    }

    static func localASRDescriptor(for modelID: VoiceASRModelID) -> VoiceModelDescriptor {
        localASRModels.first { $0.localASRModelID == modelID }!
    }
}

enum VoiceModelManager {
    static let recommendedLocalASROrder: [VoiceASRModelID] = [
        .qwen3ASR06BF32,
        .parakeetTDT06BV3,
        .qwen3ASR06BInt8
    ]

    static func localASRInstallState(
        descriptor: VoiceModelDescriptor,
        selectedModelID: VoiceASRModelID,
        providerKind: VoiceASRProviderKind,
        installedModelIDs: Set<VoiceASRModelID>,
        downloadingModelID: VoiceASRModelID?,
        failureReason: String?
    ) -> VoiceModelInstallState {
        guard let modelID = descriptor.localASRModelID else {
            return .unsupported
        }
        return localASRInstallState(
            modelID: modelID,
            selectedModelID: selectedModelID,
            providerKind: providerKind,
            installedModelIDs: installedModelIDs,
            downloadingModelID: downloadingModelID,
            failureReason: failureReason
        )
    }

    static func localASRInstallState(
        modelID: VoiceASRModelID,
        selectedModelID: VoiceASRModelID,
        providerKind: VoiceASRProviderKind,
        installedModelIDs: Set<VoiceASRModelID>,
        downloadingModelID: VoiceASRModelID?,
        failureReason: String?
    ) -> VoiceModelInstallState {
        if let failureReason {
            return .failed(reason: failureReason)
        }
        if downloadingModelID == modelID {
            return .downloading(progress: nil)
        }
        if providerKind == .local, selectedModelID == modelID, installedModelIDs.contains(modelID) {
            return .selected
        }
        if installedModelIDs.contains(modelID) {
            return .installed
        }
        return .notInstalled
    }

    static func installedLocalASRModelIDs() -> Set<VoiceASRModelID> {
        Set(recommendedLocalASROrder.filter(isLocalASRModelInstalled))
    }

    static func isLocalASRModelInstalled(_ modelID: VoiceASRModelID) -> Bool {
        switch modelID.runtime {
        case .qwenCoreML:
            guard #available(macOS 15, *) else { return false }
            return Qwen3AsrModels.modelsExist(at: localASRCacheDirectory(for: modelID))
        case .parakeetCoreML:
            guard let version = modelID.parakeetVersion else { return false }
            return AsrModels.modelsExist(at: localASRCacheDirectory(for: modelID), version: version)
        default:
            return false
        }
    }

    static func localASRCacheDirectory(for modelID: VoiceASRModelID) -> URL {
        switch modelID.runtime {
        case .qwenCoreML:
            guard #available(macOS 15, *), let variant = modelID.qwen3Variant else {
                return unavailableLocalASRCacheDirectory(for: modelID)
            }
            return Qwen3AsrModels.defaultCacheDirectory(variant: variant)
        case .parakeetCoreML:
            guard let version = modelID.parakeetVersion else {
                return unavailableLocalASRCacheDirectory(for: modelID)
            }
            return AsrModels.defaultCacheDirectory(for: version)
        default:
            return unavailableLocalASRCacheDirectory(for: modelID)
        }
    }

    @discardableResult
    static func downloadLocalASRModel(
        _ modelID: VoiceASRModelID,
        progressHandler: DownloadUtils.ProgressHandler? = nil
    ) async throws -> URL {
        switch modelID.runtime {
        case .qwenCoreML:
            guard #available(macOS 15, *) else {
                throw Qwen3EngineError.unsupportedOS
            }
            guard let variant = modelID.qwen3Variant else {
                throw VoiceLocalASREngineError.unsupportedModel(modelID)
            }
            return try await Qwen3AsrModels.download(
                variant: variant,
                progressHandler: progressHandler
            )
        case .parakeetCoreML:
            guard SystemInfo.isAppleSilicon else {
                throw VoiceLocalASREngineError.unsupportedPlatform("Parakeet requires Apple Silicon.")
            }
            guard let version = modelID.parakeetVersion else {
                throw VoiceLocalASREngineError.unsupportedModel(modelID)
            }
            return try await AsrModels.download(
                version: version,
                progressHandler: progressHandler
            )
        default:
            throw VoiceLocalASREngineError.unsupportedModel(modelID)
        }
    }

    static func deleteLocalASRModel(_ modelID: VoiceASRModelID) throws {
        let directory = localASRCacheDirectory(for: modelID)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    static func showLocalASRModelInFinder(_ modelID: VoiceASRModelID) {
        let directory = localASRCacheDirectory(for: modelID)
        if FileManager.default.fileExists(atPath: directory.path) {
            NSWorkspace.shared.activateFileViewerSelecting([directory])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([directory.deletingLastPathComponent()])
        }
    }

    static func fallbackLocalASRModel(
        afterDeleting deletedModelID: VoiceASRModelID,
        selectedModelID: VoiceASRModelID,
        installedModelIDsAfterDelete: Set<VoiceASRModelID>
    ) -> VoiceASRModelID? {
        guard deletedModelID == selectedModelID else { return selectedModelID }
        return recommendedLocalASROrder.first { installedModelIDsAfterDelete.contains($0) }
    }

    private static func unavailableLocalASRCacheDirectory(for modelID: VoiceASRModelID) -> URL {
        guard
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
        else {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("FluidAudio", isDirectory: true)
                .appendingPathComponent("Models", isDirectory: true)
                .appendingPathComponent(modelID.rawValue, isDirectory: true)
        }
        return appSupport
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(modelID.rawValue, isDirectory: true)
    }
}
