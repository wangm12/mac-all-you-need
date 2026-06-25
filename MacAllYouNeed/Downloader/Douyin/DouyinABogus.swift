import Foundation

/// Native Swift port of the Douyin `a_bogus` signer (reference: douyin-downloader `utils/abogus.py`).
///
/// The Douyin `/aweme/v1/web/aweme/detail/` endpoint rejects requests signed only
/// with `X-Bogus` (returns an empty 200). `a_bogus` is the working signature for the
/// modern web API, so single-video resolution depends on this implementation.
enum DouyinABogus {
    // MARK: - Public API

    struct Signature {
        let aBogus: String
        let userAgent: String
    }

    /// Generates the `a_bogus` token for a query string.
    ///
    /// - Parameters:
    ///   - params: the URL query string WITHOUT the leading `?` — must match the
    ///     exact query string that will be sent on the request.
    ///   - body: request body (empty for GET).
    ///   - userAgent: the User-Agent header that will accompany the request.
    ///   - fingerprint: a browser fingerprint string (see `chromeFingerprint`).
    ///   - randomPrefix: injectable random bytes (testing only); generated when nil.
    ///   - startTimeMillis / endTimeMillis: injectable timestamps (testing only).
    static func generate(
        params: String,
        body: String = "",
        userAgent: String,
        fingerprint: String,
        randomPrefix: [Int]? = nil,
        startTimeMillis: Int? = nil,
        endTimeMillis: Int? = nil
    ) -> Signature {
        let salt = "cus"
        let character = Array("Dkdpgh2ZmsQB80/MfvV36XI1R45-WUAlEixNLwoqYTOPuzKFjJnry79HbGcaStCe")
        let character2 = Array("ckdp1h4ZKsUB80/Mfvw36XIgR25+WQAlEi7NLboqYTOPuzmFjJnryx9HVGDaStCe")
        let alphabets = [character, character2]
        let options = [0, 1, 14]
        let uaKey: [UInt8] = [0x00, 0x01, 0x0e]
        let aid = 6383
        let pageId = 0

        // Encryption timestamps (ms).
        let startEncryption = startTimeMillis ?? Int(Date().timeIntervalSince1970 * 1000)

        // params/body salted+double SM3 hashed.
        let array1 = saltedString(params, salt: salt)
        let array2 = saltedString(body, salt: salt)

        // UA: RC4 → custom base64 (alphabet 1) → single SM3 (no salt).
        let uaRC4 = rc4(key: uaKey, data: Array(userAgent.utf8))
        let uaBase64 = base64Encode(uaRC4.map { Int($0) }, alphabet: alphabets[1])
        let array3 = sm3ToArray(Array(uaBase64.utf8).map { Int($0) })

        let endEncryption = endTimeMillis ?? Int(Date().timeIntervalSince1970 * 1000)

        var abDir: [Int: Int] = [
            8: 3,
            18: 44,
            66: 0,
            69: 0,
            70: 0,
            71: 0
        ]

        abDir[20] = (startEncryption >> 24) & 255
        abDir[21] = (startEncryption >> 16) & 255
        abDir[22] = (startEncryption >> 8) & 255
        abDir[23] = startEncryption & 255
        abDir[24] = Int(Double(startEncryption) / 256 / 256 / 256 / 256)
        abDir[25] = Int(Double(startEncryption) / 256 / 256 / 256 / 256 / 256)

        abDir[26] = (options[0] >> 24) & 255
        abDir[27] = (options[0] >> 16) & 255
        abDir[28] = (options[0] >> 8) & 255
        abDir[29] = options[0] & 255

        abDir[30] = (options[1] / 256) & 255
        abDir[31] = (options[1] % 256) & 255
        abDir[32] = (options[1] >> 24) & 255
        abDir[33] = (options[1] >> 16) & 255

        abDir[34] = (options[2] >> 24) & 255
        abDir[35] = (options[2] >> 16) & 255
        abDir[36] = (options[2] >> 8) & 255
        abDir[37] = options[2] & 255

        abDir[38] = array1[21]
        abDir[39] = array1[22]
        abDir[40] = array2[21]
        abDir[41] = array2[22]
        abDir[42] = array3[23]
        abDir[43] = array3[24]

        abDir[44] = (endEncryption >> 24) & 255
        abDir[45] = (endEncryption >> 16) & 255
        abDir[46] = (endEncryption >> 8) & 255
        abDir[47] = endEncryption & 255
        abDir[48] = abDir[8]
        abDir[49] = Int(Double(endEncryption) / 256 / 256 / 256 / 256)
        abDir[50] = Int(Double(endEncryption) / 256 / 256 / 256 / 256 / 256)

        abDir[51] = (pageId >> 24) & 255
        abDir[52] = (pageId >> 16) & 255
        abDir[53] = (pageId >> 8) & 255
        abDir[54] = pageId & 255
        abDir[55] = pageId
        abDir[56] = aid
        abDir[57] = aid & 255
        abDir[58] = (aid >> 8) & 255
        abDir[59] = (aid >> 16) & 255
        abDir[60] = (aid >> 24) & 255

        abDir[64] = fingerprint.count
        abDir[65] = fingerprint.count

        let sortIndex = [
            18, 20, 52, 26, 30, 34, 58, 38, 40, 53, 42, 21, 27, 54, 55, 31, 35, 57, 39, 41, 43, 22, 28,
            32, 60, 36, 23, 29, 33, 37, 44, 45, 59, 46, 47, 48, 49, 50, 24, 25, 65, 66, 70, 71
        ]
        let sortIndex2 = [
            18, 20, 26, 30, 34, 38, 40, 42, 21, 27, 31, 35, 39, 41, 43, 22, 28, 32, 36, 23, 29, 33, 37,
            44, 45, 46, 47, 48, 49, 50, 24, 25, 52, 53, 54, 55, 57, 58, 59, 60, 65, 66, 70, 71
        ]

        var sortedValues = sortIndex.map { abDir[$0] ?? 0 }
        let fingerprintArray = fingerprint.unicodeScalars.map { Int($0.value) }

        var abXor = 0
        for index in 0 ..< (sortIndex2.count - 1) {
            if index == 0 {
                abXor = abDir[sortIndex2[index]] ?? 0
            }
            abXor ^= abDir[sortIndex2[index + 1]] ?? 0
        }

        sortedValues.append(contentsOf: fingerprintArray)
        sortedValues.append(abXor)

        let prefix = randomPrefix ?? generateRandomBytes()
        let abogusCodePoints = prefix + transformBytes(sortedValues)
        let aBogus = abogusEncode(abogusCodePoints, alphabet: alphabets[0])
        return Signature(aBogus: aBogus, userAgent: userAgent)
    }

