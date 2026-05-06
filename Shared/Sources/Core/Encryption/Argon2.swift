import CArgon2
import Foundation

public enum Argon2Error: Error, Equatable {
    case invalidSalt
    case libraryError(Int32)
}

public enum Argon2 {
    public static func hash(password: Data, salt: Data, params: KDFParameters) throws -> Data {
        guard salt.count >= 8 else { throw Argon2Error.invalidSalt }
        guard params.outputLen >= 4 else { throw Argon2Error.libraryError(0) }
        guard params.algorithm == .argon2id else { throw Argon2Error.libraryError(0) }

        var output = Data(count: Int(params.outputLen))
        let result: Int32 = output.withUnsafeMutableBytes { outBuf in
            password.withUnsafeBytes { pwdBuf in
                salt.withUnsafeBytes { saltBuf in
                    mayn_argon2id_hash_raw(
                        params.iterations,
                        params.memoryKB,
                        params.parallelism,
                        pwdBuf.baseAddress, pwdBuf.count,
                        saltBuf.baseAddress, saltBuf.count,
                        outBuf.baseAddress, outBuf.count
                    )
                }
            }
        }
        guard result == 0 else { throw Argon2Error.libraryError(result) }
        return output
    }
}
