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

    func testUnsubscribeRemovesSubscriberAndTearsDownInstalledCallback() async throws {
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

    func testSubscribeDuringCallbackRemovalReinstallsForTheNewSubscriber() async {
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

    func testUnsubscribeDuringCallbackInstallationRemovesUnneededRegistration() async {
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
            return XCTFail("Expected _AXAddNotificationCallback to be available in the supported runtime")
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

    func testActionWindowReadsOnlyEventsAfterCursorWithoutDrainingHistory() async throws {
        let bus = AccessibilityNotificationBus()
        bus.recordForTesting(code: 1001, notificationData: .none, associatedElement: .none)

        let action = bus.beginActionWindow()
        XCTAssertEqual(action.cursor.sequence, 1)
        bus.recordForTesting(code: 1005, notificationData: .none, associatedElement: .none)
        bus.recordForTesting(
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
            bus.checkpoint(after: .origin, selection: .all).events.map(\.kind),
            [.elementChanged(.layout), .elementChanged(.value), .announcement]
        )
    }

    func testNestedActionWindowRollsEvidenceIntoOwnerWithoutReleasingIt() async throws {
        let bus = AccessibilityNotificationBus()
        let owner = bus.beginActionWindow()
        bus.recordForTesting(code: 1001, notificationData: .none, associatedElement: .none)
        let child = bus.beginActionWindow()
        bus.recordForTesting(code: 1005, notificationData: .none, associatedElement: .none)

        child.cancel()

        XCTAssertTrue(
            bus.checkpoint(after: .origin, selection: .unclaimedScoped).events.isEmpty
        )
        let ownerBatch = try XCTUnwrap(owner.capture())
        XCTAssertEqual(ownerBatch.events.map(\.kind), [
            .elementChanged(.layout),
            .elementChanged(.value),
        ])

        owner.consume()
        XCTAssertTrue(
            bus.checkpoint(after: .origin, selection: .unclaimedScoped).events.isEmpty
        )
    }

    func testOwnerReleaseReclassifiesNestedActionEvidenceAfterChildCloses() async {
        let bus = AccessibilityNotificationBus()
        let owner = bus.beginActionWindow()
        let child = bus.beginActionWindow()
        bus.recordForTesting(code: 1000, notificationData: .none, associatedElement: .none)

        child.cancel()
        owner.cancel()

        XCTAssertEqual(
            bus.checkpoint(after: .origin, selection: .unclaimedScoped).events.map(\.kind),
            [.screenChanged]
        )
    }

    func testOwnerReleaseBeforeChildCloseDefersReclassificationUntilChildEnds() async {
        let bus = AccessibilityNotificationBus()
        let owner = bus.beginActionWindow()
        let child = bus.beginActionWindow()
        bus.recordForTesting(code: 1000, notificationData: .none, associatedElement: .none)

        owner.cancel()

        XCTAssertTrue(
            bus.checkpoint(after: .origin, selection: .unclaimedScoped).events.isEmpty
        )

        child.cancel()

        XCTAssertEqual(
            bus.checkpoint(after: .origin, selection: .unclaimedScoped).events.map(\.kind),
            [.screenChanged]
        )
    }

    func testNewActionWindowCanBeginWhileEndedOwnerDrainsChildren() async {
        let bus = AccessibilityNotificationBus()
        let owner = bus.beginActionWindow()
        let child = bus.beginActionWindow()
        owner.consume()

        let successor = bus.beginActionWindow()
        bus.recordForTesting(code: 1000, notificationData: .none, associatedElement: .none)
        child.cancel()
        successor.cancel()

        XCTAssertEqual(
            bus.checkpoint(after: .origin, selection: .unclaimedScoped).events.map(\.kind),
            [.screenChanged]
        )
    }

    func testActionWindowReportsHistoryGapWithoutDrainingRetainedEvents() async throws {
        let bus = AccessibilityNotificationBus()
        let action = bus.beginActionWindow()

        for _ in 0..<65 {
            bus.recordForTesting(code: 1001, notificationData: .none, associatedElement: .none)
        }

        let batch = try XCTUnwrap(action.capture())
        let retainedSequences = bus.checkpoint(
            after: .origin,
            selection: .all
        ).events.map(\.sequence)
        action.cancel()

        XCTAssertEqual(action.cursor.sequence, 0)
        XCTAssertEqual(batch.gap, AccessibilityNotificationGap(droppedThroughSequence: 1))
        XCTAssertEqual(batch.through.sequence, 65)
        XCTAssertEqual(batch.events.map(\.sequence), Array(UInt64(2)...UInt64(65)))
        XCTAssertEqual(retainedSequences, batch.events.map(\.sequence))
    }

    func testRawCheckpointReportsOnlyRetentionEvictionAsGap() async {
        let bus = AccessibilityNotificationBus()
        for _ in 0..<65 {
            bus.recordForTesting(code: 1001, notificationData: .none, associatedElement: .none)
        }

        let raw = bus.checkpoint(after: .origin, selection: .all)
        let scoped = bus.checkpoint(after: .origin)

        XCTAssertEqual(raw.gap, AccessibilityNotificationGap(droppedThroughSequence: 1))
        XCTAssertEqual(raw.events.map(\.sequence), Array(UInt64(2)...UInt64(65)))
        XCTAssertNil(scoped.gap)
        XCTAssertTrue(scoped.events.isEmpty)
    }

    func testAnnouncementWaitOutcomeReportsRetainedHistoryGap() async {
        let bus = AccessibilityNotificationBus()
        let cursor = bus.cursor()
        for index in 0..<65 {
            bus.recordForTesting(
                code: 1008,
                notificationData: CapturedAccessibilityNotificationPayload(
                    "Unrelated announcement \(index)" as NSString
                ),
                associatedElement: .none
            )
        }

        let outcome = await bus.waitForAnnouncement(
            after: cursor,
            matching: ResolvedAnnouncementPredicate(
                match: ResolvedStringMatch(core: .exact("Expected announcement"))
            ),
            timeout: 60
        )

        XCTAssertEqual(
            outcome,
            .historyUnavailable(AccessibilityNotificationGap(droppedThroughSequence: 1))
        )
        XCTAssertEqual(bus.announcementWaiterCount, 0)
    }

    func testAnnouncementWaitOutcomePrefersRetainedMatchOverEarlierGap() async {
        let bus = AccessibilityNotificationBus()
        let cursor = bus.cursor()
        for index in 0..<64 {
            bus.recordForTesting(
                code: 1008,
                notificationData: CapturedAccessibilityNotificationPayload(
                    "Unrelated announcement \(index)" as NSString
                ),
                associatedElement: .none
            )
        }
        bus.recordForTesting(
            code: 1008,
            notificationData: CapturedAccessibilityNotificationPayload(
                "Expected announcement" as NSString
            ),
            associatedElement: .none
        )

        let outcome = await bus.waitForAnnouncement(
            after: cursor,
            matching: ResolvedAnnouncementPredicate(
                match: ResolvedStringMatch(core: .exact("Expected announcement"))
            ),
            timeout: 60
        )

        guard case .matched(let announcement) = outcome else {
            return XCTFail("Expected the retained announcement to match")
        }
        XCTAssertEqual(announcement.text, "Expected announcement")
        XCTAssertEqual(bus.announcementWaiterCount, 0)
    }

    func testStoppingSemanticObservationDoesNotClearNotificationHistory() async {
        let vault = TheVault(tripwire: TheTripwire())
        let heist = vault.accessibilityNotifications.beginHeistScope()
        vault.accessibilityNotifications.recordForTesting(
            code: 1001,
            notificationData: .none,
            associatedElement: .none
        )
        heist.cancel()

        vault.semanticObservationStream.stop()

        let batch = vault.accessibilityNotifications.checkpoint(after: .origin)
        XCTAssertEqual(batch.events.map(\.kind), [.elementChanged(.layout)])
        XCTAssertNil(batch.gap)
    }

    func testEndingHeistScopePreservesEventsForOpenActionWindow() async throws {
        let bus = AccessibilityNotificationBus()
        let heist = bus.beginHeistScope()
        let action = bus.beginActionWindow()
        bus.recordForTesting(code: 1001, notificationData: .none, associatedElement: .none)
        bus.recordForTesting(code: 1005, notificationData: .none, associatedElement: .none)

        heist.cancel()

        let batch = try XCTUnwrap(action.capture())
        action.cancel()
        XCTAssertEqual(batch.events.map(\.kind), [.elementChanged(.layout), .elementChanged(.value)])
        XCTAssertEqual(batch.through.sequence, 2)
        XCTAssertNil(batch.gap)
    }

    func testStringPayloadsFromPublicNotificationsAreCapturedAsAnnouncements() async {
        let bus = AccessibilityNotificationBus()

        bus.recordForTesting(
            code: 1008,
            notificationData: CapturedAccessibilityNotificationPayload("Item deleted" as NSString),
            associatedElement: .none
        )
        bus.recordForTesting(
            code: 1001,
            notificationData: CapturedAccessibilityNotificationPayload("3 items selected" as NSString),
            associatedElement: .none
        )
        bus.recordForTesting(
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
            matching: ResolvedAnnouncementPredicate(
                match: ResolvedStringMatch(core: .contains("selected"))
            ),
            timeout: 1.0
        )
        bus.recordForTesting(
            code: 1001,
            notificationData: CapturedAccessibilityNotificationPayload("3 items selected" as NSString),
            associatedElement: .none
        )

        guard case .matched(let announcement) = await result else {
            return XCTFail("Expected the layout announcement to match")
        }
        XCTAssertEqual(announcement.text, "3 items selected")
        XCTAssertEqual(announcement.kind, .elementChanged(.layout))
    }

    func testOverlappingConsumersProjectTheSameRetainedEvents() async throws {
        let bus = AccessibilityNotificationBus()
        let heist = bus.beginHeistScope()
        let action = bus.beginActionWindow()
        let announcementCursor = bus.cursor()
        let announcementTask = Task {
            await bus.waitForAnnouncement(
                after: announcementCursor,
                matching: ResolvedAnnouncementPredicate(
                    match: ResolvedStringMatch(core: .exact("Done"))
                ),
                timeout: 1
            )
        }
        await waitForAnnouncementWaiterCount(1, in: bus)

        bus.recordForTesting(code: 1001, notificationData: .none, associatedElement: .none)
        bus.recordForTesting(code: 1005, notificationData: .none, associatedElement: .none)
        bus.recordForTesting(
            code: 1008,
            notificationData: CapturedAccessibilityNotificationPayload("Done" as NSString),
            associatedElement: .none
        )

        let announcementOutcome = await announcementTask.value
        let actionBatch = try XCTUnwrap(action.capture())
        let heistBatch = bus.checkpoint(after: heist.cursor)
        let announcementProjection = bus.announcements(after: announcementCursor)
        action.cancel()
        heist.cancel()

        let expectedKinds: [AccessibilityNotificationKind] = [
            .elementChanged(.layout),
            .elementChanged(.value),
            .announcement,
        ]
        XCTAssertEqual(actionBatch.events.map(\.kind), expectedKinds)
        XCTAssertEqual(heistBatch.events.map(\.kind), expectedKinds)
        guard case .matched(let announcement) = announcementOutcome else {
            return XCTFail("Expected the retained announcement to match")
        }
        XCTAssertEqual(announcement.sequence, 3)
        XCTAssertEqual(announcementProjection.map(\.sequence), [3])
        XCTAssertEqual(
            bus.checkpoint(after: .origin, selection: .all).events.map(\.kind),
            expectedKinds
        )
    }

    func testCancellingAnnouncementWaitRemovesOnlyItsWaiter() async {
        let bus = AccessibilityNotificationBus()
        let task = Task {
            await bus.waitForAnnouncement(
                after: bus.cursor(),
                matching: ResolvedAnnouncementPredicate(
                    match: ResolvedStringMatch(core: .exact("Never"))
                ),
                timeout: 60
            )
        }
        await waitForAnnouncementWaiterCount(1, in: bus)

        task.cancel()
        let result = await task.value

        XCTAssertEqual(result, .timedOut)
        XCTAssertEqual(bus.announcementWaiterCount, 0)
    }

    func testObserverPublishesOneMonotonicPayloadSequenceToEverySubscriber() async throws {
        var callback: AccessibilityNotificationCallback?
        let observer = AccessibilityNotificationObserver(
            installCallbackForTesting: { callback = $0 },
            uninstallCallbackForTesting: {}
        )
        defer { observer.uninstall() }
        let first = AccessibilityNotificationBus()
        let second = AccessibilityNotificationBus()
        observer.subscribe(first)
        observer.subscribe(second)
        let publish = try XCTUnwrap(callback)

        publish(1001, nil, nil)
        publish(1005, "75%" as NSString, nil)
        publish(1008, "Done" as NSString, nil)

        let firstEvents = first.checkpoint(after: .origin, selection: .all).events
        let secondEvents = second.checkpoint(after: .origin, selection: .all).events
        XCTAssertEqual(firstEvents.map(\.sequence), [1, 2, 3])
        XCTAssertEqual(secondEvents.map(\.sequence), [1, 2, 3])
        XCTAssertEqual(
            firstEvents.map(\.kind),
            [.elementChanged(.layout), .elementChanged(.value), .announcement]
        )
        XCTAssertEqual(secondEvents.map(\.kind), firstEvents.map(\.kind))
        XCTAssertEqual(observer.latestSequence, 3)
        guard case .string(let firstValue) = firstEvents[1].notificationData,
              case .string(let secondValue) = secondEvents[1].notificationData else {
            return XCTFail("Expected both subscribers to receive the captured string payload")
        }
        XCTAssertEqual(firstValue, "75%")
        XCTAssertEqual(secondValue, firstValue)
    }

    func testObserverAdvancesPastSubscriberSequenceFromAnotherIngressSource() async throws {
        var callback: AccessibilityNotificationCallback?
        let observer = AccessibilityNotificationObserver(
            installCallbackForTesting: { callback = $0 },
            uninstallCallbackForTesting: {}
        )
        defer { observer.uninstall() }
        let bus = AccessibilityNotificationBus()
        observer.subscribe(bus)
        bus.record(
            sequence: 7,
            rawCode: 1005,
            timestamp: Date(timeIntervalSince1970: 0),
            notificationData: .none,
            associatedElement: .none
        )

        try XCTUnwrap(callback)(1001, nil, nil)

        XCTAssertEqual(
            bus.checkpoint(after: .origin, selection: .all).events.map(\.sequence),
            [7, 8]
        )
        XCTAssertEqual(observer.latestSequence, 8)
    }

    func testUnknownNotificationsPreserveRawCodesAtBoundary() async {
        let bus = AccessibilityNotificationBus()

        bus.recordForTesting(code: 1009, notificationData: .none, associatedElement: .none)
        bus.recordForTesting(code: 4002, notificationData: .none, associatedElement: .none)

        XCTAssertEqual(bus.latestSequence, 2)
        XCTAssertEqual(
            bus.checkpoint(after: .origin, selection: .all).events.map(\.kind),
            [.unknown(1009), .unknown(4002)]
        )
    }

    func testOnlyScopedScreenChangedAdvancesInvalidationCursor() async {
        let bus = AccessibilityNotificationBus()
        XCTAssertEqual(bus.latestScopedScreenChangedSequence, 0)

        bus.recordForTesting(code: 1000, notificationData: .none, associatedElement: .none)
        XCTAssertEqual(bus.latestScopedScreenChangedSequence, 0)

        let actionWindow = bus.beginActionWindow()
        defer { actionWindow.cancel() }
        bus.recordForTesting(code: 1001, notificationData: .none, associatedElement: .none)
        bus.recordForTesting(code: 1008, notificationData: .none, associatedElement: .none)
        bus.recordForTesting(code: 4002, notificationData: .none, associatedElement: .none)
        XCTAssertEqual(bus.latestScopedScreenChangedSequence, 0)

        bus.recordForTesting(code: 1000, notificationData: .none, associatedElement: .none)
        XCTAssertEqual(bus.latestScopedScreenChangedSequence, 5)
    }

    func testExplicitNotificationEventsPreservePublisherSequence() async {
        let bus = AccessibilityNotificationBus()
        bus.record(
            sequence: 7,
            rawCode: 1005,
            timestamp: Date(timeIntervalSince1970: 0),
            notificationData: .none,
            associatedElement: .none
        )
        bus.recordForTesting(code: 1001, notificationData: .none, associatedElement: .none)

        XCTAssertEqual(
            bus.checkpoint(after: .origin, selection: .all).events.map(\.sequence),
            [7, 8]
        )
        XCTAssertEqual(bus.latestSequence, 8)
    }

    func testCheckpointIncludesScopedEventsAndExcludesAmbientEvents() async {
        let bus = AccessibilityNotificationBus()
        bus.recordForTesting(code: 1000, notificationData: .none, associatedElement: .none)
        let heist = bus.beginHeistScope()
        bus.recordForTesting(code: 1001, notificationData: .none, associatedElement: .none)
        heist.cancel()
        bus.recordForTesting(code: 1000, notificationData: .none, associatedElement: .none)

        let batch = bus.checkpoint(after: .origin)

        XCTAssertEqual(batch.events.map(\.sequence), [2])
        XCTAssertEqual(batch.events.map(\.provenance), [.scoped])
        XCTAssertEqual(batch.through.sequence, 3)
        XCTAssertEqual(bus.announcements().count, 0)
    }

    // MARK: - Settled Observation Invalidation

    func testScreenChangedAfterCommitInvalidatesStaleServedObservation() async {
        let visibleObservationSource = VisibleObservationSourceFixture()
        let brains = TheBrains(
            tripwire: TheTripwire(),
            visibleObservationSource: visibleObservationSource.capture
        )
        brains.tripwire.startPulse()
        await brains.startSemanticObservation()
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
        let staleEvent = await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(staleScreen)

        // The completion notification lands after the commit, inside an
        // action's attribution window: the settled overview has already been
        // replaced and must not be served to the next read.
        let actionWindow = brains.vault.accessibilityNotifications.beginActionWindow()
        defer { actionWindow.cancel() }
        brains.vault.accessibilityNotifications.recordForTesting(
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
        visibleObservationSource.observation = freshScreen

        let served = await brains.vault.semanticObservationStream.settledEvent(
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
        let visibleObservationSource = VisibleObservationSourceFixture()
        let brains = TheBrains(
            tripwire: TheTripwire(),
            visibleObservationSource: visibleObservationSource.capture
        )
        brains.tripwire.startPulse()
        await brains.startSemanticObservation()
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
        let staleEvent = await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(staleScreen)

        brains.vault.accessibilityNotifications.recordForTesting(
            code: 1000,
            notificationData: .none,
            associatedElement: .none
        )
        let actionWindow = brains.vault.accessibilityNotifications.beginActionWindow()
        defer { actionWindow.cancel() }
        visibleObservationSource.observation = InterfaceObservation.makeForTests([
            InterfaceObservation.TestEntry(
                AccessibilityElement.make(label: "Destination", traits: .header),
                heistId: "destination_header"
            )
        ])

        let served = await brains.vault.semanticObservationStream.settledEvent(
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

    func testHeistScopeKeepsActionClaimsInBoundedTaggedStreamAfterScopeEnds() async {
        let bus = AccessibilityNotificationBus()
        bus.recordForTesting(code: 1001, notificationData: .none, associatedElement: .none)

        let heist = bus.beginHeistScope()
        let action = bus.beginActionWindow()
        bus.recordForTesting(code: 1005, notificationData: .none, associatedElement: .none)
        bus.recordForTesting(
            code: 1008,
            notificationData: CapturedAccessibilityNotificationPayload("Done" as NSString),
            associatedElement: .none
        )

        let claimed = action.capture()?.events ?? []
        action.cancel()

        XCTAssertEqual(claimed.map(\.kind), [.elementChanged(.value), .announcement])
        XCTAssertEqual(
            bus.checkpoint(after: .origin, selection: .all).events.map(\.kind),
            [.elementChanged(.layout), .elementChanged(.value), .announcement],
            "Action attribution must not drain the heist-scoped notification stream."
        )

        heist.cancel()
        XCTAssertEqual(
            bus.checkpoint(after: .origin, selection: .all).events.map(\.kind),
            [.elementChanged(.layout), .elementChanged(.value), .announcement]
        )
    }

    private func waitForNotification(
        kind: AccessibilityNotificationKind,
        after cursor: AccessibilityNotificationCursor,
        in bus: AccessibilityNotificationBus,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> PendingAccessibilityNotificationEvent {
        for _ in 0..<100 {
            if let event = bus.checkpoint(
                after: cursor,
                selection: .all
            ).events.first(where: { $0.kind == kind }) {
                return event
            }
            await Task.yield()
            _ = await Task.cancellableSleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for accessibility notification \(String(describing: kind))", file: file, line: line)
        throw WaitError.timedOut(kind)
    }

    private func waitForAnnouncementWaiterCount(
        _ expectedCount: Int,
        in bus: AccessibilityNotificationBus
    ) async {
        for _ in 0..<1_000 {
            guard bus.announcementWaiterCount != expectedCount else { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for \(expectedCount) announcement waiters")
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