    /// Chrome-style fingerprint (`Win32`), matching the reference generator's layout.
    static func chromeFingerprint() -> String {
        let innerWidth = Int.random(in: 1024 ... 1920)
        let innerHeight = Int.random(in: 768 ... 1080)
        let outerWidth = innerWidth + Int.random(in: 24 ... 32)
        let outerHeight = innerHeight + Int.random(in: 75 ... 90)
        let screenX = 0
        let screenY = [0, 30].randomElement() ?? 0
        let sizeWidth = Int.random(in: 1024 ... 1920)
        let sizeHeight = Int.random(in: 768 ... 1080)
        let availWidth = Int.random(in: 1280 ... 1920)
        let availHeight = Int.random(in: 800 ... 1080)
        return "\(innerWidth)|\(innerHeight)|\(outerWidth)|\(outerHeight)|"
            + "\(screenX)|\(screenY)|0|0|\(sizeWidth)|\(sizeHeight)|"
            + "\(availWidth)|\(availHeight)|\(innerWidth)|\(innerHeight)|24|24|Win32"
    }

    // MARK: - Param hashing

    private static func saltedString(_ value: String, salt: String) -> [Int] {
        // params_to_array(params_to_array(value + salt))
        let salted = value + salt
        let first = sm3ToArray(Array(salted.utf8).map { Int($0) })
        return sm3ToArray(first)
    }

