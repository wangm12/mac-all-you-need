import Foundation

/// SQL-friendly structured clipboard history filters (app, type, date).
/// Free-text and regex still use FTS or in-memory matching after load.
public struct ClipboardHistoryStructuredFilter: Sendable, Equatable {
    public var appIncludes: [String]
    public var appExcludes: [String]
    public var typeFilters: [String]
    public var modifiedOnOrAfter: Date?

    public init(
        appIncludes: [String] = [],
        appExcludes: [String] = [],
        typeFilters: [String] = [],
        modifiedOnOrAfter: Date? = nil
    ) {
        self.appIncludes = appIncludes
        self.appExcludes = appExcludes
        self.typeFilters = typeFilters
        self.modifiedOnOrAfter = modifiedOnOrAfter
    }

    public var hasStructuredConstraints: Bool {
        !appIncludes.isEmpty || !appExcludes.isEmpty || !typeFilters.isEmpty
            || modifiedOnOrAfter != nil
    }

    public func matches(_ meta: ClipboardItemMeta) -> Bool {
        let appID = (meta.sourceAppBundleID ?? "").lowercased()
        if !appIncludes.isEmpty {
            guard appIncludes.contains(where: { appID.contains($0.lowercased()) }) else { return false }
        }
        if !appExcludes.isEmpty {
            if appExcludes.contains(where: { appID.contains($0.lowercased()) }) { return false }
        }
        if !typeFilters.isEmpty {
            let type = Self.detectedTypeName(meta) ?? "plain"
            guard typeFilters.contains(type) else { return false }
        }
        if let lower = modifiedOnOrAfter, meta.modified < lower { return false }
        return true
    }

    private static func detectedTypeName(_ meta: ClipboardItemMeta) -> String? {
        guard let json = meta.detectedTypeJSON,
              let detection = try? Detection.decode(json: json) else { return nil }
        switch detection.type {
        case .plain: return "plain"
        case .email: return "email"
        case .url: return "url"
        case .phone: return "phone"
        case .jwt: return "jwt"
        case .color: return "color"
        case .code: return "code"
        }
    }
}
