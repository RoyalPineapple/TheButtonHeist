#if canImport(UIKit)
import ButtonHeistSupport
import UIKit
import XCTest

import ThePlans
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

@MainActor
final class AccessibilityNotificationObserverTests: XCTestCase {
    private enum WaitError: Error {
        case timedOut(UInt32)
    }

    override func tearDown() async throws {
        AccessibilityNotificationObserver.shared.uninstall()
        try await super.tearDown()
    }

    func testUnsubscribeRemovesSubscriberAndTearsDownInstalledCallback() throws {
        let bus = AccessibilityNotificationBus()

        AccessibilityNotificationObserver.shared.subscribe(bus)
        let installed = AccessibilityNotificationObserver.shared.isInstalled
        XCTAssertEqual(
            AccessibilityNotificationObserver.shared.lifecycleState,
            .subscribed(callbackInstalled: installed)
        )

        AccessibilityNotificationObserver.shared.unsubscribe(bus)

        XCTAssertFalse(AccessibilityNotificationObserver.shared.hasSubscribers)
        XCTAssertEqual(AccessibilityNotificationObserver.shared.lifecycleState, .unsubscribed)
        XCTAssertFalse(AccessibilityNotificationObserver.shared.isInstalled)
    }

    func testObserverReceivesPostedPayloadShapes() async throws {
        let bus = AccessibilityNotificationBus()

        AccessibilityNotificationObserver.shared.subscribe(bus)
        guard AccessibilityNotificationObserver.shared.isInstalled else {
            throw XCTSkip("_AXAddNotificationCallback is unavailable in this runtime")
        }
        bus.clearPendingEvents()

        UIAccessibility.post(
            notification: .announcement,
            argument: "BH announcement string payload"
        )
        let announcement = try await waitForNotification(code: 1008, in: bus)
        guard case .string(let value) = announcement.notificationData else {
            return XCTFail("Expected string notification data, got \(announcement.notificationData)")
        }
        XCTAssertEqual(value, "BH announcement string payload")

        let container = NSObject()
        let element = UIAccessibilityElement(accessibilityContainer: container)
        element.accessibilityLabel = "BH layout element payload"
        UIAccessibility.post(notification: .layoutChanged, argument: element)
        let layoutChange = try await waitForNotification(code: 1001, in: bus)
        guard case .object(let objectIdentity) = layoutChange.notificationData else {
            return XCTFail("Expected element notification data, got \(layoutChange.notificationData)")
        }
        XCTAssertNil(objectIdentity.object)
        XCTAssertTrue(
            objectIdentity.summary?.contains("AXUIElementRef") == true,
            "Expected transformed AX element handle summary, got \(objectIdentity.summary ?? "nil")"
        )

        UIAccessibility.post(notification: .screenChanged, argument: nil)
        let screenChange = try await waitForNotification(code: 1000, in: bus)
        guard case .none = screenChange.notificationData else {
            return XCTFail("Expected nil screen-change notification data, got \(screenChange.notificationData)")
        }
    }

    func testActionWindowClaimsOnlyEventsAfterCursor() {
        let bus = AccessibilityNotificationBus()
        bus.record(code: 1001, notificationData: .none, associatedElement: .none)

        let action = bus.beginActionWindow()
        bus.record(code: 1005, notificationData: .none, associatedElement: .none)
        bus.record(
            code: 1008,
            notificationData: CapturedAccessibilityNotificationPayload("Done" as NSString),
            associatedElement: .none
        )

        let claimed = action.finishAndClaimEvents()

        XCTAssertEqual(claimed.map(\.code), [1008])
        XCTAssertEqual(bus.pendingEvents().map(\.code), [])
    }

    func testStringPayloadsFromPublicNotificationsAreCapturedAsAnnouncements() {
        let bus = AccessibilityNotificationBus()

        bus.record(
            code: 1008,
            notificationData: CapturedAccessibilityNotificationPayload("Item deleted" as NSString),
            associatedElement: .none
        )
        bus.record(
            code: 1001,
            notificationData: CapturedAccessibilityNotificationPayload("3 items selected" as NSString),
            associatedElement: .none
        )
        bus.record(
            code: 1000,
            notificationData: CapturedAccessibilityNotificationPayload("Checkout" as NSString),
            associatedElement: .none
        )

        let announcements = bus.announcements()
        XCTAssertEqual(announcements.map(\.text), ["Item deleted", "3 items selected", "Checkout"])
        XCTAssertEqual(announcements.map(\.notificationName), ["announcement", "layoutChanged", "screenChanged"])
    }