    private static func sm3ToArray(_ input: [Int]) -> [Int] {
        let bytes = input.map { UInt8($0 & 0xff) }
        let hex = SM3.hashHex(bytes)
        var out: [Int] = []
        out.reserveCapacity(32)
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2)
            out.append(Int(hex[idx ..< next], radix: 16) ?? 0)
            idx = next
        }
        return out
    }

    // MARK: - transform_bytes

    private static func transformBytes(_ bytesList: [Int]) -> [Int] {
        var bigArray = Self.bigArray
        var result: [Int] = []
        result.reserveCapacity(bytesList.count)
        var indexB = bigArray[1]
        var initialValue = 0
        var valueE = 0
        let count = bigArray.count

        for (index, charValue) in bytesList.enumerated() {
            var sumInitial: Int
            if index == 0 {
                initialValue = bigArray[indexB]
                sumInitial = indexB + initialValue
                bigArray[1] = initialValue
                bigArray[indexB] = indexB
            } else {
                sumInitial = initialValue + valueE
            }

            sumInitial %= count
            let valueF = bigArray[sumInitial]
            result.append(charValue ^ valueF)

            valueE = bigArray[(index + 2) % count]
            sumInitial = (indexB + valueE) % count
            initialValue = bigArray[sumInitial]
            bigArray[sumInitial] = bigArray[(index + 2) % count]
            bigArray[(index + 2) % count] = initialValue
            indexB = sumInitial
        }

        return result
    }

    // MARK: - Encoding

    private static func base64Encode(_ input: [Int], alphabet: [Character]) -> String {
        var binary = ""
        binary.reserveCapacity(input.count * 8)
        for value in input {
            binary += String(repeating: "0", count: 8 - String(value & 0xff, radix: 2).count)
                + String(value & 0xff, radix: 2)
        }
        let paddingLength = (6 - binary.count % 6) % 6
        binary += String(repeating: "0", count: paddingLength)

        var output = ""
        var idx = binary.startIndex
        while idx < binary.endIndex {
            let next = binary.index(idx, offsetBy: 6)
            let index = Int(binary[idx ..< next], radix: 2) ?? 0
            output.append(alphabet[index])
            idx = next
        }
        output += String(repeating: "=", count: paddingLength / 2)
        return output
    }

    private static func abogusEncode(_ input: [Int], alphabet: [Character]) -> String {
        var result: [Character] = []
        let masksAndShifts: [(shift: Int, mask: Int)] = [
            (18, 0xFC0000), (12, 0x03F000), (6, 0x0FC0), (0, 0x3F)
        ]
        var i = 0
        while i < input.count {
            let n: Int
            if i + 2 < input.count {
                n = (input[i] << 16) | (input[i + 1] << 8) | input[i + 2]
            } else if i + 1 < input.count {
                n = (input[i] << 16) | (input[i + 1] << 8)
            } else {
                n = input[i] << 16
            }

            for (shift, mask) in masksAndShifts {
                if shift == 6, i + 1 >= input.count { break }
                if shift == 0, i + 2 >= input.count { break }
                result.append(alphabet[(n & mask) >> shift])
            }
            i += 3
        }
        let pad = (4 - result.count % 4) % 4
        result.append(contentsOf: Array(repeating: "=", count: pad))
        return String(result)
    }

    private static func rc4(key: [UInt8], data: [UInt8]) -> [UInt8] {
        var s = Array(0 ... 255)
        var j = 0
        for i in 0 ..< 256 {
            j = (j + s[i] + Int(key[i % key.count])) % 256
            s.swapAt(i, j)
        }
        var i = 0
        j = 0
        var out: [UInt8] = []
        out.reserveCapacity(data.count)
        for byte in data {
            i = (i + 1) % 256
            j = (j + s[i]) % 256
            s.swapAt(i, j)
            out.append(byte ^ UInt8(s[(s[i] + s[j]) % 256]))
        }
        return out
    }

    private static func generateRandomBytes(length: Int = 3) -> [Int] {
        var out: [Int] = []
        out.reserveCapacity(length * 4)
        for _ in 0 ..< length {
            let rd = Int(Double.random(in: 0 ..< 1) * 10000)
            out.append(((rd & 255) & 170) | 1)
            out.append(((rd & 255) & 85) | 2)
            out.append((((rd % 0x1_0000_0000) >> 8) & 170) | 5)
            out.append((((rd % 0x1_0000_0000) >> 8) & 85) | 40)
        }
        return out
    }

    // swiftformat:disable all
    private static let bigArray: [Int] = [
        121, 243,  55, 234, 103,  36,  47, 228,  30, 231, 106,   6, 115,  95,  78, 101, 250, 207, 198,  50,
        139, 227, 220, 105,  97, 143,  34,  28, 194, 215,  18, 100, 159, 160,  43,   8, 169, 217, 180, 120,
        247,  45,  90,  11,  27, 197,  46,   3,  84,  72,   5,  68,  62,  56, 221,  75, 144,  79,  73, 161,
        178,  81,  64, 187, 134, 117, 186, 118,  16, 241, 130,  71,  89, 147, 122, 129,  65,  40,  88, 150,
        110, 219, 199, 255, 181, 254,  48,   4, 195, 248, 208,  32, 116, 167,  69, 201,  17, 124, 125, 104,
         96,  83,  80, 127, 236, 108, 154, 126, 204,  15,  20, 135, 112, 158,  13,   1, 188, 164, 210, 237,
        222,  98, 212,  77, 253,  42, 170, 202,  26,  22,  29, 182, 251,  10, 173, 152,  58, 138,  54, 141,
        185,  33, 157,  31, 252, 132, 233, 235, 102, 196, 191, 223, 240, 148,  39, 123,  92,  82, 128, 109,
         57,  24,  38, 113, 209, 245,   2, 119, 153, 229, 189, 214, 230, 174, 232,  63,  52, 205,  86, 140,
         66, 175, 111, 171, 246, 133, 238, 193,  99,  60,  74,  91, 225,  51,  76,  37, 145, 211, 166, 151,
        213, 206,   0, 200, 244, 176, 218,  44, 184, 172,  49, 216,  93, 168,  53,  21, 183,  41,  67,  85,
        224, 155, 226, 242,  87, 177, 146,  70, 190,  12, 162,  19, 137, 114,  25, 165, 163, 192,  23,  59,
          9,  94, 179, 107,  35,   7, 142, 131, 239, 203, 149, 136,  61, 249,  14, 156
    ]
    // swiftformat:enable all
}

