import Core
import Foundation

actor FileURLLoader {
    private let xpc: any ClipboardXPCInteracting
    private var cache: [String: [URL]] = [:]

    init(xpc: any ClipboardXPCInteracting) {
        self.xpc = xpc
    }

    func urls(recordID: String) async -> [URL]? {
        if let cached = cache[recordID] { return cached }
        guard let paths = await xpc.bodyFileURLs(forID: recordID) else { return nil }
        let urls = paths.map { URL(fileURLWithPath: $0) }
        cache[recordID] = urls
        return urls
    }
}
