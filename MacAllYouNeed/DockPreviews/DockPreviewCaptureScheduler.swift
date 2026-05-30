import Foundation

/// Caps concurrent thumbnail captures to `maxConcurrent` to avoid overwhelming the capture API.
actor DockPreviewCaptureScheduler {
    private let maxConcurrent: Int
    private var activeCount = 0
    private var queue: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int = 4) {
        self.maxConcurrent = maxConcurrent
    }

    func acquire() async {
        if activeCount < maxConcurrent {
            activeCount += 1
            return
        }
        await withCheckedContinuation { continuation in
            queue.append(continuation)
        }
    }

    func release() {
        if queue.isEmpty {
            activeCount -= 1
        } else {
            let next = queue.removeFirst()
            next.resume()
        }
    }
}