/// Minimal SM3 (GM/T 0004-2012) hash used by the `a_bogus` signer.
enum SM3 {
    private static let iv: [UInt32] = [
        0x7380_166f, 0x4914_b2b9, 0x1724_42d7, 0xda8a_0600,
        0xa96f_30bc, 0x1631_38aa, 0xe38d_ee4d, 0xb0fb_0e4e
    ]

    static func hashHex(_ message: [UInt8]) -> String {
        var msg = message
        let bitLength = UInt64(message.count) * 8
        msg.append(0x80)
        while msg.count % 64 != 56 { msg.append(0x00) }
        for shift in stride(from: 56, through: 0, by: -8) {
            msg.append(UInt8((bitLength >> UInt64(shift)) & 0xff))
        }

        var v = iv
        var block = 0
        while block < msg.count {
            v = compress(v, Array(msg[block ..< block + 64]))
            block += 64
        }

        return v.map { String(format: "%08x", $0) }.joined()
    }

    private static func rotl(_ x: UInt32, _ n: UInt32) -> UInt32 {
        let n = n % 32
        return (x << n) | (x >> (32 - n))
    }

    private static func p0(_ x: UInt32) -> UInt32 { x ^ rotl(x, 9) ^ rotl(x, 17) }
    private static func p1(_ x: UInt32) -> UInt32 { x ^ rotl(x, 15) ^ rotl(x, 23) }

    private static func compress(_ vIn: [UInt32], _ block: [UInt8]) -> [UInt32] {
        var w = [UInt32](repeating: 0, count: 68)
        for i in 0 ..< 16 {
            w[i] = (UInt32(block[i * 4]) << 24)
                | (UInt32(block[i * 4 + 1]) << 16)
                | (UInt32(block[i * 4 + 2]) << 8)
                | UInt32(block[i * 4 + 3])
        }
        for i in 16 ..< 68 {
            w[i] = p1(w[i - 16] ^ w[i - 9] ^ rotl(w[i - 3], 15)) ^ rotl(w[i - 13], 7) ^ w[i - 6]
        }
        var w1 = [UInt32](repeating: 0, count: 64)
        for i in 0 ..< 64 { w1[i] = w[i] ^ w[i + 4] }

        var a = vIn[0], b = vIn[1], c = vIn[2], d = vIn[3]
        var e = vIn[4], f = vIn[5], g = vIn[6], h = vIn[7]

        for j in 0 ..< 64 {
            let t: UInt32 = j < 16 ? 0x79cc_4519 : 0x7a87_9d8a
            let ss1 = rotl(rotl(a, 12) &+ e &+ rotl(t, UInt32(j)), 7)
            let ss2 = ss1 ^ rotl(a, 12)
            let ff = j < 16 ? (a ^ b ^ c) : ((a & b) | (a & c) | (b & c))
            let gg = j < 16 ? (e ^ f ^ g) : ((e & f) | (~e & g))
            let tt1 = ff &+ d &+ ss2 &+ w1[j]
            let tt2 = gg &+ h &+ ss1 &+ w[j]
            d = c
            c = rotl(b, 9)
            b = a
            a = tt1
            h = g
            g = rotl(f, 19)
            f = e
            e = p0(tt2)
        }

        return [
            a ^ vIn[0], b ^ vIn[1], c ^ vIn[2], d ^ vIn[3],
            e ^ vIn[4], f ^ vIn[5], g ^ vIn[6], h ^ vIn[7]
        ]
    }
}
