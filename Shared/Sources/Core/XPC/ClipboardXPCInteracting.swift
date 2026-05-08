import Foundation

public protocol ClipboardXPCInteracting: Sendable {
    func listItems(query: String?, pageToken: String?, limit: Int) async -> ClipboardXPCList
    func metasByIDs(ids: [String]) async -> ClipboardXPCList
    func bodyText(forID id: String) async -> String?
    func bodyFileURLs(forID id: String) async -> [String]?
    func paste(itemID: String, plainText: Bool) async -> String
    func pasteMany(itemIDs: [String], delimiter: String, plainText: Bool) async -> String
    func pasteText(text: String, plainText: Bool, saveAsNew: Bool) async -> String
    func transformAndCopy(itemID: String, transform: String, saveAsNew: Bool) async -> String?
    func imageThumbnail(forID id: String, maxDim: Int) async -> Data?
    func listSnippets() async -> [SnippetXPCDTO]
    func deleteItem(id: String) async -> Bool
    func runRetention(maxAgeDays: Int) async -> Bool
}

public extension ClipboardXPCInteracting {
    func deleteItem(id: String) async -> Bool {
        false
    }

    /// Default no-op implementation so test mocks don't need to add a stub.
    /// Real client overrides this.
    func runRetention(maxAgeDays: Int) async -> Bool {
        false
    }
}
