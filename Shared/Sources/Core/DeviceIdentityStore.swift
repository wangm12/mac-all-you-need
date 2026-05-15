import Foundation

public enum DeviceIdentityStore {
    public static func loadOrCreate(root: URL = AppGroup.containerURL()) throws -> DeviceID {
        try loadOrCreate(root: root, recoveryURL: recoveryURL(for: root), readTimeout: 0.75) { url in
            try String(contentsOf: url, encoding: .utf8)
        }
    }

    static func loadOrCreate(
        root: URL,
        recoveryURL: URL,
        readTimeout: TimeInterval,
        readString: @escaping @Sendable (URL) throws -> String
    ) throws -> DeviceID {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let primaryURL = root.appendingPathComponent("device-id.txt")

        if case let .found(id) = readID(at: recoveryURL, timeout: readTimeout, readString: readString) {
            return id
        }

        switch readID(at: primaryURL, timeout: readTimeout, readString: readString) {
        case let .found(id):
            return id
        case .unavailable:
            let id = DeviceID.generate()
            try id.rawValue.write(to: primaryURL, atomically: true, encoding: .utf8)
            return id
        case .timedOut:
            let id = DeviceID.generate()
            try? FileManager.default.createDirectory(
                at: recoveryURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? id.rawValue.write(to: recoveryURL, atomically: true, encoding: .utf8)
            return id
        }
    }

    private static func recoveryURL(for root: URL) -> URL {
        if root.path.contains("/Library/Group Containers/\(AppGroup.identifier)") {
            return applicationSupportDirectory()
                .appendingPathComponent("MacAllYouNeed", isDirectory: true)
                .appendingPathComponent("device-id-recovery.txt")
        }
        return root.appendingPathComponent("device-id-recovery.txt")
    }

    private static func applicationSupportDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    fileprivate enum ReadOutcome {
        case found(DeviceID)
        case unavailable
        case timedOut
    }

    private static func readID(
        at url: URL,
        timeout: TimeInterval,
        readString: @escaping @Sendable (URL) throws -> String
    ) -> ReadOutcome {
        let box = ReadOutcomeBox()
        let semaphore = DispatchSemaphore(value: 0)

        DispatchQueue.global(qos: .utility).async {
            let outcome: ReadOutcome
            do {
                let raw = try readString(url).trimmingCharacters(in: .whitespacesAndNewlines)
                if let id = DeviceID(rawValue: raw) {
                    outcome = .found(id)
                } else {
                    outcome = .unavailable
                }
            } catch {
                outcome = .unavailable
            }
            box.set(outcome)
            semaphore.signal()
        }

        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            return .timedOut
        }
        return box.get()
    }
}

private final class ReadOutcomeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var outcome: DeviceIdentityStore.ReadOutcome = .unavailable

    func set(_ outcome: DeviceIdentityStore.ReadOutcome) {
        lock.lock()
        self.outcome = outcome
        lock.unlock()
    }

    func get() -> DeviceIdentityStore.ReadOutcome {
        lock.lock()
        defer { lock.unlock() }
        return outcome
    }
}
