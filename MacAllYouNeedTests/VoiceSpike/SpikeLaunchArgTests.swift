@testable import MacAllYouNeed
import XCTest

final class SpikeLaunchArgTests: XCTestCase {
    func testSpikeArgDetectedWhenPresent() {
        let argv = ["MacAllYouNeed", "--voice-spike"]
        XCTAssertTrue(VoiceSpikeLog.isSpikeEnabled(arguments: argv))
    }

    func testSpikeArgAbsentByDefault() {
        let argv = ["MacAllYouNeed"]
        XCTAssertFalse(VoiceSpikeLog.isSpikeEnabled(arguments: argv))
    }
}
