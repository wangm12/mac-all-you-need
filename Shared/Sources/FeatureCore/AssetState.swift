import Foundation

public enum AssetState: Equatable, Sendable {
    case notRequired
    case notDownloaded
    case downloading(progress: Double)
    case downloadFailed(reason: String)
    case present(version: String)
}

extension AssetState: Codable {
    private enum CodingKeys: String, CodingKey { case kind, progress, reason, version }
    private enum Kind: String, Codable { case notRequired, notDownloaded, downloading, downloadFailed, present }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .notRequired: self = .notRequired
        case .notDownloaded: self = .notDownloaded
        case .downloading: self = .downloading(progress: try c.decode(Double.self, forKey: .progress))
        case .downloadFailed: self = .downloadFailed(reason: try c.decode(String.self, forKey: .reason))
        case .present: self = .present(version: try c.decode(String.self, forKey: .version))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .notRequired: try c.encode(Kind.notRequired, forKey: .kind)
        case .notDownloaded: try c.encode(Kind.notDownloaded, forKey: .kind)
        case .downloading(let p):
            try c.encode(Kind.downloading, forKey: .kind)
            try c.encode(p, forKey: .progress)
        case .downloadFailed(let r):
            try c.encode(Kind.downloadFailed, forKey: .kind)
            try c.encode(r, forKey: .reason)
        case .present(let v):
            try c.encode(Kind.present, forKey: .kind)
            try c.encode(v, forKey: .version)
        }
    }
}
