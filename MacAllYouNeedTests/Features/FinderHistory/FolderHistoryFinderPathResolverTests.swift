@testable import MacAllYouNeed
import XCTest

final class FolderHistoryFinderPathResolverTests: XCTestCase {
    func testAppleScriptFallbackUsedWhenInjected() {
        let path = FolderHistoryFinderPathResolver.resolve(
            pid: 1,
            axReader: StubFolderHistoryAXReader(),
            appleScriptFallback: { "/Users/me/Desktop" }
        )
        XCTAssertEqual(path, "/Users/me/Desktop")
    }
}

private struct StubFolderHistoryAXReader: FolderHistoryAXReader {
    func documentPath(for windowElement: AXUIElement) -> String? { nil }
}
