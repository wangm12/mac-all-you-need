@testable import Core
import XCTest

final class VoiceAudioCodecTests: XCTestCase {
    func testDecodeWAVReturnsSamplesAndSampleRate() throws {
        let wav = Self.fixtureWAV(sampleRate: 16_000, int16Samples: [0, 1, -1, 32_767])
        let decoded = try VoiceAudioCodec.decodeWAV(wav)
        XCTAssertEqual(decoded.sampleRate, 16_000)
        XCTAssertEqual(decoded.samples.count, 4)
        XCTAssertEqual(decoded.samples[0], 0)
        XCTAssertEqual(decoded.samples[3], Float(32_767) / 32_768, accuracy: 0.0001)
    }

    func testDecodeWAVRejectsTruncatedHeader() {
        XCTAssertThrowsError(try VoiceAudioCodec.decodeWAV(Data([0x52, 0x49, 0x46, 0x46]))) { error in
            XCTAssertEqual(error as? VoiceAudioCodec.DecodeError, .truncated)
        }
    }

    func testDecodeWAVRejectsWrongMagic() {
        var bad = Self.fixtureWAV(sampleRate: 16_000, int16Samples: [0])
        bad[0] = 0x58
        XCTAssertThrowsError(try VoiceAudioCodec.decodeWAV(bad)) { error in
            XCTAssertEqual(error as? VoiceAudioCodec.DecodeError, .badMagic)
        }
    }

    private static func fixtureWAV(sampleRate: Int, int16Samples: [Int16]) -> Data {
        let dataSize = int16Samples.count * 2
        let fmtSize = 16
        let fileSize = 4 + 8 + fmtSize + 8 + dataSize
        var wav = Data()
        func u32(_ val: UInt32) {
            var x = val.littleEndian
            wav.append(contentsOf: withUnsafeBytes(of: &x) { Array($0) })
        }
        func u16(_ val: UInt16) {
            var x = val.littleEndian
            wav.append(contentsOf: withUnsafeBytes(of: &x) { Array($0) })
        }
        func ascii(_ s: String) { wav.append(contentsOf: s.utf8.prefix(4)) }
        ascii("RIFF")
        u32(UInt32(fileSize))
        ascii("WAVE")
        ascii("fmt ")
        u32(UInt32(fmtSize))
        u16(1)
        u16(1)
        u32(UInt32(sampleRate))
        u32(UInt32(sampleRate * 2))
        u16(2)
        u16(16)
        ascii("data")
        u32(UInt32(dataSize))
        for s in int16Samples {
            var x = s.littleEndian
            wav.append(contentsOf: withUnsafeBytes(of: &x) { Array($0) })
        }
        return wav
    }
}
