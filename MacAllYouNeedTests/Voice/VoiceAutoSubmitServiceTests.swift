import Core
@testable import MacAllYouNeed
import XCTest

final class VoiceAutoSubmitServiceTests: XCTestCase {
    func testNonePostsNoEvents() {
        let recorder = EventRecorder()
        let service = VoiceAutoSubmitService(postEvent: recorder.post)

        service.submit(.none)

        XCTAssertTrue(recorder.events.isEmpty)
    }

    func testReturnKeyPostsDownAndUpEvents() {
        let recorder = EventRecorder()
        let service = VoiceAutoSubmitService(postEvent: recorder.post)

        service.submit(.returnKey)

        XCTAssertEqual(recorder.events.map(\.keyCode), [36, 36])
        XCTAssertEqual(recorder.events.map(\.isKeyDown), [true, false])
        XCTAssertEqual(recorder.events.map(\.flags), [[], []])
    }

    func testCommandReturnPostsCommandModifiedEvents() {
        let recorder = EventRecorder()
        let service = VoiceAutoSubmitService(postEvent: recorder.post)

        service.submit(.commandReturn)

        XCTAssertEqual(recorder.events.map(\.keyCode), [36, 36])
        XCTAssertEqual(recorder.events.map(\.isKeyDown), [true, false])
        XCTAssertEqual(recorder.events.map(\.flags), [[.maskCommand], [.maskCommand]])
    }
}

private final class EventRecorder {
    private(set) var events: [VoiceAutoSubmitEvent] = []

    func post(_ event: VoiceAutoSubmitEvent) {
        events.append(event)
    }
}
