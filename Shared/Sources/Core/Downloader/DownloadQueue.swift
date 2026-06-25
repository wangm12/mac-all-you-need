import Foundation

private final class LineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffered = ""

    func append(_ data: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }

        buffered += String(data: data, encoding: .utf8) ?? ""
        let parts = buffered.split(separator: "\n", omittingEmptySubsequences: false)
        buffered = parts.last.map(String.init) ?? ""
        return parts.dropLast().map(String.init)
    }

    /// Return whatever is still buffered without a trailing newline.
    /// Called once when the producer process exits so the final partial line
    /// is not lost.
    func flushResidual() -> String? {
        lock.lock(); defer { lock.unlock() }
        guard !buffered.isEmpty else { return nil }
        let s = buffered
        buffered = ""
        return s
    }
}

/// Thread-safe accumulator for yt-dlp output lines that don't match a known
/// progress/destination/phase pattern. Populated synchronously from the
/// read loop and snapshotted from the actor when the process exits, so the
/// failure completion always sees a fully-drained ring.
private final class UnmatchedLineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func append(_ line: String) { lock.lock(); lines.append(line); lock.unlock() }
    func snapshot() -> [String] { lock.lock(); defer { lock.unlock() }; return lines }
}

private final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var lastNotify: [RecordID: Date] = [:]
    private var lastFraction: [RecordID: Double] = [:]

    func shouldNotify(recordID: RecordID, progress: DownloadProgress, interval: TimeInterval) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        let previousNotify = lastNotify[recordID] ?? .distantPast
        let previousFraction = lastFraction[recordID] ?? -1
        let fraction = progress.fraction
        let isTerminalLike = fraction >= 0.999 || (progress.downloadedBytes != nil && progress.totalBytes != nil)
        if isTerminalLike || now.timeIntervalSince(previousNotify) >= interval || abs(fraction - previousFraction) >= 0.05 {
            lastNotify[recordID] = now
            lastFraction[recordID] = fraction
            return true
        }
        return false
    }

    func clear(recordID: RecordID) {
        lock.lock()
        defer { lock.unlock() }
        lastNotify.removeValue(forKey: recordID)
        lastFraction.removeValue(forKey: recordID)
    }
}

/// Retains the last N non-progress lines from yt-dlp so a failed job can surface
/// its actual error instead of a bare non-zero exit code.
struct StderrRing {
    private(set) var lines: [String] = []
    private let capacity: Int

    init(capacity: Int = 30) { self.capacity = capacity }

    mutating func append(_ line: String) {
        lines.append(line)
        if lines.count > capacity { lines.removeFirst(lines.count - capacity) }
    }

    /// Pick the most informative line for the UI. yt-dlp prefixes fatal errors
    /// with `ERROR:`, so prefer the latest one; else fall back to the last few
    /// non-empty lines joined.
    func bestMessage() -> String? {
        let cleaned = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return nil }
        if let err = cleaned.reversed().first(where: {
            $0.contains("ERROR:") || $0.lowercased().hasPrefix("error")
        }) {
            return err
        }
        return cleaned.suffix(3).joined(separator: " | ")
    }
}

