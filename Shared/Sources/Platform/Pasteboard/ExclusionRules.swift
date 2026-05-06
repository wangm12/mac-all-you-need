import Foundation

public struct ExclusionRules: Equatable, Sendable {
    public var blockedBundleIDs: Set<String>
    public var concealedUTIs: Set<String>

    public init(
        blockedBundleIDs: Set<String> = [],
        concealedUTIs: Set<String> = ["org.nspasteboard.ConcealedType"]
    ) {
        self.blockedBundleIDs = blockedBundleIDs
        self.concealedUTIs = concealedUTIs
    }

    public func shouldExclude(types: [String], appBundleID: String?) -> Bool {
        if !concealedUTIs.isDisjoint(with: types) { return true }
        if let id = appBundleID, blockedBundleIDs.contains(id) { return true }
        return false
    }
}
