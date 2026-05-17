import CoreGraphics
import Foundation

public struct WindowIdentity: Hashable, Codable, Sendable {
    public let pid: pid_t
    public let cgWindowID: CGWindowID?
    public let titleHash: Int?
    public let frameFingerprint: Int?

    public init(pid: pid_t, cgWindowID: CGWindowID?, titleHash: Int?, frameFingerprint: Int? = nil) {
        self.pid = pid
        self.cgWindowID = cgWindowID
        self.titleHash = titleHash
        self.frameFingerprint = frameFingerprint
    }

    fileprivate var historyKey: WindowRestoreHistory.Key? {
        if let cgWindowID {
            return .cgWindowID(pid: pid, id: cgWindowID)
        }
        if let titleHash {
            return .titleHash(pid: pid, hash: titleHash)
        }
        return nil
    }
}

public final class WindowRestoreHistory {
    fileprivate enum Key: Hashable {
        case cgWindowID(pid: pid_t, id: CGWindowID)
        case titleHash(pid: pid_t, hash: Int)
    }

    private let capacity: Int
    private var framesByKey: [Key: CGRect] = [:]
    private var insertionOrder: [Key] = []

    public init(capacity: Int = 200) {
        self.capacity = max(0, capacity)
    }

    public var entryCount: Int {
        framesByKey.count
    }

    public func store(_ frame: CGRect, for identity: WindowIdentity) {
        guard capacity > 0, let key = identity.historyKey else {
            return
        }

        insertionOrder.removeAll { $0 == key }
        insertionOrder.append(key)
        framesByKey[key] = frame
        trimToCapacity()
    }

    public func restoreFrame(for identity: WindowIdentity) -> CGRect? {
        guard let key = identity.historyKey else {
            return nil
        }
        return framesByKey[key]
    }

    public func clear() {
        framesByKey.removeAll()
        insertionOrder.removeAll()
    }

    private func trimToCapacity() {
        while framesByKey.count > capacity, let oldest = insertionOrder.first {
            insertionOrder.removeFirst()
            framesByKey.removeValue(forKey: oldest)
        }
    }
}