    func testAnnouncementWaiterMatchesLayoutChangedStringPayload() async {
        let bus = AccessibilityNotificationBus()
        let cursor = bus.announcementCursor()

        async let result = bus.waitForAnnouncement(
            after: cursor,
            matching: AnnouncementPredicate(match: .contains("selected")),
            timeout: 1.0
        )
        bus.record(
            code: 1001,
            notificationData: CapturedAccessibilityNotificationPayload("3 items selected" as NSString),
            associatedElement: .none
        )

        let announcement = await result
        XCTAssertEqual(announcement?.text, "3 items selected")
        XCTAssertEqual(announcement?.notificationName, "layoutChanged")
    }

    // MARK: - Transition Waiter

    func testTransitionWaiterResumesWhenTransitionEventRecorded() async {
        let bus = AccessibilityNotificationBus()
        let cursor = bus.transitionCursor()

        async let wake = bus.waitForTransitionEvent(after: cursor, timeout: 2.0)
        bus.record(code: 1001, notificationData: .none, associatedElement: .none)

        let advanced = await wake
        XCTAssertNotNil(advanced)
        XCTAssertGreaterThan(advanced?.sequence ?? 0, cursor.sequence)
    }

    func testTransitionWaiterFastPathReturnsPastEventWithoutSuspending() async {
        let bus = AccessibilityNotificationBus()
        let cursor = bus.transitionCursor()
        bus.record(code: 1000, notificationData: .none, associatedElement: .none)

        let advanced = await bus.waitForTransitionEvent(after: cursor, timeout: 0)

        XCTAssertEqual(advanced?.sequence, bus.transitionCursor().sequence)
    }

    func testTransitionWaiterIgnoresAnnouncementsAndUnsupportedEventsAndTimesOut() async {
        let bus = AccessibilityNotificationBus()
        let cursor = bus.transitionCursor()
        bus.record(code: 4002, notificationData: .none, associatedElement: .none)

        async let wake = bus.waitForTransitionEvent(after: cursor, timeout: 0.15)
        bus.record(
            code: 1008,
            notificationData: CapturedAccessibilityNotificationPayload("Done" as NSString),
            associatedElement: .none
        )

        let advanced = await wake
        XCTAssertNil(advanced)
        XCTAssertEqual(bus.pendingEvents().map(\.code), [1008])
        XCTAssertEqual(bus.transitionCursor(), cursor)
    }

    func testUnsupportedNotificationsAreDroppedAtBoundary() {
        let bus = AccessibilityNotificationBus()

        bus.record(code: 1005, notificationData: .none, associatedElement: .none)
        bus.record(code: 1009, notificationData: .none, associatedElement: .none)
        bus.record(code: 4002, notificationData: .none, associatedElement: .none)

        XCTAssertEqual(bus.latestSequence, 0)
        XCTAssertEqual(bus.pendingEvents().map(\.code), [])
        XCTAssertEqual(bus.transitionCursor(), .origin)
    }

    func testTransitionWaiterCancellationReturnsPromptlyAndRemovesWaiter() async {
        let bus = AccessibilityNotificationBus()
        let cursor = bus.transitionCursor()

        let task = Task {
            await bus.waitForTransitionEvent(after: cursor, timeout: 5.0)
        }
        await waitForTransitionWaiterCount(1, in: bus)

        let cancelledAt = Date()
        task.cancel()
        let advanced = await task.value

        XCTAssertNil(advanced)
        XCTAssertLessThan(Date().timeIntervalSince(cancelledAt), 0.5)
        await waitForTransitionWaiterCount(0, in: bus)
    }

    func testTransitionCursorAndScopedScreenChangedSequenceTracking() {
        let bus = AccessibilityNotificationBus()
        XCTAssertEqual(bus.transitionCursor().sequence, 0)
        XCTAssertEqual(bus.latestScopedScreenChangedSequence, 0)

        bus.record(code: 1001, notificationData: .none, associatedElement: .none)
        XCTAssertEqual(bus.transitionCursor().sequence, 1)
        XCTAssertEqual(bus.latestScopedScreenChangedSequence, 0)

        bus.record(code: 1008, notificationData: .none, associatedElement: .none)
        XCTAssertEqual(bus.transitionCursor().sequence, 1)

        bus.record(code: 1000, notificationData: .none, associatedElement: .none)
        XCTAssertEqual(bus.transitionCursor().sequence, 3)
        XCTAssertEqual(bus.latestScopedScreenChangedSequence, 0)

        let actionWindow = bus.beginActionWindow()
        defer { actionWindow.cancel() }
        bus.record(code: 1000, notificationData: .none, associatedElement: .none)
        XCTAssertEqual(bus.transitionCursor().sequence, 4)
        XCTAssertEqual(bus.latestScopedScreenChangedSequence, 4)
    }

    // MARK: - Settled Observation Invalidation

