import Foundation

public enum SmartTextRankBlend {
    public static func blend(lexicalScores: [String: Double], semanticScores: [String: Double], weight: Double) -> [String] {
        lexicalScores.keys.sorted { l, r in
            let sl = lexicalScores[l]! + weight * (semanticScores[l] ?? 0)
            let sr = lexicalScores[r]! + weight * (semanticScores[r] ?? 0)
            if sl == sr { return l < r }
            return sl > sr
        }
    }
}
