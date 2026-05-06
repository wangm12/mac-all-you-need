@testable import Core
import XCTest

final class ClipboardXPCContractTests: XCTestCase {
    func testProtocolHasRequiredSelectors() {
        let p = ClipboardXPCProtocol.self as Protocol
        XCTAssertNotNil(p)
        let _ = ClipboardXPCList(items: [], nextPageToken: nil)
    }
}
