import AVFoundation
import Foundation

/// Gate 1: request microphone permission, then capture three seconds of input.
enum SpikeMicGate {
    static func run() async -> String {
        var lines: [String] = []
        let start = Date()

        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        lines.append("AVCaptureDevice.requestAccess(.audio): granted=\(granted)")
        guard granted else {
            lines.append("FAIL: microphone access was denied.")
            return lines.joined(separator: "\n")
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        lines.append(
            "Input format: \(format.sampleRate) Hz, \(format.channelCount) ch, \(format.commonFormat.rawValue)"
        )

        var totalFrames: AVAudioFrameCount = 0
        var peakLevel: Float = 0

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            totalFrames += buffer.frameLength
            guard let channels = buffer.floatChannelData else { return }
            let channelCount = Int(buffer.format.channelCount)
            let frameCount = Int(buffer.frameLength)
            for channelIndex in 0 ..< channelCount {
                let channel = channels[channelIndex]
                for frameIndex in 0 ..< frameCount {
                    peakLevel = max(peakLevel, abs(channel[frameIndex]))
                }
            }
        }

        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            lines.append("engine.start() error: \(error)")
            return lines.joined(separator: "\n")
        }

        try? await Task.sleep(nanoseconds: 3_000_000_000)

        engine.stop()
        input.removeTap(onBus: 0)

        let elapsed = Date().timeIntervalSince(start)
        let capturedSeconds = Double(totalFrames) / format.sampleRate
        lines.append("Captured \(totalFrames) frames = \(String(format: "%.2f", capturedSeconds)) s")
        lines.append("Peak level (linear): \(String(format: "%.4f", peakLevel))")
        lines.append("Wall-clock elapsed: \(String(format: "%.2f", elapsed)) s")

        if peakLevel < 0.001 {
            lines.append("WARN: peak level is near zero; verify the mic is unmuted and selected.")
        } else {
            lines.append("OK: audio captured successfully.")
        }

        return lines.joined(separator: "\n")
    }
}
