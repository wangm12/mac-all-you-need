import Foundation

public enum WindowRuleAction: String, Codable, Sendable, CaseIterable {
    case ignore
    case forceFloating
    case defaultSnap

    public var title: String {
        switch self {
        case .ignore: "Ignore"
        case .forceFloating: "Force floating"
        case .defaultSnap: "Allow snap"
        }
    }
}

public struct WindowRule: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var bundleID: String?
    public var titlePattern: String?
    public var action: WindowRuleAction

    public init(
        id: UUID = UUID(),
        bundleID: String? = nil,
        titlePattern: String? = nil,
        action: WindowRuleAction = .ignore
    ) {
        self.id = id
        self.bundleID = bundleID
        self.titlePattern = titlePattern
        self.action = action
    }

    public func matches(bundleID: String?, title: String?) -> Bool {
        if let ruleBundle = self.bundleID?.trimmingCharacters(in: .whitespacesAndNewlines), !ruleBundle.isEmpty {
            guard bundleID?.caseInsensitiveCompare(ruleBundle) == .orderedSame else { return false }
        }
        if let pattern = titlePattern?.trimmingCharacters(in: .whitespacesAndNewlines), !pattern.isEmpty {
            guard let title else { return false }
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(title.startIndex..., in: title)
                guard regex.firstMatch(in: title, range: range) != nil else { return false }
            } else if !title.localizedCaseInsensitiveContains(pattern) {
                return false
            }
        }
        let hasBundle = self.bundleID != nil && !(self.bundleID?.isEmpty ?? true)
        let hasPattern = titlePattern != nil && !(titlePattern?.isEmpty ?? true)
        return hasBundle || hasPattern
    }
}

public struct WindowRulesEngine: Sendable {
    public var rules: [WindowRule]

    public init(rules: [WindowRule] = []) {
        self.rules = rules
    }

    public func resolvedAction(bundleID: String?, title: String?) -> WindowRuleAction? {
        for rule in rules where rule.matches(bundleID: bundleID, title: title) {
            return rule.action
        }
        return nil
    }

    public func shouldIgnore(bundleID: String?, title: String?) -> Bool {
        resolvedAction(bundleID: bundleID, title: title) == .ignore
    }

    public func allowsWindowControl(bundleID: String?, title: String?) -> Bool {
        !shouldIgnore(bundleID: bundleID, title: title)
    }

    public func allowsSnapping(bundleID: String?, title: String?) -> Bool {
        guard allowsWindowControl(bundleID: bundleID, title: title) else { return false }
        switch resolvedAction(bundleID: bundleID, title: title) {
        case .forceFloating, .ignore:
            return false
        case .defaultSnap, nil:
            return true
        }
    }
}
