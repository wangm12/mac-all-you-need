import AVFoundation
import Darwin
import FluidAudio
import Foundation

/// Gate 3: run a real local ASR model against the bundled fixture.
enum SpikeASRGate {
    static let groundTruth = "我今天要 deploy 这个 service 到 production"

    static func run() async -> String {
        guard #available(macOS 15, *) else {
            return "FAIL: Qwen3-ASR requires macOS 15 or later. Pick a fallback engine before Plan 8a."
        }

        var lines: [String] = []
        guard let samples = loadBundledFixture(lines: &lines) else { return lines.joined(separator: "\n") }
        guard let manager = await loadQwen3Manager(lines: &lines) else { return lines.joined(separator: "\n") }

        await warmUp(samples: samples, manager: manager, lines: &lines)
        let measured = await measuredPasses(samples: samples, manager: manager, count: 3)
        lines.append(contentsOf: measured.lines)

        guard !measured.latencies.isEmpty else {
            lines.append("FAIL: all inference passes failed.")
            return lines.joined(separator: "\n")
        }

        appendSummary(latencies: measured.latencies, transcript: measured.transcript, lines: &lines)
        return lines.joined(separator: "\n")
    }

    static func loadFloat32PCM(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard abs(format.sampleRate - 16000) < 0.1, format.channelCount == 1 else {
            throw NSError(
                domain: "VoiceSpike",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Fixture must be 16kHz mono; got \(format.sampleRate)Hz \(format.channelCount)ch"
                ]
            )
        }

        let frameCount = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "VoiceSpike", code: 2)
        }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?.pointee else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    static func residentMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return -1 }
        return Double(info.resident_size) / (1024.0 * 1024.0)
    }

    private struct MeasuredPasses {
        var latencies: [Double] = []
        var transcript = ""
        var lines: [String] = []
    }

    private static func loadBundledFixture(lines: inout [String]) -> [Float]? {
        guard let url = Bundle.main.url(forResource: "zh-en-mixed-5s", withExtension: "wav") else {
            lines.append("FAIL: fixture audio is missing from the app bundle.")
            return nil
        }

        let loadStart = Date()
        do {
            let samples = try loadFloat32PCM(from: url)
            let durationSec = Double(samples.count) / 16000.0
            lines.append(String(
                format: "Fixture loaded: %d samples (%.2fs) in %.0f ms",
                samples.count,
                durationSec,
                Date().timeIntervalSince(loadStart) * 1000
            ))
            return samples
        } catch {
            lines.append("FAIL: fixture load failed: \(error)")
            return nil
        }
    }

    @available(macOS 15, *)
    private static func loadQwen3Manager(lines: inout [String]) async -> Qwen3AsrManager? {
        let memBefore = residentMemoryMB()
        lines.append(String(format: "Resident memory before model load: %.1f MB", memBefore))

        let modelState = VoiceSpikeLog.signposter.beginInterval("modelLoad")
        let modelStart = Date()
        do {
            let cacheDir = try await Qwen3AsrModels.download(variant: .f32)
            let manager = Qwen3AsrManager()
            try await manager.loadModels(from: cacheDir)
            VoiceSpikeLog.signposter.endInterval("modelLoad", modelState)
            appendModelMetrics(start: modelStart, memBefore: memBefore, lines: &lines)
            return manager
        } catch {
            VoiceSpikeLog.signposter.endInterval("modelLoad", modelState)
            lines.append("FAIL: Qwen3-ASR model load failed: \(error)")
            return nil
        }
    }

    private static func appendModelMetrics(start: Date, memBefore: Double, lines: inout [String]) {
        let modelLoadMs = Date().timeIntervalSince(start) * 1000
        let memAfter = residentMemoryMB()
        lines.append(String(format: "Model loaded in %.0f ms", modelLoadMs))
        lines.append(String(format: "Resident memory after model load: %.1f MB (delta %.1f MB)", memAfter, memAfter - memBefore))
    }

    @available(macOS 15, *)
    private static func warmUp(samples: [Float], manager: Qwen3AsrManager, lines: inout [String]) async {
        do {
            _ = try await manager.transcribe(audioSamples: samples, language: .chinese, maxNewTokens: 512)
        } catch {
            lines.append("Warmup transcribe error: \(error)")
        }
    }

    @available(macOS 15, *)
    private static func measuredPasses(samples: [Float], manager: Qwen3AsrManager, count: Int) async -> MeasuredPasses {
        var measured = MeasuredPasses()
        for pass in 1 ... count {
            await measurePass(pass, samples: samples, manager: manager, measured: &measured)
        }
        return measured
    }

    @available(macOS 15, *)
    private static func measurePass(_ pass: Int, samples: [Float], manager: Qwen3AsrManager, measured: inout MeasuredPasses) async {
        let interval = VoiceSpikeLog.signposter.beginInterval("inference", "pass=\(pass)")
        let start = Date()
        do {
            measured.transcript = try await manager.transcribe(audioSamples: samples, language: .chinese, maxNewTokens: 512)
        } catch {
            VoiceSpikeLog.signposter.endInterval("inference", interval)
            measured.lines.append("Pass \(pass) ERROR: \(error)")
            return
        }
        VoiceSpikeLog.signposter.endInterval("inference", interval)
        let ms = Date().timeIntervalSince(start) * 1000
        measured.latencies.append(ms)
        measured.lines.append(String(format: "Pass %d: %.0f ms", pass, ms))
    }

    private static func appendSummary(latencies: [Double], transcript: String, lines: inout [String]) {
        let sorted = latencies.sorted()
        let median = sorted[sorted.count / 2]
        lines.append(String(format: "Median inference: %.0f ms", median))
        lines.append("Ground truth: \"\(groundTruth)\"")
        lines.append("Last transcript: \"\(transcript)\"")

        let overlap = lexicalOverlap(transcript: transcript, groundTruth: groundTruth)
        lines.append(String(format: "Lexical overlap: %.0f%%", overlap * 100))
        if transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("FAIL: transcript is empty. Gate 3 does not pass.")
        } else if overlap < 0.5 {
            lines.append("WARN: real transcript produced, but overlap is below the 50% acceptance bar.")
        } else {
            lines.append("OK: real transcript produced with >=50% lexical overlap.")
        }
    }

    private static func lexicalOverlap(transcript: String, groundTruth: String) -> Double {
        let truthUnits = lexicalUnits(in: groundTruth)
        guard !truthUnits.isEmpty else { return 0 }
        let transcriptUnits = Set(lexicalUnits(in: transcript))
        let hits = truthUnits.filter { transcriptUnits.contains($0) }.count
        return Double(hits) / Double(truthUnits.count)
    }

    private static func lexicalUnits(in text: String) -> [String] {
        var units: [String] = []
        var latin = ""
        for scalar in text.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar), scalar.value < 128 {
                latin.append(Character(scalar))
            } else {
                if !latin.isEmpty {
                    units.append(latin)
                    latin = ""
                }
                if (0x4E00 ... 0x9FFF).contains(scalar.value) {
                    units.append(String(scalar))
                }
            }
        }
        if !latin.isEmpty { units.append(latin) }
        return units
    }
}
