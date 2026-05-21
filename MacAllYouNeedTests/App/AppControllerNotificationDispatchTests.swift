@testable import MacAllYouNeed
import Combine
import Core
import Foundation
import XCTest

/// Characterization tests for AppNotificationObservers, the typed-publisher
/// adapter that replaces the 9 raw NotificationCenter subscriptions in
/// AppController.
///
/// Each test posts the matching NotificationCenter notification and
/// asserts the adapter emits the corresponding AppEvent case on its
/// PassthroughSubject. This pins the contract so the AppController
/// extraction can't silently drop or rewire an observer.
@MainActor
final class AppControllerNotificationDispatchTests: XCTestCase {
    private var observers: AppNotificationObservers!
    private var center: NotificationCenter!
    private var received: [AppEvent] = []
    private var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()
        center = NotificationCenter()
        // Synchronous delivery on the posting thread so we can assert
        // immediately after post(). Production wires queue: .main via the
        // default initializer parameter; the typed publisher contract is
        // identical either way.
        observers = AppNotificationObservers(center: center, queue: nil)
        received = []
        cancellables = []
        observers.events
            .sink { [weak self] event in self?.received.append(event) }
            .store(in: &cancellables)
    }

    override func tearDown() {
        cancellables = []
        observers = nil
        center = nil
        received = []
        super.tearDown()
    }

    func testBrowseFolderNotificationEmitsBrowseFolderEventWithURL() {
        let url = URL(fileURLWithPath: "/tmp/example")
        center.post(name: .browseFolderRequested, object: url)
        XCTAssertEqual(received, [.browseFolder(url)])
    }

    func testBrowseFolderNotificationWithNonURLObjectIsIgnored() {
        center.post(name: .browseFolderRequested, object: "not a url")
        XCTAssertEqual(received, [])
    }

    func testClipboardDownloadNotificationEmitsDownloadRequestedEvent() {
        let url = URL(string: "https://example.com/video.mp4")!
        center.post(name: .clipboardDownloadRequested, object: url)
        XCTAssertEqual(received, [.clipboardDownloadRequested(url)])
    }

    func testPauseCaptureNotificationEmitsPauseCaptureEvent() {
        center.post(name: .pauseCaptureRequested, object: nil)
        XCTAssertEqual(received, [.pauseCaptureRequested])
    }

    func testClearOlderThanNotificationExtractsDaysFromNSNumber() {
        center.post(name: .clearClipboardOlderThanRequested, object: NSNumber(value: 30))
        XCTAssertEqual(received, [.clearClipboardOlderThan(days: 30)])
    }

    func testClearOlderThanNotificationExtractsDaysFromInt() {
        center.post(name: .clearClipboardOlderThanRequested, object: 14)
        XCTAssertEqual(received, [.clearClipboardOlderThan(days: 14)])
    }

    func testClearOlderThanNotificationDefaultsToZeroForUnknownPayload() {
        center.post(name: .clearClipboardOlderThanRequested, object: "garbage")
        XCTAssertEqual(received, [.clearClipboardOlderThan(days: 0)])
    }

    func testClearAllNotificationEmitsClearAllEvent() {
        center.post(name: .clearAllClipboardHistoryRequested, object: nil)
        XCTAssertEqual(received, [.clearAllClipboardHistory])
    }

    func testMainWindowSettingsNotificationEmitsRouteEvent() {
        center.post(name: .mainWindowSettingsRequested, object: "voice")
        XCTAssertEqual(received, [.mainWindowSettings(route: "voice")])
    }

    func testMainWindowSettingsNotificationWithNilObjectEmitsNilRoute() {
        center.post(name: .mainWindowSettingsRequested, object: nil)
        XCTAssertEqual(received, [.mainWindowSettings(route: nil)])
    }

    func testFeatureRuntimeStateChangedNotificationEmitsFeatureEvent() {
        center.post(name: .featureRuntimeStateChanged, object: nil)
        XCTAssertEqual(received, [.featureRuntimeStateChanged])
    }

    func testHotkeyRecorderStartNotificationEmitsRecordingStartedEvent() {
        center.post(name: .hotkeyRecorderDidStartRecording, object: nil)
        XCTAssertEqual(received, [.hotkeyRecordingStarted])
    }

    func testHotkeyRecorderStopNotificationEmitsRecordingStoppedEvent() {
        center.post(name: .hotkeyRecorderDidStopRecording, object: nil)
        XCTAssertEqual(received, [.hotkeyRecordingStopped])
    }

    func testEachNotificationDispatchesIndependently() {
        let url = URL(fileURLWithPath: "/tmp/example")
        center.post(name: .browseFolderRequested, object: url)
        center.post(name: .pauseCaptureRequested, object: nil)
        center.post(name: .clearAllClipboardHistoryRequested, object: nil)
        center.post(name: .hotkeyRecorderDidStartRecording, object: nil)
        center.post(name: .hotkeyRecorderDidStopRecording, object: nil)
        center.post(name: .featureRuntimeStateChanged, object: nil)
        XCTAssertEqual(received, [
            .browseFolder(url),
            .pauseCaptureRequested,
            .clearAllClipboardHistory,
            .hotkeyRecordingStarted,
            .hotkeyRecordingStopped,
            .featureRuntimeStateChanged
        ])
    }

    func testDeallocateRemovesAllObservers() {
        observers = nil
        center.post(name: .browseFolderRequested, object: URL(fileURLWithPath: "/tmp"))
        center.post(name: .pauseCaptureRequested, object: nil)
        XCTAssertEqual(received, [])
    }
}
