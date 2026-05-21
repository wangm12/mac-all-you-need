/// DownloadQueueAsyncParityTests — verifies that `enqueueAndWait` and the
/// existing callback path produce identical observable side effects for
/// success, failure, and queued-cancel scenarios.
@testable import Core
import XCTest

// MARK: - Helpers

/// Returns a DownloadJob whose process immediately exits with `exitCode`.
/// Uses `/bin/sh -c "exit N"` so no real download happens.
private func scriptedJob(
    id: RecordID = .generate(),
    exitCode: Int,
    stderrMessage: String? = nil
) -> DownloadJob {
    let job = DownloadJob(
        recordID: id,
        url: "https://example.com/parity-test",
        destination: URL(fileURLWithPath: "/tmp/parity-out"),
        ytdlp: URL(fileURLWithPath: "/bin/sh"),
        ffmpeg: URL(fileURLWithPath: "/bin/echo"),
        extraArgs: []
    )
    job.process.executableURL = URL(fileURLWithPath: "/bin/sh")
    var cmd = ""
    if let msg = stderrMessage {
        cmd += "echo 'ERROR: \(msg)' 1>&2; "
    }
    cmd += "exit \(exitCode)"
    job.process.arguments = ["-c", cmd]
    return job
}

// MARK: - Parity tests

final class DownloadQueueAsyncParityTests: XCTestCase {

    // MARK: Success parity

    func testSuccessCallbackPath() async {
        let id = RecordID.generate()
        let job = scriptedJob(id: id, exitCode: 0)

        let startedExp = expectation(description: "started")
        let completedExp = expectation(description: "completed")
        var startedID: RecordID?
        var completionResult: Result<Void, Error>?

        let queue = DownloadQueue(
            maxConcurrent: 1,
            started: { sid in startedID = sid; startedExp.fulfill() },
            progress: { _, _ in },
            completion: { _, result in completionResult = result; completedExp.fulfill() }
        )

        await queue.enqueue(job)
        await fulfillment(of: [startedExp, completedExp], timeout: 5)

        XCTAssertEqual(startedID, id)
        guard case .success = completionResult else {
            return XCTFail("callback path: expected success, got \(String(describing: completionResult))")
        }
    }

    func testSuccessAsyncPath() async throws {
        let id = RecordID.generate()
        let job = scriptedJob(id: id, exitCode: 0)

        let startedExp = expectation(description: "started")
        var startedID: RecordID?
        var callbackResult: Result<Void, Error>?

        let queue = DownloadQueue(
            maxConcurrent: 1,
            started: { sid in startedID = sid; startedExp.fulfill() },
            progress: { _, _ in },
            completion: { _, result in callbackResult = result }
        )

        // enqueueAndWait returns on success
        try await queue.enqueueAndWait(job)
        await fulfillment(of: [startedExp], timeout: 1)

        XCTAssertEqual(startedID, id)
        // The global callback was also fired
        guard case .success = callbackResult else {
            return XCTFail("async path: global callback must also succeed, got \(String(describing: callbackResult))")
        }
    }

    // MARK: Failure parity

    func testFailureCallbackPath() async {
        let id = RecordID.generate()
        let job = scriptedJob(id: id, exitCode: 1, stderrMessage: "parity error")

        let completedExp = expectation(description: "completed")
        var completionResult: Result<Void, Error>?

        let queue = DownloadQueue(
            maxConcurrent: 1,
            started: { _ in },
            progress: { _, _ in },
            completion: { _, result in completionResult = result; completedExp.fulfill() }
        )

        await queue.enqueue(job)
        await fulfillment(of: [completedExp], timeout: 5)

        guard case .failure(let err) = completionResult else {
            return XCTFail("callback path: expected failure")
        }
        let nsErr = err as NSError
        XCTAssertEqual(nsErr.domain, "DownloadQueue")
        XCTAssertEqual(nsErr.code, 1)
        XCTAssertTrue(
            (nsErr.userInfo[NSLocalizedDescriptionKey] as? String)?.contains("parity error") ?? false,
            "stderr message must be forwarded"
        )
    }

    func testFailureAsyncPath() async {
        let id = RecordID.generate()
        let job = scriptedJob(id: id, exitCode: 1, stderrMessage: "parity error")

        var callbackResult: Result<Void, Error>?

        let queue = DownloadQueue(
            maxConcurrent: 1,
            started: { _ in },
            progress: { _, _ in },
            completion: { _, result in callbackResult = result }
        )

        do {
            try await queue.enqueueAndWait(job)
            XCTFail("async path: expected throw on failure")
        } catch {
            let nsErr = error as NSError
            XCTAssertEqual(nsErr.domain, "DownloadQueue")
            XCTAssertEqual(nsErr.code, 1)
            XCTAssertTrue(
                (nsErr.userInfo[NSLocalizedDescriptionKey] as? String)?.contains("parity error") ?? false,
                "async throw must carry same error as callback"
            )
        }

        // Global callback was also fired with the same result
        guard case .failure(let cbErr) = callbackResult else {
            return XCTFail("async path: global callback must also fire with failure")
        }
        XCTAssertEqual((cbErr as NSError).code, 1)
    }

    // MARK: Queued-cancel parity

    func testCancelQueuedCallbackPath() async {
        let id = RecordID.generate()
        // maxConcurrent: 0 keeps the job in the queue so cancel can hit it.
        let job = scriptedJob(id: id, exitCode: 0)

        let completedExp = expectation(description: "cancelled")
        var completionResult: Result<Void, Error>?

        let queue = DownloadQueue(
            maxConcurrent: 0,
            started: { _ in XCTFail("must not start") },
            progress: { _, _ in },
            completion: { _, result in completionResult = result; completedExp.fulfill() }
        )

        await queue.enqueue(job)
        await queue.cancel(id)
        await fulfillment(of: [completedExp], timeout: 1)

        guard case .failure = completionResult else {
            return XCTFail("callback path: queued cancel must produce failure")
        }
    }

    func testCancelQueuedAsyncPath() async {
        let id = RecordID.generate()
        let job = scriptedJob(id: id, exitCode: 0)

        var callbackResult: Result<Void, Error>?

        let queue = DownloadQueue(
            maxConcurrent: 0,
            started: { _ in XCTFail("must not start") },
            progress: { _, _ in },
            completion: { _, result in callbackResult = result }
        )

        // Kick off the async wait in a child Task so we can cancel concurrently.
        let waitTask = Task { try await queue.enqueueAndWait(job) }

        // Give the enqueueAndWait time to register the continuation, then cancel.
        try? await Task.sleep(nanoseconds: 10_000_000) // 10 ms
        await queue.cancel(id)

        do {
            try await waitTask.value
            XCTFail("async path: expected throw after cancel")
        } catch {
            // Any error is acceptable — CocoaError.userCancelled or NSError
            // as long as it throws rather than succeeds.
            _ = error
        }

        // Global callback was also fired
        guard case .failure = callbackResult else {
            return XCTFail("async path: global callback must fire with failure after cancel")
        }
    }
}
