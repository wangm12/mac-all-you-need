import Foundation

public enum CodeLanguage: String, Codable, Equatable, Sendable {
    case swift, javascript, python, sql, html, c, shell, unknown
}

public enum DetectedType: Codable, Equatable, Sendable {
    case plain, email, url, phone, jwt, color
    case code(language: CodeLanguage)
}

public struct CalculationResult: Codable, Equatable, Sendable {
    public let expression: String
    public let value: String
    public init(expression: String, value: String) { self.expression = expression; self.value = value }
}

public struct LinkCleanResult: Codable, Equatable, Sendable {
    public let cleaned: String
    public let removedCount: Int
    public let original: String
    public init(cleaned: String, removedCount: Int, original: String) {
        self.cleaned = cleaned; self.removedCount = removedCount; self.original = original
    }
}

public struct Detection: Codable, Equatable, Sendable {
    public let type: DetectedType
    public let calculation: CalculationResult?
    public let linkClean: LinkCleanResult?
    public init(type: DetectedType, calculation: CalculationResult? = nil, linkClean: LinkCleanResult? = nil) {
        self.type = type; self.calculation = calculation; self.linkClean = linkClean
    }
    public func encodedJSON() throws -> String { String(decoding: try JSONEncoder().encode(self), as: UTF8.self) }
    public static func decode(json: String) throws -> Detection { try JSONDecoder().decode(Detection.self, from: Data(json.utf8)) }
}
