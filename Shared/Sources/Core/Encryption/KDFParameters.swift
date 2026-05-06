import Foundation

public struct KDFParameters: Codable, Equatable, Sendable {
    public enum Algorithm: String, Codable, Sendable {
        case argon2id
    }

    public let algorithm: Algorithm
    public let iterations: UInt32
    public let memoryKB: UInt32
    public let parallelism: UInt32
    public let outputLen: UInt32

    public init(algorithm: Algorithm, iterations: UInt32, memoryKB: UInt32, parallelism: UInt32, outputLen: UInt32) {
        self.algorithm = algorithm
        self.iterations = iterations
        self.memoryKB = memoryKB
        self.parallelism = parallelism
        self.outputLen = outputLen
    }

    public static let defaultV1 = KDFParameters(
        algorithm: .argon2id,
        iterations: 3,
        memoryKB: 64 * 1024,
        parallelism: 4,
        outputLen: 32
    )
}
