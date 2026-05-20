@testable import Core
import XCTest

final class DownloadQueueTests: XCTestCase {
    func testDownloadJobIncludesNoCheckCertificateForPyInstallerSSL() {
        let job = DownloadJob(
            recordID: RecordID.generate(), url: "https://example.com",
            destination: URL(fileURLWithPath: "/tmp/out"),
            ytdlp: URL(fileURLWithPath: "/bin/echo"),
            ffmpeg: URL(fileURLWithPath: "/bin/echo"),
            extraArgs: []
        )
        // PyInstaller-bundled Python can't find macOS system CA — --no-check-certificate is required
        XCTAssertTrue(job.process.arguments?.contains("--no-check-certificate") ?? false)
    }

    func testCancelQueuedJobCompletesWithoutStartingProcess() async {
        let cancelled = expectation(description: "cancelled")
        let id = RecordID.generate()
        let queue = DownloadQueue(
            maxConcurrent: 0,
            started: { _ in XCTFail("queued job must not start") },
            progress: { _, _ in },
            completion: { completedID, result in
                XCTAssertEqual(completedID, id)
                if case .success = result { XCTFail("expected failure") }
                cancelled.fulfill()
            }
        )
        let job = DownloadJob(
            recordID: id, url: "https://example.com",
            destination: URL(fileURLWithPath: "/tmp/out"),
            ytdlp: URL(fileURLWithPath: "/bin/echo"),
            ffmpeg: URL(fileURLWithPath: "/bin/echo"),
            extraArgs: []
        )
        await queue.enqueue(job)
        await queue.cancel(id)
        await fulfillment(of: [cancelled], timeout: 1)
    }

    func testFailedDownloadAttachesStderrToErrorUserInfo() async {
        let completed = expectation(description: "completed")
        let id = RecordID.generate()
        let queue = DownloadQueue(
            maxConcurrent: 1,
            started: { _ in },
            progress: { _, _ in },
            completion: { _, result in
                switch result {
                case .success:
                    XCTFail("expected failure")
                case .failure(let error):
                    let nsError = error as NSError
                    XCTAssertEqual(nsError.code, 1)
                    let msg = nsError.userInfo[NSLocalizedDescriptionKey] as? String
                    XCTAssertNotNil(msg, "stderr should be captured into userInfo")
                    XCTAssertTrue(
                        msg?.contains("ERROR: bilibili members only") ?? false,
                        "expected captured ERROR line, got: \(msg ?? "nil")"
                    )
                }
                completed.fulfill()
            }
        )
        let job = DownloadJob(
            recordID: id, url: "https://example.com",
            destination: URL(fileURLWithPath: "/tmp/out"),
            ytdlp: URL(fileURLWithPath: "/bin/echo"),
            ffmpeg: URL(fileURLWithPath: "/bin/echo"),
            extraArgs: []
        )
        job.process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Mimic the real yt-dlp failure shape: a `[download] N%` line that goes
        // through the progress parser, followed by an `ERROR:` line on stderr
        // and a non-zero exit. The ring buffer should retain the ERROR line.
        job.process.arguments = [
            "-c",
            "echo '[download] 12.0% of 5.00MiB at 1.00MiB/s ETA 0:04'; " +
                "echo 'ERROR: bilibili members only' 1>&2; " +
                "exit 1"
        ]
        await queue.enqueue(job)
        await fulfillment(of: [completed], timeout: 5)
    }

    func testStderrRingPrefersLatestErrorLine() {
        var ring = StderrRing(capacity: 5)
        ring.append("[download] Destination: /tmp/x.mp4")
        ring.append("WARNING: this is just a warning")
        ring.append("ERROR: first error")
        ring.append("something else")
        ring.append("ERROR: most recent error")
        XCTAssertEqual(ring.bestMessage(), "ERROR: most recent error")
    }

    func testStderrRingFallsBackToLastLinesWhenNoExplicitError() {
        var ring = StderrRing(capacity: 5)
        ring.append("first line")
        ring.append("")
        ring.append("second line")
        ring.append("third line")
        XCTAssertEqual(ring.bestMessage(), "first line | second line | third line")
    }

    func testStderrRingReturnsNilWhenEmpty() {
        let ring = StderrRing()
        XCTAssertNil(ring.bestMessage())
    }

    func testStderrRingObeysCapacity() {
        var ring = StderrRing(capacity: 3)
        for i in 0 ..< 10 { ring.append("line \(i)") }
        XCTAssertEqual(ring.lines, ["line 7", "line 8", "line 9"])
    }
}