    func testScreenChangedAfterCommitInvalidatesStaleServedObservation() async {
        let brains = TheBrains(tripwire: TheTripwire())
        brains.tripwire.startPulse()
        brains.startSemanticObservation()
        defer {
            brains.stopSemanticObservation()
            brains.tripwire.stopPulse()
        }

        let staleScreen = Screen.makeForTests([
            Screen.TestEntry(
                AccessibilityElement.make(label: "Overview", traits: .header),
                heistId: "overview_header"
            )
        ])
        let staleEvent = brains.stash.semanticObservationStream.commitSettledVisibleObservation(staleScreen)

        // The completion notification lands after the commit, inside an
        // action's attribution window: the settled overview has already been
        // replaced and must not be served to the next read.
        let actionWindow = brains.stash.accessibilityNotifications.beginActionWindow()
        defer { actionWindow.cancel() }
        brains.stash.accessibilityNotifications.record(
            code: 1000,
            notificationData: .none,
            associatedElement: .none
        )
        let freshScreen = Screen.makeForTests([
            Screen.TestEntry(
                AccessibilityElement.make(label: "Destination", traits: .header),
                heistId: "destination_header"
            )
        ])
        brains.stash.nextVisibleRefreshScreenForTesting = freshScreen

        let served = await brains.stash.observeSettledSemanticObservation(
            scope: .visible,
            after: staleEvent.sequence > 0 ? staleEvent.sequence - 1 : nil,
            timeout: 3.0
        )

        XCTAssertNotNil(served)
        XCTAssertGreaterThan(
            served?.sequence ?? 0,
            staleEvent.sequence,
            "A screenChanged recorded after the settled commit must invalidate it, not serve it from cache"
        )
    }

    func testAmbientScreenChangedAfterCommitDoesNotInvalidateLaterScopedRead() async {
        let brains = TheBrains(tripwire: TheTripwire())
        brains.tripwire.startPulse()
        brains.startSemanticObservation()
        defer {
            brains.stopSemanticObservation()
            brains.tripwire.stopPulse()
        }

        let staleScreen = Screen.makeForTests([
            Screen.TestEntry(
                AccessibilityElement.make(label: "Overview", traits: .header),
                heistId: "overview_header"
            )
        ])
        let staleEvent = brains.stash.semanticObservationStream.commitSettledVisibleObservation(staleScreen)

        brains.stash.accessibilityNotifications.record(
            code: 1000,
            notificationData: .none,
            associatedElement: .none
        )
        let actionWindow = brains.stash.accessibilityNotifications.beginActionWindow()
        defer { actionWindow.cancel() }
        brains.stash.nextVisibleRefreshScreenForTesting = Screen.makeForTests([
            Screen.TestEntry(
                AccessibilityElement.make(label: "Destination", traits: .header),
                heistId: "destination_header"
            )
        ])

        let served = await brains.stash.observeSettledSemanticObservation(
            scope: .visible,
            after: staleEvent.sequence > 0 ? staleEvent.sequence - 1 : nil,
            timeout: 0.25
        )

        XCTAssertEqual(
            served?.sequence,
            staleEvent.sequence,
            "A screenChanged recorded outside command scope must not poison the next scoped settled read."
        )
    }

    func testHeistScopeKeepsActionClaimsAppendOnlyUntilScopeEnds() {
        let bus = AccessibilityNotificationBus()
        bus.record(code: 1001, notificationData: .none, associatedElement: .none)

        let heist = bus.beginHeistScope()
        let action = bus.beginActionWindow()
        bus.record(code: 1005, notificationData: .none, associatedElement: .none)
        bus.record(
            code: 1008,
            notificationData: CapturedAccessibilityNotificationPayload("Done" as NSString),
            associatedElement: .none
        )

        let claimed = action.finishAndClaimEvents()

        XCTAssertEqual(claimed.map(\.code), [1008])
        XCTAssertEqual(
            bus.pendingEvents().map(\.code),
            [1008],
            "Action attribution must not drain the heist-scoped notification stream."
        )

        heist.cancel()
        XCTAssertEqual(bus.pendingEvents().map(\.code), [])
    }

    private func waitForNotification(
        code: UInt32,
        in bus: AccessibilityNotificationBus,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> PendingAccessibilityNotificationEvent {
        for _ in 0..<100 {
            if let event = bus.pendingEvents().first(where: { $0.code == code }) {
                return event
            }
            await Task.yield()
            _ = await Task.cancellableSleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for accessibility notification \(code)", file: file, line: line)
        throw WaitError.timedOut(code)
    }

    private func waitForTransitionWaiterCount(
        _ expectedCount: Int,
        in bus: AccessibilityNotificationBus,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<100 {
            if bus.transitionWaiterCount == expectedCount {
                return
            }
            await Task.yield()
            _ = await Task.cancellableSleep(for: .milliseconds(1))
        }
        XCTAssertEqual(bus.transitionWaiterCount, expectedCount, file: file, line: line)
    }
}

#endif
