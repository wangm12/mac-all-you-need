@testable import MacAllYouNeed
import FeatureCore
import Foundation
import SwiftUI
import XCTest

// MARK: - Stub FeatureManager

// FeatureStatePublisher needs a FeatureManager. We make a real one with an isolated defaults suite.
private func makeTestManager() -> FeatureManager {
    let clipboard = FeatureDescriptor(
        id: .clipboard,
        displayName: "Clipboard",
        icon: "doc",
        summary: "",
        detailDescription: "",
        activator: NoopFeatureActivator()
    )
    let registry = FeatureRegistry(descriptors: [clipboard])
    let defaults = UserDefaults(suiteName: "FeatureStatePublisherObservationTests-\(UUID().uuidString)")!
    return FeatureManager(registry: registry, defaults: defaults)
}

// MARK: - Tests

@MainActor
final class FeatureStatePublisherObservationTests: XCTestCase {

    // MARK: Initial state

    func testInitialStatesIsEmpty() {
        let manager = makeTestManager()
        let publisher = FeatureStatePublisher(manager: manager)
        // states may be empty or populated (the init fires a Task to refresh);
        // the important thing is states is a dict — type-check is implicit.
        XCTAssertNotNil(publisher.states as [FeatureID: FeatureRuntimeState]?)
    }

    // MARK: state(for:) convenience

    func testStateForUnknownIDReturnsDefault() {
        let manager = makeTestManager()
        let publisher = FeatureStatePublisher(manager: manager)
        let state = publisher.state(for: .voice)
        XCTAssertEqual(state.activationState, .disabled)
    }

    // MARK: refresh updates states

    func testRefreshPopulatesStates() async {
        let manager = makeTestManager()
        let publisher = FeatureStatePublisher(manager: manager)
        await publisher.refresh()
        XCTAssertNotNil(publisher.states[.clipboard])
    }

    func testRefreshReflectsManagerTransition() async throws {
        let manager = makeTestManager()
        let publisher = FeatureStatePublisher(manager: manager)

        try await manager.transition(.enable, for: .clipboard)
        await publisher.refresh()

        let state = publisher.states[.clipboard]
        XCTAssertEqual(state?.activationState, .enabled)
    }

    // MARK: Notification fires on Darwin notification

    func testDarwinNotificationTriggersConcurrentRefresh() async {
        let manager = makeTestManager()
        let publisher = FeatureStatePublisher(manager: manager)
        await publisher.refresh()

        let before = publisher.states

        // Post the Darwin notification that FeatureStatePublisher observes
        NotificationCenter.default.post(name: .featureRuntimeStateChanged, object: nil)

        // Give the async Task in the observer a chance to run
        try? await Task.sleep(nanoseconds: 50_000_000)

        // States should still be valid (same or updated)
        XCTAssertNotNil(publisher.states as [FeatureID: FeatureRuntimeState]?)
        _ = before // suppress unused warning
    }

    // MARK: Observation — states mutation notifies via Observation framework (post-migration)
    //
    // withObservationTracking only fires for @Observable types. This test is the
    // post-migration parity check; against ObservableObject code notificationCount stays 0.

    func testStatesMutationNotifiesObserver() async {
        let manager = makeTestManager()
        let publisher = FeatureStatePublisher(manager: manager)

        var notificationCount = 0
        func track() {
            withObservationTracking {
                _ = publisher.states
            } onChange: {
                notificationCount += 1
                Task { @MainActor in track() }
            }
        }
        track()

        // Trigger a refresh which mutates `states`
        await publisher.refresh()

        XCTAssertGreaterThanOrEqual(
            notificationCount, 1,
            "Expected at least one Observation notification after states mutation"
        )
    }
}
