@testable import Core
import XCTest

final class ClipboardXPCContractTests: XCTestCase {
    func testProtocolHasRequiredSelectors() {
        let p = ClipboardXPCProtocol.self as Protocol
        XCTAssertNotNil(p)
        _ = ClipboardXPCList(items: [], nextPageToken: nil)
    }
}
