import XCTest
@testable import Core

final class OrganizerEngineTests: XCTestCase {
    func testEngineProposesRenamedFiles() async throws {
        let fake = FakeOrganizerLLMService(responses: [.init(suggestedName: "Invoice March 2026")])
        let engine = OrganizerEngine(llmService: fake)
        let content = ExtractedContent(originalURL: URL(fileURLWithPath: "/tmp/IMG_001.png"), utTypeIdentifier: "public.png", kind: .image, snippet: "Invoice #42")
        let proposal = try await engine.propose(contents: [content], rootURL: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(proposal.operations.count, 1)
        XCTAssertTrue(proposal.operations[0].proposedFilename.contains("Invoice"))
    }
    func testEngineHandlesLLMFailureGracefully() async throws {
        let fake = FakeOrganizerLLMService()
        fake.throwOnIndex = 0
        let engine = OrganizerEngine(llmService: fake)
        let content = ExtractedContent(originalURL: URL(fileURLWithPath: "/tmp/a.txt"), utTypeIdentifier: "public.text", kind: .text, snippet: "...")
        let proposal = try await engine.propose(contents: [content], rootURL: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(proposal.operations[0].proposedFilename, "a.txt")  // keeps original
    }
    func testEngineResolvesCollisions() async throws {
        let fake = FakeOrganizerLLMService(responses: [.init(suggestedName: "Report"), .init(suggestedName: "Report")])
        let engine = OrganizerEngine(llmService: fake)
        let c1 = ExtractedContent(originalURL: URL(fileURLWithPath: "/tmp/a.pdf"), utTypeIdentifier: "com.adobe.pdf", kind: .pdf, snippet: "Q1")
        let c2 = ExtractedContent(originalURL: URL(fileURLWithPath: "/tmp/b.pdf"), utTypeIdentifier: "com.adobe.pdf", kind: .pdf, snippet: "Q2")
        let proposal = try await engine.propose(contents: [c1, c2], rootURL: URL(fileURLWithPath: "/tmp"))
        XCTAssertNotEqual(proposal.operations[0].proposedFilename, proposal.operations[1].proposedFilename)
    }
}
