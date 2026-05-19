import AudioToolbox
import AVFoundation
import Core
import CoreAudio
import Foundation
import Observation
import OSLog

enum VoiceAudioSettings {
    static let microphoneIDKey = "voice.audio.microphoneID"
    static let systemMicrophoneID = "system"

    static func preferredMicrophoneID(from defaults: UserDefaults = AppGroupSettings.defaults) -> String {
        defaults.string(forKey: microphoneIDKey) ?? systemMicrophoneID
    }

    static func normalizedPreferredMicrophoneID(
        _ preferredID: String,
        availableDeviceIDs: Set<String>
    ) -> String {
        let trimmed = preferredID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != systemMicrophoneID else {
            return systemMicrophoneID
        }
        return availableDeviceIDs.contains(trimmed) ? trimmed : systemMicrophoneID
    }

    static func currentSystemInputName() -> String {
        AVCaptureDevice.default(for: .audio)?.localizedName ?? "System input"
    }
}

struct VoiceMicrophoneOptionDescriptor: Identifiable, Equatable {
    static let systemID = VoiceAudioSettings.systemMicrophoneID

    let id: String
    let name: String

    static func available() -> [VoiceMicrophoneOptionDescriptor] {
        let system = VoiceMicrophoneOptionDescriptor(
            id: systemID,
            name: "Auto-detect (\(VoiceAudioSettings.currentSystemInputName()))"
        )
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        var seen = Set<String>()
        let devices = session.devices.compactMap { device -> VoiceMicrophoneOptionDescriptor? in
            guard seen.insert(device.uniqueID).inserted else { return nil }
            return VoiceMicrophoneOptionDescriptor(id: device.uniqueID, name: device.localizedName)
        }
        return [system] + devices
    }
}

enum AudioCaptureServiceError: LocalizedError {
    case microphoneSelectionFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .microphoneSelectionFailed(status):
            "Could not switch to the selected microphone. AudioUnit status: \(status)."
        }
    }
}

struct CapturedAudio {
    let samples: [Float]
    let sampleRate: Double
    let startedAt: Date
    let endedAt: Date
    let peakLevel: Float
}

final class AudioSampleAccumulator {
    private let lock = NSLock()
    private var storedSamples: [Float] = []
    private var storedPeak: Float = 0

    func reset(keepingCapacity: Bool = true) {
        lock.lock()
        storedSamples.removeAll(keepingCapacity: keepingCapacity)
        storedPeak = 0
        lock.unlock()
    }

    func append(_ samples: [Float], peak: Float) {
        lock.lock()
        storedSamples.append(contentsOf: samples)
        storedPeak = max(storedPeak, peak)
        lock.unlock()
    }

    func snapshot() -> (samples: [Float], peak: Float) {
        lock.lock()
        let result = (storedSamples, storedPeak)
        lock.unlock()
        return result
    }
}

@MainActor
@Observable
final class AudioCaptureService {
    private var engine: AVAudioEngine?
    private let accumulator = AudioSampleAccumulator()
    private var startedAt: Date?
    private var captureID = UUID()
    private(set) var peakLevel: Float = 0
    private let log = Logger(subsystem: "com.macallyouneed.voice", category: "audio")

    func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func start() throws {
        stopWithoutResult()
        accumulator.reset()
        peakLevel = 0
        startedAt = Date()
        let captureID = UUID()
        self.captureID = captureID

        let preferredID = VoiceAudioSettings.preferredMicrophoneID()
        log.info("audio start — preferred mic: \(preferredID, privacy: .public)")

        let engine = AVAudioEngine()
        let input = engine.inputNode
        try applyPreferredInputDevice(to: input)
        let format = input.outputFormat(forBus: 0)
        log.info("audio format — sampleRate: \(format.sampleRate, privacy: .public) channels: \(format.channelCount, privacy: .public)")
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            let mono = Self.floatMonoSamples(from: buffer)
            let peak = mono.map(abs).max() ?? 0
            self?.accumulator.append(mono, peak: peak)
            Task { @MainActor [weak self] in
                guard let self, self.captureID == captureID else { return }
                peakLevel = Self.livePeakLevel(previous: peakLevel, incomingPeak: peak)
            }
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
        log.info("audio engine started")
    }

