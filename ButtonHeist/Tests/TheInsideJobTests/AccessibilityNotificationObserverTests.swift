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
        case timedOut(AccessibilityNotificationKind)
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

    func testSubscribeDuringCallbackRemovalReinstallsForTheNewSubscriber() {
        let harness = CallbackRegistrationHarness()
        let observer = AccessibilityNotificationObserver(
            installCallbackForTesting: { harness.install() },
            uninstallCallbackForTesting: { harness.uninstall() }
        )
        harness.observer = observer
        let original = AccessibilityNotificationBus()
        let replacement = AccessibilityNotificationBus()

        observer.subscribe(original)
        harness.subscriberAddedDuringUninstall = replacement
        observer.unsubscribe(original)

        XCTAssertTrue(observer.hasSubscribers)
        XCTAssertTrue(observer.isInstalled)
        XCTAssertEqual(observer.lifecycleState, .subscribed(callbackInstalled: true))
        XCTAssertTrue(harness.isInstalled)
        XCTAssertEqual(harness.installCount, 2)
        XCTAssertEqual(harness.uninstallCount, 1)

        observer.unsubscribe(replacement)
        XCTAssertFalse(observer.hasSubscribers)
        XCTAssertFalse(observer.isInstalled)
        XCTAssertEqual(observer.lifecycleState, .unsubscribed)
        XCTAssertFalse(harness.isInstalled)
    }

    func testUnsubscribeDuringCallbackInstallationRemovesUnneededRegistration() {
        let harness = CallbackRegistrationHarness()
        let observer = AccessibilityNotificationObserver(
            installCallbackForTesting: { harness.install() },
            uninstallCallbackForTesting: { harness.uninstall() }
        )
        harness.observer = observer
        let subscriber = AccessibilityNotificationBus()
        harness.subscriberRemovedDuringInstall = subscriber

        observer.subscribe(subscriber)

        XCTAssertFalse(observer.hasSubscribers)
        XCTAssertFalse(observer.isInstalled)
        XCTAssertFalse(harness.isInstalled)
        XCTAssertEqual(harness.installCount, 1)
        XCTAssertEqual(harness.uninstallCount, 1)
    }

    func testObserverReceivesPostedPayloadShapes() async throws {
        let bus = AccessibilityNotificationBus()

        AccessibilityNotificationObserver.shared.subscribe(bus)
        guard AccessibilityNotificationObserver.shared.isInstalled else {
            throw XCTSkip("_AXAddNotificationCallback is unavailable in this runtime")
        }
        let cursor = AccessibilityNotificationCursor(sequence: bus.latestSequence)

        UIAccessibility.post(
            notification: .announcement,
            argument: "BH announcement string payload"
        )
        let announcement = try await waitForNotification(
            kind: .announcement,
            after: cursor,
            in: bus
        )
        XCTAssertEqual(announcement.kind, .announcement)
        guard case .string(let value) = announcement.notificationData else {
            return XCTFail("Expected string notification data, got \(announcement.notificationData)")
        }
        XCTAssertEqual(value, "BH announcement string payload")

        let container = NSObject()
        let element = UIAccessibilityElement(accessibilityContainer: container)
        element.accessibilityLabel = "BH layout element payload"
        UIAccessibility.post(notification: .layoutChanged, argument: element)
        let layoutChange = try await waitForNotification(
            kind: .elementChanged(.layout),
            after: cursor,
            in: bus
        )
        XCTAssertEqual(layoutChange.kind, .elementChanged(.layout))
        guard case .object(let objectIdentity) = layoutChange.notificationData else {
            return XCTFail("Expected element notification data, got \(layoutChange.notificationData)")
        }
        XCTAssertNil(objectIdentity.object)
        XCTAssertTrue(
            objectIdentity.summary?.contains("AXUIElementRef") == true,
            "Expected transformed AX element handle summary, got \(objectIdentity.summary ?? "nil")"
        )

        UIAccessibility.post(notification: .screenChanged, argument: nil)
        let screenChange = try await waitForNotification(
            kind: .screenChanged,
            after: cursor,
            in: bus
        )
        XCTAssertEqual(screenChange.kind, .screenChanged)
        guard case .none = screenChange.notificationData else {
            return XCTFail("Expected nil screen-change notification data, got \(screenChange.notificationData)")
        }
    }

    func testActionWindowReadsOnlyEventsAfterCursorWithoutDrainingHistory() throws {
        let bus = AccessibilityNotificationBus()
        bus.record(code: 1001, notificationData: .none, associatedElement: .none)

        let action = bus.beginActionWindow()
        XCTAssertEqual(action.cursor.sequence, 1)
        bus.record(code: 1005, notificationData: .none, associatedElement: .none)
        bus.record(
            code: 1008,
            notificationData: CapturedAccessibilityNotificationPayload("Done" as NSString),
            associatedElement: .none
        )

        let batch = try XCTUnwrap(action.capture())
        action.cancel()

        XCTAssertEqual(batch.events.map(\.kind), [.elementChanged(.value), .announcement])
        XCTAssertEqual(batch.events.map(\.sequence), [2, 3])
        XCTAssertEqual(batch.through.sequence, 3)
        XCTAssertNil(batch.gap)
        XCTAssertEqual(
            bus.pendingEvents().map(\.kind),
            [.elementChanged(.layout), .elementChanged(.value), .announcement]
        )
    }

    func testActionWindowReportsHistoryGapWithoutDrainingRetainedEvents() throws {
        let bus = AccessibilityNotificationBus()
        let action = bus.beginActionWindow()

        for _ in 0..<65 {
            bus.record(code: 1001, notificationData: .none, associatedElement: .none)
        }

        let batch = try XCTUnwrap(action.capture())
        let retainedSequences = bus.pendingEvents().map(\.sequence)
        action.cancel()

        XCTAssertEqual(action.cursor.sequence, 0)
        XCTAssertEqual(batch.gap, AccessibilityNotificationGap(droppedThroughSequence: 1))
        XCTAssertEqual(batch.through.sequence, 65)
        XCTAssertEqual(batch.events.map(\.sequence), Array(UInt64(2)...UInt64(65)))
        XCTAssertEqual(retainedSequences, batch.events.map(\.sequence))
    }

    func testClearingPendingEventsReportsGapToOpenActionWindow() throws {
        let bus = AccessibilityNotificationBus()
        let action = bus.beginActionWindow()
        bus.record(code: 1001, notificationData: .none, associatedElement: .none)
        bus.record(code: 1005, notificationData: .none, associatedElement: .none)

        bus.clearPendingEvents()

        let batch = try XCTUnwrap(action.capture())
        action.cancel()
        XCTAssertTrue(batch.events.isEmpty)
        XCTAssertEqual(batch.through.sequence, 2)
        XCTAssertEqual(batch.gap, AccessibilityNotificationGap(droppedThroughSequence: 2))
    }

    func testEndingHeistScopeReportsDiscardedEventsToOpenActionWindow() throws {
        let bus = AccessibilityNotificationBus()
        let heist = bus.beginHeistScope()
        let action = bus.beginActionWindow()
        bus.record(code: 1001, notificationData: .none, associatedElement: .none)
        bus.record(code: 1005, notificationData: .none, associatedElement: .none)

        heist.cancel()

        let batch = try XCTUnwrap(action.capture())
        action.cancel()
        XCTAssertTrue(batch.events.isEmpty)
        XCTAssertEqual(batch.through.sequence, 2)
        XCTAssertEqual(batch.gap, AccessibilityNotificationGap(droppedThroughSequence: 2))
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
        XCTAssertEqual(announcements.map(\.kind), [.announcement, .elementChanged(.layout), .screenChanged])
    }

    func testAnnouncementWaiterMatchesLayoutChangedStringPayload() async {
        let bus = AccessibilityNotificationBus()
        let cursor = bus.cursor()

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
        XCTAssertEqual(announcement?.kind, .elementChanged(.layout))
    }

    func testUnknownNotificationsPreserveRawCodesAtBoundary() {
        let bus = AccessibilityNotificationBus()

        bus.record(code: 1009, notificationData: .none, associatedElement: .none)
        bus.record(code: 4002, notificationData: .none, associatedElement: .none)

        XCTAssertEqual(bus.latestSequence, 2)
        XCTAssertEqual(
            bus.pendingEvents().map(\.kind),
            [.unknown(1009), .unknown(4002)]
        )
    }

    func testOnlyScopedScreenChangedAdvancesInvalidationCursor() {
        let bus = AccessibilityNotificationBus()
        XCTAssertEqual(bus.latestScopedScreenChangedSequence, 0)

        bus.record(code: 1000, notificationData: .none, associatedElement: .none)
        XCTAssertEqual(bus.latestScopedScreenChangedSequence, 0)

        let actionWindow = bus.beginActionWindow()
        defer { actionWindow.cancel() }
        bus.record(code: 1001, notificationData: .none, associatedElement: .none)
        bus.record(code: 1008, notificationData: .none, associatedElement: .none)
        bus.record(code: 4002, notificationData: .none, associatedElement: .none)
        XCTAssertEqual(bus.latestScopedScreenChangedSequence, 0)

        bus.record(code: 1000, notificationData: .none, associatedElement: .none)
        XCTAssertEqual(bus.latestScopedScreenChangedSequence, 5)
    }

    func testExplicitNotificationEventsPreservePublisherSequence() {
        let bus = AccessibilityNotificationBus()
        let event = PendingAccessibilityNotificationEvent(
            sequence: 7,
            kind: .elementChanged(.value),
            timestamp: Date(timeIntervalSince1970: 0),
            notificationData: .none,
            associatedElement: .none
        )

        bus.record(event)
        bus.record(code: 1001, notificationData: .none, associatedElement: .none)

        XCTAssertEqual(bus.pendingEvents().map(\.sequence), [7, 8])
        XCTAssertEqual(bus.latestSequence, 8)
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

        let staleScreen = InterfaceObservation.makeForTests([
            InterfaceObservation.TestEntry(
                AccessibilityElement.make(label: "Overview", traits: .header),
                heistId: "overview_header"
            )
        ])
        let staleEvent = brains.stash.semanticObservationStream.commitVisibleObservationForTesting(staleScreen)

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
        let freshScreen = InterfaceObservation.makeForTests([
            InterfaceObservation.TestEntry(
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

        let staleScreen = InterfaceObservation.makeForTests([
            InterfaceObservation.TestEntry(
                AccessibilityElement.make(label: "Overview", traits: .header),
                heistId: "overview_header"
            )
        ])
        let staleEvent = brains.stash.semanticObservationStream.commitVisibleObservationForTesting(staleScreen)

        brains.stash.accessibilityNotifications.record(
            code: 1000,
            notificationData: .none,
            associatedElement: .none
        )
        let actionWindow = brains.stash.accessibilityNotifications.beginActionWindow()
        defer { actionWindow.cancel() }
        brains.stash.nextVisibleRefreshScreenForTesting = InterfaceObservation.makeForTests([
            InterfaceObservation.TestEntry(
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

        let claimed = action.capture()?.events ?? []
        action.cancel()

        XCTAssertEqual(claimed.map(\.kind), [.elementChanged(.value), .announcement])
        XCTAssertEqual(
            bus.pendingEvents().map(\.kind),
            [.elementChanged(.value), .announcement],
            "Action attribution must not drain the heist-scoped notification stream."
        )

        heist.cancel()
        XCTAssertEqual(bus.pendingEvents().map(\.kind), [])
    }

    private func waitForNotification(
        kind: AccessibilityNotificationKind,
        after cursor: AccessibilityNotificationCursor,
        in bus: AccessibilityNotificationBus,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> PendingAccessibilityNotificationEvent {
        for _ in 0..<100 {
            if let event = bus.pendingEvents(after: cursor).first(where: { $0.kind == kind }) {
                return event
            }
            await Task.yield()
            _ = await Task.cancellableSleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for accessibility notification \(String(describing: kind))", file: file, line: line)
        throw WaitError.timedOut(kind)
    }

    @MainActor
    private final class CallbackRegistrationHarness {
        weak var observer: AccessibilityNotificationObserver?
        var subscriberRemovedDuringInstall: AccessibilityNotificationBus?
        var subscriberAddedDuringUninstall: AccessibilityNotificationBus?
        private(set) var installCount = 0
        private(set) var uninstallCount = 0
        private(set) var isInstalled = false

        func install() {
            installCount += 1
            isInstalled = true
            guard let subscriber = subscriberRemovedDuringInstall else { return }
            subscriberRemovedDuringInstall = nil
            observer?.unsubscribe(subscriber)
        }

        func uninstall() {
            uninstallCount += 1
            isInstalled = false
            guard let subscriber = subscriberAddedDuringUninstall else { return }
            subscriberAddedDuringUninstall = nil
            observer?.subscribe(subscriber)
        }
    }
}

#endif
