import XCTest
@testable import PackPipeline

final class CodesignVerifierTests: XCTestCase {
    func testValidatesAppleSignedBinary() throws {
        let lsURL = URL(fileURLWithPath: "/bin/ls")
        // Apple's anchor is universally accepted. Designated requirement that any Apple binary satisfies:
        let req = "anchor apple"
        try CodesignVerifier.verify(fileAt: lsURL, requirement: req)
    }

    func testRejectsBinaryNotMatchingRequirement() throws {
        let lsURL = URL(fileURLWithPath: "/bin/ls")
        // A requirement that intentionally won't match (impossible team ID)
        let req = "anchor apple generic and certificate leaf [subject.OU] = \"NOT_A_REAL_TEAM_ZZZZ\""
        XCTAssertThrowsError(try CodesignVerifier.verify(fileAt: lsURL, requirement: req)) { err in
            guard case PackPipelineError.codesignFailed = err else {
                return XCTFail("expected codesignFailed, got \(err)")
            }
        }
    }

    func testRejectsMissingFile() {
        let url = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID())")
        XCTAssertThrowsError(try CodesignVerifier.verify(fileAt: url, requirement: "anchor apple")) { err in
            guard case PackPipelineError.codesignFailed = err else {
                return XCTFail("expected codesignFailed, got \(err)")
            }
        }
    }
}
