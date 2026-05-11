import Foundation

public struct ExclusionRules: Equatable, Sendable {
    public var blockedBundleIDs: Set<String>
    public var concealedUTIs: Set<String>
    public var transientUTIs: Set<String>
    public var regexBlocklist: RegexBlocklist

    public init(
        blockedBundleIDs: Set<String> = [],
        concealedUTIs: Set<String> = ["org.nspasteboard.ConcealedType"],
        transientUTIs: Set<String> = ["org.nspasteboard.TransientType"],
        regexBlocklist: RegexBlocklist = RegexBlocklist(patterns: [])
    ) {
        self.blockedBundleIDs = blockedBundleIDs
        self.concealedUTIs = concealedUTIs
        self.transientUTIs = transientUTIs
        self.regexBlocklist = regexBlocklist
    }

    public func shouldExclude(types: [String], appBundleID: String?) -> Bool {
        if !concealedUTIs.isDisjoint(with: types) { return true }
        if !transientUTIs.isDisjoint(with: types) { return true }
        if let id = appBundleID, blockedBundleIDs.contains(id) { return true }
        return false
    }

    public func shouldExcludeText(_ text: String) -> Bool {
        regexBlocklist.matches(text)
    }

    public static func == (lhs: ExclusionRules, rhs: ExclusionRules) -> Bool {
        lhs.blockedBundleIDs == rhs.blockedBundleIDs &&
            lhs.concealedUTIs == rhs.concealedUTIs &&
            lhs.transientUTIs == rhs.transientUTIs
    }
}
