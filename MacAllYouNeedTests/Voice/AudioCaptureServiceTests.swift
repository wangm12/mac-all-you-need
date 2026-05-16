import AVFoundation
@testable import MacAllYouNeed
import XCTest

final class AudioCaptureServiceTests: XCTestCase {
    func testAccumulatorSnapshotsSamplesAppendedOutsideMainActor() {
        let accumulator = AudioSampleAccumulator()

        accumulator.append([0.1, -0.4, 0.2], peak: 0.4)

        let snapshot = accumulator.snapshot()
        XCTAssertEqual(snapshot.samples, [0.1, -0.4, 0.2])
        XCTAssertEqual(snapshot.peak, 0.4)
    }

    func testAccumulatorResetClearsSamplesAndPeak() {
        let accumulator = AudioSampleAccumulator()
        accumulator.append([0.1, -0.4], peak: 0.4)

        accumulator.reset()

        let snapshot = accumulator.snapshot()
        XCTAssertTrue(snapshot.samples.isEmpty)
        XCTAssertEqual(snapshot.peak, 0)
    }

    func testDownmixesStereoFloatBufferToMonoArray() throws {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48000,
            channels: 2,
            interleaved: false
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 3))
        buffer.frameLength = 3
        buffer.floatChannelData?[0][0] = 0.2
        buffer.floatChannelData?[0][1] = 0.4
        buffer.floatChannelData?[0][2] = 0.6
        buffer.floatChannelData?[1][0] = 0.4
        buffer.floatChannelData?[1][1] = 0.6
        buffer.floatChannelData?[1][2] = 0.8

        let samples = AudioCaptureService.floatMonoSamples(from: buffer)
        XCTAssertEqual(samples.count, 3)
        XCTAssertEqual(samples[0], 0.3, accuracy: 0.0001)
        XCTAssertEqual(samples[1], 0.5, accuracy: 0.0001)
        XCTAssertEqual(samples[2], 0.7, accuracy: 0.0001)
    }

    func testResamplesAligned48kSamplesTo16k() {
        let samples: [Float] = [0, 1, 2, 3, 4, 5]

        XCTAssertEqual(
            AudioCaptureService.resample(samples, from: 48000, to: 16000),
            [0, 3]
        )
    }

    func testLivePeakLevelTracksCurrentPeakWithFastDecay() {
        XCTAssertEqual(
            AudioCaptureService.livePeakLevel(previous: 0.2, incomingPeak: 0.7),
            1,
            accuracy: 0.0001
        )
        XCTAssertGreaterThan(
            AudioCaptureService.livePeakLevel(previous: 0.05, incomingPeak: 0.03),
            0.25
        )
        XCTAssertEqual(
            AudioCaptureService.livePeakLevel(previous: 0.8, incomingPeak: 0),
            0.496,
            accuracy: 0.0001
        )
    }

    func testLevelSamplingTargetsInteractiveWaveformCadence() {
        XCTAssertLessThanOrEqual(VoiceLevelSampling.intervalMilliseconds, 33)
    }
}
