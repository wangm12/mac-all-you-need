import XCTest
@testable import Core

final class OrganizerLLMServiceTests: XCTestCase {
    func testFakeLLMReturnsConfiguredResponse() async throws {
        let fake = FakeOrganizerLLMService(responses: [.init(suggestedName: "Invoice 2026")])
        let req = OrganizerLLMRequest(contentSnippet: "...", originalFilename: "IMG_001.jpg", contentKind: .image)
        let resp = try await fake.suggest(for: req)
        XCTAssertEqual(resp.suggestedName, "Invoice 2026")
    }
    func testFakeLLMThrowsOnConfiguredIndex() async {
        let fake = FakeOrganizerLLMService(responses: [.init(suggestedName: "ok")])
        fake.throwOnIndex = 0
        let req = OrganizerLLMRequest(contentSnippet: "...", originalFilename: "a.txt", contentKind: .text)
        do {
            _ = try await fake.suggest(for: req)
            XCTFail("Should have thrown")
        } catch {}
    }
}
