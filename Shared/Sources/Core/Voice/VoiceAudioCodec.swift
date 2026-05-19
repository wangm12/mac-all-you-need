import Foundation

public enum VoiceAudioCodec {
    public enum DecodeError: Error, Equatable {
        case truncated
        case badMagic
        case unsupportedFormat
    }

    public struct DecodedAudio: Equatable {
        public let samples: [Float]
        public let sampleRate: Int

        public init(samples: [Float], sampleRate: Int) {
            self.samples = samples
            self.sampleRate = sampleRate
        }
    }

    public static func decodeWAV(_ data: Data) throws -> DecodedAudio {
        guard data.count >= 44 else { throw DecodeError.truncated }
        let bytes = [UInt8](data)

        func ascii(_ at: Int, length: Int) -> String {
            String(bytes: bytes[at..<at + length], encoding: .ascii) ?? ""
        }
        func u16(_ at: Int) -> UInt16 {
            UInt16(bytes[at]) | (UInt16(bytes[at + 1]) << 8)
        }
        func u32(_ at: Int) -> UInt32 {
            UInt32(bytes[at]) | (UInt32(bytes[at + 1]) << 8)
                | (UInt32(bytes[at + 2]) << 16) | (UInt32(bytes[at + 3]) << 24)
        }

        guard ascii(0, length: 4) == "RIFF", ascii(8, length: 4) == "WAVE" else {
            throw DecodeError.badMagic
        }
        guard ascii(12, length: 4) == "fmt " else {
            throw DecodeError.unsupportedFormat
        }
        let audioFormat = u16(20)
        let numChannels = u16(22)
        let sampleRate = Int(u32(24))
        let bitsPerSample = u16(34)
        guard audioFormat == 1, numChannels == 1, bitsPerSample == 16 else {
            throw DecodeError.unsupportedFormat
        }

        var cursor = 36
        while cursor + 8 <= bytes.count {
            let chunkID = ascii(cursor, length: 4)
            let chunkSize = Int(u32(cursor + 4))
            let payloadStart = cursor + 8
            if chunkID == "data" {
                guard payloadStart + chunkSize <= bytes.count else { throw DecodeError.truncated }
                var samples: [Float] = []
                samples.reserveCapacity(chunkSize / 2)
                var i = payloadStart
                while i + 1 < payloadStart + chunkSize {
                    let raw = Int16(bitPattern: u16(i))
                    samples.append(Float(raw) / 32_768)
                    i += 2
                }
                return DecodedAudio(samples: samples, sampleRate: sampleRate)
            }
            cursor = payloadStart + chunkSize
        }
        throw DecodeError.truncated
    }

    public static func encodeWAV(samples: [Float], sampleRate: Int) -> Data {
        let int16Samples = samples.map { sample -> Int16 in
            let clamped = max(-1.0, min(1.0, sample))
            let scaled = clamped * 32_768.0
            return Int16(max(Float(Int16.min), min(Float(Int16.max), scaled)))
        }
        let dataSize = int16Samples.count * 2
        let fmtSize = 16
        let fileSize = 4 + 8 + fmtSize + 8 + dataSize

        var wav = Data(capacity: 8 + fileSize)
        func u32(_ value: UInt32) {
            var val = value.littleEndian
            wav.append(contentsOf: withUnsafeBytes(of: &val) { Array($0) })
        }
        func u16(_ value: UInt16) {
            var val = value.littleEndian
            wav.append(contentsOf: withUnsafeBytes(of: &val) { Array($0) })
        }
        func ascii(_ str: String) { wav.append(contentsOf: str.utf8.prefix(4)) }

        let sampleRateU = UInt32(sampleRate)
        let bitsPerSample: UInt16 = 16
        let numChannels: UInt16 = 1
        let byteRate = sampleRateU * UInt32(numChannels) * UInt32(bitsPerSample) / 8
        let blockAlign = numChannels * bitsPerSample / 8

        ascii("RIFF")
        u32(UInt32(fileSize))
        ascii("WAVE")

        ascii("fmt ")
        u32(UInt32(fmtSize))
        u16(UInt16(1))
        u16(numChannels)
        u32(sampleRateU)
        u32(byteRate)
        u16(blockAlign)
        u16(bitsPerSample)

        ascii("data")
        u32(UInt32(dataSize))
        for sample in int16Samples {
            var val = sample.littleEndian
            wav.append(contentsOf: withUnsafeBytes(of: &val) { Array($0) })
        }
        return wav
    }
}