    func stop() -> CapturedAudio? {
        guard let engine, let startedAt else {
            log.error("audio stop called but engine/startedAt nil")
            return nil
        }
        let endedAt = Date()
        let sampleRate = engine.inputNode.outputFormat(forBus: 0).sampleRate
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        let snapshot = accumulator.snapshot()
        self.engine = nil
        self.startedAt = nil
        captureID = UUID()
        let durationSec = String(format: "%.2f", endedAt.timeIntervalSince(startedAt))
        log.info("audio stop — samples: \(snapshot.samples.count, privacy: .public) sampleRate: \(sampleRate, privacy: .public) peak: \(snapshot.peak, privacy: .public) duration: \(durationSec, privacy: .public)s")
        return CapturedAudio(
            samples: snapshot.samples,
            sampleRate: sampleRate,
            startedAt: startedAt,
            endedAt: endedAt,
            peakLevel: snapshot.peak
        )
    }

    nonisolated static func floatMonoSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channels = buffer.floatChannelData else { return [] }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard channelCount > 0 else { return [] }

        return (0 ..< frameCount).map { frame in
            var sum: Float = 0
            for channel in 0 ..< channelCount {
                sum += channels[channel][frame]
            }
            return sum / Float(channelCount)
        }
    }

    nonisolated static func resample(_ samples: [Float], from sourceRate: Double, to targetRate: Double) -> [Float] {
        guard !samples.isEmpty, sourceRate > 0, targetRate > 0 else { return [] }
        guard abs(sourceRate - targetRate) > 0.1 else { return samples }

        let outputCount = max(1, Int((Double(samples.count) * targetRate / sourceRate).rounded(.down)))
        let ratio = sourceRate / targetRate
        return (0 ..< outputCount).map { outputIndex in
            let sourceIndex = Double(outputIndex) * ratio
            let lower = min(Int(sourceIndex.rounded(.down)), samples.count - 1)
            let upper = min(lower + 1, samples.count - 1)
            let fraction = Float(sourceIndex - Double(lower))
            return samples[lower] + (samples[upper] - samples[lower]) * fraction
        }
    }

    nonisolated static func livePeakLevel(previous: Float, incomingPeak: Float) -> Float {
        max(normalizedLivePeak(incomingPeak), previous * 0.62)
    }

    nonisolated static func normalizedLivePeak(_ incomingPeak: Float) -> Float {
        let floor: Float = 0.012
        let ceiling: Float = 0.18
        let clamped = min(max(incomingPeak - floor, 0), ceiling - floor) / (ceiling - floor)
        return Float(pow(Double(clamped), 0.55))
    }

    private func stopWithoutResult() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        startedAt = nil
        captureID = UUID()
    }

    private func applyPreferredInputDevice(to input: AVAudioInputNode) throws {
        let preferredID = VoiceAudioSettings.preferredMicrophoneID()
        guard preferredID != VoiceAudioSettings.systemMicrophoneID,
              let deviceID = CoreAudioInputDeviceResolver.deviceID(forUID: preferredID),
              let audioUnit = input.audioUnit
        else {
            log.info("mic selection — using system default (preferredID: \(preferredID, privacy: .public))")
            return
        }

        log.info("mic selection — applying deviceID: \(deviceID, privacy: .public) for uid: \(preferredID, privacy: .public)")
        var selectedDeviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &selectedDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            log.error("mic selection failed — deviceID: \(deviceID, privacy: .public) status: \(status, privacy: .public)")
            throw AudioCaptureServiceError.microphoneSelectionFailed(status)
        }
        log.info("mic selection succeeded — deviceID: \(deviceID, privacy: .public)")
    }
}

private enum CoreAudioInputDeviceResolver {
    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        guard !uid.isEmpty else { return nil }
        return allDeviceIDs().first { deviceUID(for: $0) == uid }
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        )
        guard sizeStatus == noErr, dataSize > 0 else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.stride
        var devices = Array(repeating: AudioDeviceID(), count: deviceCount)
        let dataStatus = devices.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return OSStatus(kAudioHardwareBadObjectError) }
            return AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &dataSize,
                baseAddress
            )
        }
        guard dataStatus == noErr else { return [] }
        return devices
    }

    private static func deviceUID(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &uid) { pointer in
            AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &dataSize,
                pointer
            )
        }
        guard status == noErr else { return nil }
        return uid as String?
    }
}
