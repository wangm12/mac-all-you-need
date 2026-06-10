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

    public func enqueue(_ job: DownloadJob) {
        queued.append(job)
        sortQueuedJobs()
        Task { await self.tryStart() }
    }

    private func sortQueuedJobs() {
        queued.sort { lhs, rhs in
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
            enqueue(job)
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

    public func setMaxConcurrent(_ n: Int) {
        slots = n
        Task { await tryStart() }
    }

    private func tryStart() async {
        while running.count < slots, let job = queued.first {
            queued.removeFirst()
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
                progress(recordID, p)
            } else if let dest = ProgressParser.extractDestination(line: s) {
                NotificationCenter.default.post(
                    name: Notification.Name("downloadDestinationPath"), object: nil,
                    userInfo: ["id": recordID.rawValue, "path": dest]
                )
                NotificationCenter.default.post(
                    name: Notification.Name("downloadPhase"), object: nil,
                    userInfo: ["id": recordID.rawValue, "phase": "Downloading..."]
                )
            } else if let phase = ProgressParser.detectPhase(line: s) {
                NotificationCenter.default.post(
                    name: Notification.Name("downloadPhase"), object: nil,
                    userInfo: ["id": recordID.rawValue, "phase": phase]
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
                Task { await self?.completed(recordID: recordID, status: proc.terminationStatus, unmatched: snapshot) }
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
        running.removeValue(forKey: recordID)
        if pausedIDs.contains(recordID) {
            // Job was terminated for pause — don't fire failure completion
            pausedIDs.remove(recordID)
            asyncContinuations.removeValue(forKey: recordID)?
                .resume(throwing: CocoaError(.userCancelled))
            await tryStart()
            return
        }
        if status == 0 {
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
}
