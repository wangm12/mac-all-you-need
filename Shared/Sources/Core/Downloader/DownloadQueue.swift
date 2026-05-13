import Foundation

private final class LineBuffer {
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
    private let log = Logging.logger(for: "downloader", category: "queue")

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
        Task { await self.tryStart() }
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
            completion(id, .failure(CocoaError(.userCancelled)))
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
        let lineBuffer = LineBuffer()
        NSLog("🚀 spawn: starting pid for url=\(job.url)")
        handle.readabilityHandler = { [progress, recordID = job.recordID] fh in
            let data = fh.availableData
            if data.isEmpty { return }
            for s in lineBuffer.append(data) {
                NSLog("📺 yt-dlp: \(s)")
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
                }
            }
        }
        job.process.terminationHandler = { [weak self, recordID = job.recordID] proc in
            NSLog("🏁 yt-dlp terminated: status=\(proc.terminationStatus)")
            handle.readabilityHandler = nil
            Task { await self?.completed(recordID: recordID, status: proc.terminationStatus) }
        }
        do {
            try job.process.run()
        } catch {
            NSLog("❌ spawn: process.run() threw: \(error)")
            Task { await self.completed(recordID: job.recordID, status: -1) }
        }
    }

    private func completed(recordID: RecordID, status: Int32) async {
        NSLog("🏁 completed: status=\(status) for recordID=\(recordID.rawValue.prefix(8))")
        running.removeValue(forKey: recordID)
        if pausedIDs.contains(recordID) {
            // Job was terminated for pause — don't fire failure completion
            pausedIDs.remove(recordID)
            await tryStart()
            return
        }
        if status == 0 {
            completion(recordID, .success(()))
        } else {
            completion(recordID, .failure(NSError(domain: "DownloadQueue", code: Int(status))))
        }
        await tryStart()
    }
}
