import Foundation

public actor DownloadQueue {
    public typealias StartHandler = (RecordID) -> Void
    public typealias ProgressHandler = (RecordID, DownloadProgress) -> Void
    public typealias CompletionHandler = (RecordID, Result<Void, Error>) -> Void

    private var slots: Int
    private var queued: [DownloadJob] = []
    private var running: [RecordID: DownloadJob] = [:]
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
        var buffered = ""
        handle.readabilityHandler = { [progress, recordID = job.recordID] fh in
            let data = fh.availableData
            if data.isEmpty { return }
            buffered += String(data: data, encoding: .utf8) ?? ""
            let parts = buffered.split(separator: "\n", omittingEmptySubsequences: false)
            buffered = parts.last.map(String.init) ?? ""
            for line in parts.dropLast() {
                if let p = ProgressParser.parse(line: String(line)) {
                    progress(recordID, p)
                }
            }
        }
        job.process.terminationHandler = { [weak self, recordID = job.recordID] proc in
            handle.readabilityHandler = nil
            Task { await self?.completed(recordID: recordID, status: proc.terminationStatus) }
        }
        do {
            try job.process.run()
        } catch {
            Task { await self.completed(recordID: job.recordID, status: -1) }
        }
    }

    private func completed(recordID: RecordID, status: Int32) async {
        running.removeValue(forKey: recordID)
        if status == 0 {
            completion(recordID, .success(()))
        } else {
            completion(recordID, .failure(NSError(domain: "DownloadQueue", code: Int(status))))
        }
        await tryStart()
    }
}
