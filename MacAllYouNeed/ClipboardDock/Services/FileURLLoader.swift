import Core
import Foundation

actor FileURLLoader {
    private let xpc: any ClipboardXPCInteracting
    /// Optional in-process read path. The body of a file-kind record already
    /// contains the URLs encoded into the encrypted envelope, so when `clip`
    /// is injected we can return them without an XPC roundtrip — avoiding
    /// the silent-nil failure mode when the daemon's mach service isn't
    /// reachable.
    private let clip: ClipboardStore?
    private var cache: [String: [URL]] = [:]

    init(xpc: any ClipboardXPCInteracting, clip: ClipboardStore? = nil) {
        self.xpc = xpc
        self.clip = clip
    }

    func urls(recordID: String) async -> [URL]? {
        if let cached = cache[recordID] { return cached }

        if let local = await loadLocal(recordID: recordID) {
            cache[recordID] = local
            return local
        }

        guard let paths = await xpc.bodyFileURLs(forID: recordID) else { return nil }
        let urls = paths.map { URL(fileURLWithPath: $0) }
        cache[recordID] = urls
        return urls
    }

    private func loadLocal(recordID: String) async -> [URL]? {
        guard let clip, let rid = RecordID(rawValue: recordID) else { return nil }
        return await Task.detached {
            guard let body = try? clip.body(for: rid),
                  case let .files(urls) = body
            else { return nil }
            return urls
        }.value
    }
}
