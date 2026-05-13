import FluidAudio
import Foundation

/// Gate 5: benchmark real machine work with signposts.
enum SpikeBenchmark {
    static func run() async -> String {
        guard #available(macOS 15, *) else {
            return "FAIL: Qwen3-ASR benchmark requires macOS 15 or later."
        }

        var lines = ["=== Gate 5: real machine-work benchmark ==="]
        guard let samples = loadSamples(lines: &lines) else { return lines.joined(separator: "\n") }
        guard let manager = await loadManager(lines: &lines) else { return lines.joined(separator: "\n") }

        await warmUp(samples: samples, manager: manager, lines: &lines)
        let measured = await measure(samples: samples, manager: manager)
        lines.append(contentsOf: measured.lines)

        guard !measured.asrLatencies.isEmpty else {
            lines.append("FAIL: all benchmark ASR passes failed.")
            return lines.joined(separator: "\n")
        }

        appendSummary(measured, lines: &lines)
        return lines.joined(separator: "\n")
    }

    private struct Measurements {
        var asrLatencies: [Double] = []
        var pasteSetMicros: [Double] = []
        var pastePostMicros: [Double] = []
        var restoreMicros: [Double] = []
        var totalLatencies: [Double] = []
        var transcript = ""
        var lines: [String] = []
    }

    private static func loadSamples(lines: inout [String]) -> [Float]? {
        guard let url = Bundle.main.url(forResource: "zh-en-mixed-5s", withExtension: "wav") else {
            lines.append("FAIL: fixture audio is missing from the app bundle.")
            return nil
        }
        let loadStart = Date()
        do {
            let samples = try SpikeASRGate.loadFloat32PCM(from: url)
            lines.append(String(format: "Fixture load: %.0f ms (%d samples)", Date().timeIntervalSince(loadStart) * 1000, samples.count))
            return samples
        } catch {
            lines.append("FAIL: fixture load failed: \(error)")
            return nil
        }
    }

    @available(macOS 15, *)
    private static func loadManager(lines: inout [String]) async -> Qwen3AsrManager? {
        let modelInterval = VoiceSpikeLog.signposter.beginInterval("modelLoad")
        let modelStart = Date()
        do {
            let cacheDir = try await Qwen3AsrModels.download(variant: .f32)
            let manager = Qwen3AsrManager()
            try await manager.loadModels(from: cacheDir)
            VoiceSpikeLog.signposter.endInterval("modelLoad", modelInterval)
            lines.append(String(format: "Model load: %.0f ms", Date().timeIntervalSince(modelStart) * 1000))
            return manager
        } catch {
            VoiceSpikeLog.signposter.endInterval("modelLoad", modelInterval)
            lines.append("FAIL: Qwen3-ASR model load failed: \(error)")
            return nil
        }
    }

    @available(macOS 15, *)
    private static func warmUp(samples: [Float], manager: Qwen3AsrManager, lines: inout [String]) async {
        do {
            _ = try await manager.transcribe(audioSamples: samples, language: .chinese, maxNewTokens: 512)
        } catch {
            lines.append("Warmup ASR error: \(error)")
        }
    }

    @available(macOS 15, *)
    private static func measure(samples: [Float], manager: Qwen3AsrManager) async -> Measurements {
        var measured = Measurements()
        for pass in 1 ... 5 {
            await measurePass(pass, samples: samples, manager: manager, measured: &measured)
        }
        return measured
    }

    @available(macOS 15, *)
    private static func measurePass(_ pass: Int, samples: [Float], manager: Qwen3AsrManager, measured: inout Measurements) async {
        let inferenceInterval = VoiceSpikeLog.signposter.beginInterval("inference", "pass=\(pass)")
        let asrStart = Date()
        do {
            measured.transcript = try await manager.transcribe(audioSamples: samples, language: .chinese, maxNewTokens: 512)
        } catch {
            VoiceSpikeLog.signposter.endInterval("inference", inferenceInterval)
            measured.lines.append("Pass \(pass) ASR error: \(error)")
            return
        }
        VoiceSpikeLog.signposter.endInterval("inference", inferenceInterval)
        appendPasteTiming(pass, asrMs: Date().timeIntervalSince(asrStart) * 1000, measured: &measured)
    }

    private static func appendPasteTiming(_ pass: Int, asrMs: Double, measured: inout Measurements) {
        let pasteInterval = VoiceSpikeLog.signposter.beginInterval("paste", "pass=\(pass)")
        let timing = SpikePasteGate.runUnattended(text: measured.transcript.isEmpty ? "benchmark fallback" : measured.transcript)
        VoiceSpikeLog.signposter.endInterval("paste", pasteInterval)

        let totalMs = asrMs + (timing.setMicros + timing.postMicros + timing.restoreMicros) / 1000.0
        measured.asrLatencies.append(asrMs)
        measured.pasteSetMicros.append(timing.setMicros)
        measured.pastePostMicros.append(timing.postMicros)
        measured.restoreMicros.append(timing.restoreMicros)
        measured.totalLatencies.append(totalMs)
        measured.lines.append(String(
            format: "Pass %d: ASR %.0f ms, paste-set %.0f us, post %.0f us, restore %.0f us, total %.1f ms",
            pass,
            asrMs,
            timing.setMicros,
            timing.postMicros,
            timing.restoreMicros,
            totalMs
        ))
    }

    private static func appendSummary(_ measured: Measurements, lines: inout [String]) {
        lines.append("")
        lines.append("--- Medians (5 runs) ---")
        lines.append(String(format: "ASR inference: %.0f ms", median(measured.asrLatencies)))
        lines.append(String(format: "Pasteboard set: %.0f us", median(measured.pasteSetMicros)))
        lines.append(String(format: "CGEvent post: %.0f us", median(measured.pastePostMicros)))
        lines.append(String(format: "Pasteboard restore: %.0f us", median(measured.restoreMicros)))
        lines.append(String(format: "Machine-work total: %.1f ms", median(measured.totalLatencies)))
        lines.append("Last transcript: \"\(measured.transcript)\"")
        lines.append("Manual check required: verify signposts in Instruments for subsystem com.macallyouneed.spike.")
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}
