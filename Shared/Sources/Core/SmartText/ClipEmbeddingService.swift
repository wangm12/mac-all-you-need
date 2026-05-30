import Foundation
import NaturalLanguage

public enum ClipEmbeddingService {
    public static func encode(_ vector: [Float]) -> Data {
        var littleEndian = vector.map { $0.bitPattern.littleEndian }
        return Data(bytes: &littleEndian, count: littleEndian.count * MemoryLayout<UInt32>.size)
    }

    public static func decode(_ data: Data) -> [Float]? {
        guard data.count % MemoryLayout<UInt32>.size == 0 else { return nil }
        return data.withUnsafeBytes { buf -> [Float] in
            buf.bindMemory(to: UInt32.self).map { Float(bitPattern: UInt32(littleEndian: $0)) }
        }
    }

    public static func cosine(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in a.indices { dot += Double(a[i] * b[i]); na += Double(a[i] * a[i]); nb += Double(b[i] * b[i]) }
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na.squareRoot() * nb.squareRoot())
    }

    public static func vector(for text: String, language: NLLanguage = .english) -> [Float]? {
        guard let emb = NLEmbedding.sentenceEmbedding(for: language),
              let vector = emb.vector(for: text) else { return nil }
        return vector.map(Float.init)
    }
}