public actor DownloadQueue {
    public typealias StartHandler = (RecordID) -> Void
    public typealias ProgressHandler = (RecordID, DownloadProgress) -> Void
    public typealias CompletionHandler = (RecordID, Result<Void, Error>) -> Void

    private var slots: Int
    private var queued: [DownloadJob] = []
    private var running: [RecordID: DownloadJob] = [:]
    private var pausedIDs: Set<RecordID> = [] // jobs cancelled for pause, not failure
    private let started: StartHandler
    private let progress: ProgressHandler
    private let completion: CompletionHandler
    private var asyncContinuations: [RecordID: CheckedContinuation<Void, Error>] = [:]
    private let progressThrottle = ProgressThrottle()
    private static let progressNotifyInterval: TimeInterval = 0.25
    private var startTask: Task<Void, Never>?

    public init(
        maxConcurrent: Int,
        started: @escaping StartHandler,
        progress: @escaping ProgressHandler,
        completion: @escaping CompletionHandler
    ) {
        slots = maxConcurrent
        self.started = started
        self.progress = progress
        self.completion = completion
    }

    public func enqueue(_ job: DownloadJob) async {
        // Keep only the latest pending job per record so resume retries do not
        // pile up duplicate queue entries.
        queued.removeAll { $0.recordID == job.recordID }
        queued.append(job)
        queued.sort(by: Self.compareJobs)
        scheduleStart()
    }

    public func enqueueBatch(_ jobs: [DownloadJob]) async {
        guard !jobs.isEmpty else { return }
        var seenIDs: Set<RecordID> = []
        let uniqueJobs = jobs.filter { seenIDs.insert($0.recordID).inserted }
        let incomingIDs = Set(uniqueJobs.map(\.recordID))
        queued.removeAll { incomingIDs.contains($0.recordID) }

        let sortedIncoming = uniqueJobs.sorted(by: Self.compareJobs)
        queued = mergeSortedJobs(existing: queued, incoming: sortedIncoming)
        if queued.count >= 64 {
            await Task.yield()
        }
        scheduleStart()
    }

    private static func compareJobs(_ lhs: DownloadJob, _ rhs: DownloadJob) -> Bool {
        if let leftCollection = lhs.collectionID, let rightCollection = rhs.collectionID,
           leftCollection == rightCollection
        {
            let leftIndex = lhs.collectionIndex ?? Int.max
            let rightIndex = rhs.collectionIndex ?? Int.max
            if leftIndex != rightIndex { return leftIndex < rightIndex }
        }
        if lhs.enqueuedAt != rhs.enqueuedAt {
            return lhs.enqueuedAt < rhs.enqueuedAt
        }
        return lhs.recordID.rawValue < rhs.recordID.rawValue
    }

    private func mergeSortedJobs(existing: [DownloadJob], incoming: [DownloadJob]) -> [DownloadJob] {
        guard !existing.isEmpty else { return incoming }
        guard !incoming.isEmpty else { return existing }

        var merged: [DownloadJob] = []
        merged.reserveCapacity(existing.count + incoming.count)
        var left = 0
        var right = 0

        while left < existing.count, right < incoming.count {
            if Self.compareJobs(incoming[right], existing[left]) {
                merged.append(incoming[right])
                right += 1
            } else {
                merged.append(existing[left])
                left += 1
            }
        }
        if left < existing.count {
            merged.append(contentsOf: existing[left...])
        }
        if right < incoming.count {
            merged.append(contentsOf: incoming[right...])
        }
        return merged
    }

    /// Async/await overload. Suspends until the job finishes (success) or fails
    /// (throws). The callback-based `started`, `progress`, and `completion`
    /// handlers registered at init are still invoked as normal — both APIs are
    /// fully active for the same job.
    ///
    /// Named distinctly from `enqueue(_:)` to avoid ambiguity at call sites that
    /// already use `await queue.enqueue(job)` without `try`.
    public func enqueueAndWait(_ job: DownloadJob) async throws {
        try await withCheckedThrowingContinuation { continuation in
            if let prior = asyncContinuations[job.recordID] {
                prior.resume(throwing: CocoaError(.userCancelled))
            }
            asyncContinuations[job.recordID] = continuation
            Task { await self.enqueue(job) }
        }
    }

    public func pause(_ id: RecordID) {
        running[id]?.pause()
    }

    public func resume(_ id: RecordID) {
        running[id]?.resume()
    }

    /// Cancel the job but suppress the failure completion (job is being paused, not failed).
    public func pauseForResume(_ id: RecordID) {
        if let job = running[id] {
            pausedIDs.insert(id)
            job.cancel()
        } else if let idx = queued.firstIndex(where: { $0.recordID == id }) {
            queued.remove(at: idx)
            pausedIDs.insert(id)
        }
    }

    public func cancel(_ id: RecordID) {
        if let job = running[id] {
            job.cancel()
        } else if let idx = queued.firstIndex(where: { $0.recordID == id }) {
            queued.remove(at: idx)
            let error = CocoaError(.userCancelled)
            completion(id, .failure(error))
            asyncContinuations.removeValue(forKey: id)?.resume(throwing: error)
        }
    }

    public func cancelMany(_ ids: [RecordID]) {
        guard !ids.isEmpty else { return }
        let idSet = Set(ids)
        for id in idSet {
            if let job = running[id] {
                job.cancel()
            }
        }
        queued.removeAll { idSet.contains($0.recordID) }
    }

    public func setMaxConcurrent(_ n: Int) {
        slots = n
        scheduleStart()
    }

    private func scheduleStart() {
        guard startTask == nil else { return }
        startTask = Task { [weak self] in
            guard let self else { return }
            await self.tryStart()
            await self.finishScheduledStart()
        }
    }

    private func finishScheduledStart() {
        startTask = nil
        if !queued.isEmpty, running.count < slots {
            scheduleStart()
        }
    }

    private func tryStart() async {
        while running.count < slots {
            guard let nextIndex = queued.firstIndex(where: { running[$0.recordID] == nil }) else {
                break
            }
            let job = queued.remove(at: nextIndex)
            running[job.recordID] = job
            started(job.recordID)
            spawn(job: job)
        }
    }

    private func spawn(job: DownloadJob) {
        let handle = job.pipe.fileHandleForReading
        let writeHandle = job.pipe.fileHandleForWriting
        let lineBuffer = LineBuffer()
        let unmatched = UnmatchedLineCollector()
        let recordID = job.recordID
        let progress = progress
        // Serial read queue, owned per job. The read loop drains the pipe
        // synchronously until EOF, then the termination snapshot is enqueued
        // behind it so it observes every line. Using `readabilityHandler` for
        // this races at end-of-process: events queued before we set the
        // handler to nil can still fire AFTER our drain, leaking lines.
        let readQueue = DispatchQueue(label: "com.maycoin.downloader.read.\(recordID.rawValue)")
        @Sendable func route(_ s: String) {
            if let p = ProgressParser.parse(line: s) {
                if progressThrottle.shouldNotify(recordID: recordID, progress: p, interval: Self.progressNotifyInterval) {
                    progress(recordID, p)
                }
            } else if let dest = ProgressParser.extractDestination(line: s) {
                Self.postDestinationPath(recordID: recordID, path: dest)
                let phaseNotification = Notification(
                    name: Notification.Name("downloadPhase"),
                    object: nil,
                    userInfo: ["id": recordID.rawValue, "phase": "Downloading..."]
                )
                NotificationCenter.default.post(phaseNotification)
                DistributedNotificationCenter.default().postNotificationName(
                    phaseNotification.name,
                    object: nil,
                    userInfo: phaseNotification.userInfo
                )
            } else if let phase = ProgressParser.detectPhase(line: s) {
                let notification = Notification(
                    name: Notification.Name("downloadPhase"),
                    object: nil,
                    userInfo: ["id": recordID.rawValue, "phase": phase]
                )
                NotificationCenter.default.post(notification)
                DistributedNotificationCenter.default().postNotificationName(
                    notification.name,
                    object: nil,
                    userInfo: notification.userInfo
                )
            } else {
                // Preserve everything else (especially `ERROR: ...` lines from
                // yt-dlp) so the failure completion can surface a real reason.
                unmatched.append(s)
            }
        }
        job.process.terminationHandler = { [weak self] proc in
            // Enqueue the snapshot behind any in-flight read iterations. The
            // serial queue guarantees the loop has finished draining first.
            readQueue.async {
                let snapshot = unmatched.snapshot()
                guard let self else { return }
                let actor = self
                Task { await actor.completed(recordID: recordID, status: proc.terminationStatus, unmatched: snapshot) }
            }
        }
        do {
            try job.process.run()
            // Close the parent-side write end now that the child holds its own
            // copy; without this, `availableData` never sees EOF.
            try? writeHandle.close()
        } catch {
            try? writeHandle.close()
            Task { await self.completed(recordID: job.recordID, status: -1, unmatched: []) }
            return
        }
        readQueue.async {
            while true {
                let data = handle.availableData
                if data.isEmpty { break } // EOF
                for s in lineBuffer.append(data) { route(s) }
            }
            if let tail = lineBuffer.flushResidual() { route(tail) }
        }
    }

    private func completed(recordID: RecordID, status: Int32, unmatched: [String]) async {
        let completedJob = running[recordID]
        running.removeValue(forKey: recordID)
        progressThrottle.clear(recordID: recordID)
        if pausedIDs.contains(recordID) {
            // Job was terminated for pause — don't fire failure completion
            pausedIDs.remove(recordID)
            asyncContinuations.removeValue(forKey: recordID)?
                .resume(throwing: CocoaError(.userCancelled))
            await tryStart()
            return
        }
        if status == 0 {
            if let path = completedJob?.destination.path,
               DownloadDiskCleanup.isConcretePath(path)
            {
                Self.postDestinationPath(recordID: recordID, path: path)
            }
            completion(recordID, .success(()))
            asyncContinuations.removeValue(forKey: recordID)?.resume(returning: ())
        } else {
            var ring = StderrRing()
            for line in unmatched { ring.append(line) }
            var userInfo: [String: Any] = [:]
            if let msg = ring.bestMessage(), !msg.isEmpty {
                userInfo[NSLocalizedDescriptionKey] = msg
            }
            let error = NSError(domain: "DownloadQueue", code: Int(status), userInfo: userInfo)
            completion(recordID, .failure(error))
            asyncContinuations.removeValue(forKey: recordID)?.resume(throwing: error)
        }
        await tryStart()
    }

    private static func postDestinationPath(recordID: RecordID, path: String) {
        let destinationNotification = Notification(
            name: Notification.Name("downloadDestinationPath"),
            object: nil,
            userInfo: ["id": recordID.rawValue, "path": path]
        )
        NotificationCenter.default.post(destinationNotification)
        DistributedNotificationCenter.default().postNotificationName(
            destinationNotification.name,
            object: nil,
            userInfo: destinationNotification.userInfo
        )
    }
}
