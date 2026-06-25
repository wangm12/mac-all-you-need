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
    case preferredMicrophoneUnavailable(String)

    var errorDescription: String? {
        switch self {
        case let .microphoneSelectionFailed(status):
            "Could not switch to the selected microphone. AudioUnit status: \(status)."
        case let .preferredMicrophoneUnavailable(deviceID):
            "The selected microphone is unavailable (\(deviceID)). Plug it in or choose another input in Voice settings."
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
            let rms = Self.rmsLevel(from: mono)
            self?.accumulator.append(mono, peak: peak)
            Task { @MainActor [weak self] in
                guard let self, self.captureID == captureID else { return }
                let envelope = Self.speechWaveformEnvelope(rms: rms, peak: peak)
                peakLevel = Self.livePeakLevel(previous: peakLevel, incomingEnvelope: envelope)
            }
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
        log.info("audio engine started")
    }

    /// Non-destructive read of accumulated samples for background live ASR feeding.
    func liveFeedSnapshot() -> (samples: [Float], sampleRate: Double)? {
        guard let engine else { return nil }
        let sampleRate = engine.inputNode.outputFormat(forBus: 0).sampleRate
        let snapshot = accumulator.snapshot()
        return (snapshot.samples, sampleRate)
    }

    func stop() -> CapturedAudio? {
        guard let engine, let startedAt else {
            // Called defensively (e.g. from fail()) after already stopped — no-op.
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

    nonisolated static func rmsLevel(from samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(0) { $0 + $1 * $1 }
        return sqrt(sum / Float(samples.count))
    }

    /// Blends RMS with short-term peak so syllable attacks read on the HUD.
    /// Speech has a high crest factor; RMS alone stays visually quiet.
    nonisolated static func speechWaveformEnvelope(rms: Float, peak: Float) -> Float {
        max(rms, peak * 0.52)
    }

    nonisolated static func livePeakLevel(previous: Float, incomingEnvelope: Float) -> Float {
        let noiseGate: Float = 0.008
        let gain: Float = 5.0
        let attack: Float = 0.46
        let release: Float = 0.13
        let gated = max(0, incomingEnvelope - noiseGate)
        let target = min(1, gated * gain)
        let smoothing = target > previous ? attack : release
        return previous + (target - previous) * smoothing
    }

    /// Legacy peak-based helper retained for tests comparing decay behavior.
    nonisolated static func livePeakLevel(previous: Float, incomingRMS: Float) -> Float {
        livePeakLevel(previous: previous, incomingEnvelope: incomingRMS)
    }

    nonisolated static func livePeakLevel(previous: Float, incomingPeak: Float) -> Float {
        livePeakLevel(previous: previous, incomingEnvelope: incomingPeak)
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
        guard let audioUnit = input.audioUnit else {
            log.warning("mic selection — input node has no audio unit; using HAL default")
            return
        }

        let deviceID: AudioDeviceID?
        if preferredID == VoiceAudioSettings.systemMicrophoneID {
            deviceID = CoreAudioInputDeviceResolver.defaultInputDeviceID()
            log.info("mic selection — applying system default input device")
        } else if let resolved = CoreAudioInputDeviceResolver.deviceID(forUID: preferredID) {
            deviceID = resolved
            log.info("mic selection — applying deviceID: \(resolved, privacy: .public) for uid: \(preferredID, privacy: .public)")
        } else {
            log.error("mic selection — preferred uid not found: \(preferredID, privacy: .public)")
            throw AudioCaptureServiceError.preferredMicrophoneUnavailable(preferredID)
        }

        guard let deviceID else {
            log.error("mic selection — no default input device available")
            throw AudioCaptureServiceError.microphoneSelectionFailed(-1)
        }

        try setInputDevice(deviceID, on: audioUnit)
        if let activeUID = CoreAudioInputDeviceResolver.deviceUID(for: deviceID) {
            log.info("mic selection succeeded — active uid: \(activeUID, privacy: .public)")
        }
    }

    private func setInputDevice(_ deviceID: AudioDeviceID, on audioUnit: AudioUnit) throws {
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
    }
}

private enum CoreAudioInputDeviceResolver {
    static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

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

    static func deviceUID(for deviceID: AudioDeviceID) -> String? {
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
