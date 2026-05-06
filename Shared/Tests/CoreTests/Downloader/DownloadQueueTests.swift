@testable import Core
import XCTest

final class DownloadQueueTests: XCTestCase {
    func testDownloadJobKeepsTLSVerificationEnabled() {
        let job = DownloadJob(
            recordID: RecordID.generate(), url: "https://example.com",
            destination: URL(fileURLWithPath: "/tmp/out"),
            ytdlp: URL(fileURLWithPath: "/bin/echo"),
            ffmpeg: URL(fileURLWithPath: "/bin/echo"),
            extraArgs: []
        )

        XCTAssertFalse(job.process.arguments?.contains("--no-check-certificate") ?? false)
        XCTAssertEqual(job.process.environment?["SSL_CERT_FILE"], "/etc/ssl/cert.pem")
        XCTAssertEqual(job.process.environment?["REQUESTS_CA_BUNDLE"], "/etc/ssl/cert.pem")
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
}
