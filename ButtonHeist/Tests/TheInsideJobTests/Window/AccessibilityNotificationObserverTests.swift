#if canImport(UIKit)
import ButtonHeistSupport
import UIKit
import XCTest

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
        guard case .subscribed(let callbackInstalled, _) =
            AccessibilityNotificationObserver.shared.lifecycleState
        else {
            return XCTFail("Expected the shared observer to report a subscribed lifecycle")
        }
        XCTAssertEqual(callbackInstalled, installed)

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
        XCTAssertEqual(observer.lifecycleState, .subscribed(callbackInstalled: true, unitTestModeArmed: true))
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
            kind: .layoutChanged,
            after: cursor,
            in: bus
        )
        XCTAssertEqual(layoutChange.kind, .layoutChanged)
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

    func testActionWindowReadsOnlyEventsAfterCursorUntilAdmissionReleasesThem() async throws {
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

        let admitted = await action.admitCaptured { batch in
            XCTAssertEqual(batch.events.map(\.kind), [.elementUpdate, .announcement])
            XCTAssertEqual(batch.events.map(\.sequence), [2, 3])
            XCTAssertEqual(batch.through.sequence, 3)
            XCTAssertNil(batch.gap)
            XCTAssertEqual(
                bus.checkpoint(after: .origin, selection: .all).events.map(\.kind),
                [.layoutChanged, .elementUpdate, .announcement]
            )
            return batch
        }
        let batch = try XCTUnwrap(admitted)

        XCTAssertEqual(batch.through.sequence, 3)
        XCTAssertEqual(
            bus.checkpoint(after: .origin, selection: .all).events.map(\.kind),
            [.layoutChanged]
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
        let admitted = await owner.admitCaptured { Optional($0) }
        let ownerBatch = try XCTUnwrap(admitted)
        XCTAssertEqual(ownerBatch.events.map(\.kind), [
            .layoutChanged,
            .elementUpdate,
        ])

        XCTAssertTrue(
            bus.checkpoint(after: .origin, selection: .unclaimedScoped).events.isEmpty
        )
    }

    func testNestedActionAdmissionCommitsTheWholeAccumulatedActionWindow() async throws {
        let bus = AccessibilityNotificationBus()
        let owner = bus.beginActionWindow()
        bus.recordForTesting(code: 1001, notificationData: .none, associatedElement: .none)
        let child = bus.beginActionWindow()
        bus.recordForTesting(code: 1005, notificationData: .none, associatedElement: .none)

        let admittedChild = await child.admitCaptured { Optional($0) }
        let childBatch = try XCTUnwrap(admittedChild)
        XCTAssertEqual(childBatch.events.map(\.sequence), [1, 2])

        XCTAssertTrue(bus.checkpoint(after: .origin, selection: .all).events.isEmpty)

        let admittedOwner = await owner.admitCaptured { Optional($0) }
        let ownerBatch = try XCTUnwrap(admittedOwner)
        XCTAssertTrue(ownerBatch.events.isEmpty)

        XCTAssertTrue(bus.checkpoint(after: .origin, selection: .all).events.isEmpty)
    }

    func testOwnerCancellationRetainsNestedActionEvidenceForCycleClaim() async throws {
        let bus = AccessibilityNotificationBus()
        let owner = bus.beginActionWindow()
        let child = bus.beginActionWindow()
        bus.recordForTesting(code: 1000, notificationData: .none, associatedElement: .none)

        child.cancel()
        owner.cancel()

        XCTAssertEqual(
            bus.checkpoint(after: .origin, selection: .all).events.map(\.kind),
            [.screenChanged]
        )
        XCTAssertEqual(
            bus.checkpoint(after: .origin, selection: .all).events.map(\.provenance),
            [.scoped]
        )
        let claim = try XCTUnwrap(bus.freezeObservationCycleClaim())
        XCTAssertEqual(claim.batch.events.map(\.kind), [.screenChanged])
        XCTAssertTrue(claim.acknowledge())
    }

    func testOwnerCancellationKeepsEvidenceClaimedUntilChildEnds() async {
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
            bus.checkpoint(after: .origin, selection: .all).events.map(\.kind),
            [.screenChanged]
        )
        XCTAssertEqual(
            bus.checkpoint(after: .origin, selection: .all).events.map(\.provenance),
            [.scoped]
        )
    }

    func testChildEventAfterOwnerCancellationStaysClaimedUntilLastChildEnds() async {
        let bus = AccessibilityNotificationBus()
        let owner = bus.beginActionWindow()
        let child = bus.beginActionWindow()

        owner.cancel()
        bus.recordForTesting(code: 1000, notificationData: .none, associatedElement: .none)

        XCTAssertTrue(
            bus.checkpoint(after: .origin, selection: .unclaimedScoped).events.isEmpty
        )

        child.cancel()

        XCTAssertEqual(
            bus.checkpoint(after: .origin, selection: .all).events.map(\.kind),
            [.screenChanged]
        )
        XCTAssertEqual(
            bus.checkpoint(after: .origin, selection: .all).events.map(\.provenance),
            [.scoped]
        )
    }

    func testChildEventAfterSuccessorBeginsIsAttributedToDrainingWindow() async throws {
        let bus = AccessibilityNotificationBus()
        let owner = bus.beginActionWindow()
        let child = bus.beginActionWindow()
        owner.cancel()

        let successor = bus.beginActionWindow()
        bus.recordForTesting(code: 1000, notificationData: .none, associatedElement: .none)

        let childBatch = try XCTUnwrap(
            await child.admitCaptured { Optional($0) }
        )
        XCTAssertEqual(childBatch.events.map(\.kind), [.screenChanged])

        child.cancel()

        XCTAssertTrue(
            bus.checkpoint(after: .origin, selection: .unclaimedScoped).events.isEmpty
        )

        successor.cancel()

        XCTAssertEqual(
            bus.checkpoint(after: .origin, selection: .all).events.map(\.kind),
            [.screenChanged]
        )
        XCTAssertEqual(
            bus.checkpoint(after: .origin, selection: .all).events.map(\.provenance),
            [.scoped]
        )
    }

    func testActionWindowRetainsMoreThanAmbientLimitUntilAdmission() async throws {
        let bus = AccessibilityNotificationBus()
        let action = bus.beginActionWindow()

        for index in 0..<65 {
            bus.recordForTesting(
                code: 1008,
                notificationData: CapturedAccessibilityNotificationPayload(
                    "Action announcement \(index)" as NSString
                ),
                associatedElement: .none
            )
        }

        let admitted = await action.admitCaptured { batch in
            XCTAssertEqual(
                bus.checkpoint(after: .origin, selection: .all).events.map(\.sequence),
                Array(UInt64(1)...UInt64(65))
            )
            return batch
        }
        let batch = try XCTUnwrap(admitted)
        let retainedText = batch.events.compactMap { event -> String? in
            guard case .string(let text) = event.notificationData else { return nil }
            return text
        }
        XCTAssertNil(batch.gap)
        XCTAssertEqual(batch.through.sequence, 65)
        XCTAssertEqual(batch.events.map(\.sequence), Array(UInt64(1)...UInt64(65)))
        XCTAssertEqual(
            retainedText,
            (0..<65).map { "Action announcement \($0)" }
        )
        XCTAssertTrue(bus.checkpoint(after: .origin, selection: .all).events.isEmpty)
    }

    func testCycleClaimFreezesCutoffBeforeLaterIngress() async throws {
        let bus = AccessibilityNotificationBus()
        bus.recordForTesting(code: 1001, notificationData: .none, associatedElement: .none)

        let first = try XCTUnwrap(bus.freezeObservationCycleClaim())
        bus.recordForTesting(code: 1005, notificationData: .none, associatedElement: .none)

        XCTAssertEqual(first.batch.events.map(\.sequence), [1])
        XCTAssertEqual(first.batch.through.sequence, 1)
        XCTAssertTrue(first.acknowledge())

        let second = try XCTUnwrap(bus.freezeObservationCycleClaim())
        XCTAssertEqual(second.batch.events.map(\.sequence), [2])
        XCTAssertEqual(second.batch.through.sequence, 2)
    }

    func testUnacknowledgedCycleClaimIsReturnedIntactForRetry() async throws {
        let bus = AccessibilityNotificationBus()
        bus.recordForTesting(code: 1001, notificationData: .none, associatedElement: .none)

        let failedAttempt = try XCTUnwrap(bus.freezeObservationCycleClaim())
        let retry = try XCTUnwrap(bus.freezeObservationCycleClaim())

        XCTAssertEqual(retry.id, failedAttempt.id)
        XCTAssertEqual(retry.batch.events.map(\.sequence), [1])
        XCTAssertEqual(retry.batch.through, failedAttempt.batch.through)
        XCTAssertTrue(retry.acknowledge())
        XCTAssertTrue(bus.checkpoint(after: .origin, selection: .all).events.isEmpty)
    }

    func testCancelledScopeTransfersItsExactFrozenClaimForRetry() async throws {
        let bus = AccessibilityNotificationBus()
        let action = bus.beginActionWindow()
        bus.recordForTesting(code: 1001, notificationData: .none, associatedElement: .none)
        let failedCapture = try XCTUnwrap(action.capture())
        bus.recordForTesting(code: 1005, notificationData: .none, associatedElement: .none)

        action.cancel()

        let retry = try XCTUnwrap(bus.freezeObservationCycleClaim())
        XCTAssertEqual(retry.batch.events.map(\.sequence), failedCapture.events.map(\.sequence))
        XCTAssertEqual(retry.batch.through, failedCapture.through)
        XCTAssertTrue(retry.acknowledge())
        let next = try XCTUnwrap(bus.freezeObservationCycleClaim())
        XCTAssertEqual(next.batch.events.map(\.sequence), [2])
    }

    func testCycleClaimCanBeAcknowledgedAtMostOnce() async throws {
        let bus = AccessibilityNotificationBus()
        bus.recordForTesting(code: 1001, notificationData: .none, associatedElement: .none)

        let claim = try XCTUnwrap(bus.freezeObservationCycleClaim())

        XCTAssertTrue(claim.acknowledge())
        XCTAssertFalse(claim.acknowledge())
        XCTAssertTrue(bus.checkpoint(after: .origin, selection: .all).events.isEmpty)
    }

    func testCancelledActionEvidenceBeyondAmbientLimitWaitsForCycleAdmission() async throws {
        let bus = AccessibilityNotificationBus()
        let action = bus.beginActionWindow()
        for index in 0..<65 {
            bus.recordForTesting(
                code: 1008,
                notificationData: CapturedAccessibilityNotificationPayload(
                    "Cancelled action announcement \(index)" as NSString
                ),
                associatedElement: .none
            )
        }

        action.cancel()

        XCTAssertEqual(
            bus.checkpoint(after: .origin, selection: .all).events.map(\.sequence),
            Array(UInt64(1)...UInt64(65))
        )
        let claim = try XCTUnwrap(bus.freezeObservationCycleClaim())
        XCTAssertEqual(claim.batch.events.map(\.sequence), Array(UInt64(1)...UInt64(65)))
        XCTAssertNil(claim.batch.gap)
        XCTAssertTrue(claim.acknowledge())
        XCTAssertTrue(bus.checkpoint(after: .origin, selection: .all).events.isEmpty)
    }

    func testActionAdmissionDoesNotDiscardEventsAfterCapturedCutoff() async throws {
        let bus = AccessibilityNotificationBus()
        let action = bus.beginActionWindow()
        bus.recordForTesting(code: 1001, notificationData: .none, associatedElement: .none)
        let admitted = await action.admitCaptured { _ -> Bool? in
            bus.recordForTesting(code: 1005, notificationData: .none, associatedElement: .none)
            return true
        }

        XCTAssertEqual(admitted, true)
        let retained = bus.checkpoint(after: .origin, selection: .all)
        XCTAssertEqual(retained.events.map(\.sequence), [2])
        XCTAssertEqual(retained.events.map(\.provenance), [.scoped])
        XCTAssertNil(retained.gap)
    }

    func testHeistScopeRetainsMoreThanAmbientLimitUntilAdmission() async throws {
        let bus = AccessibilityNotificationBus()
        let heist = bus.beginHeistScope()

        for index in 0..<65 {
            bus.recordForTesting(
                code: 1008,
                notificationData: CapturedAccessibilityNotificationPayload(
                    "Heist announcement \(index)" as NSString
                ),
                associatedElement: .none
            )
        }

        let admitted = await heist.admitCaptured { Optional($0) }
        let batch = try XCTUnwrap(admitted)
        let retainedText = batch.events.compactMap { event -> String? in
            guard case .string(let text) = event.notificationData else { return nil }
            return text
        }
        XCTAssertNil(batch.gap)
        XCTAssertEqual(batch.events.map(\.sequence), Array(UInt64(1)...UInt64(65)))
        XCTAssertEqual(
            retainedText,
            (0..<65).map { "Heist announcement \($0)" }
        )

        XCTAssertTrue(bus.checkpoint(after: .origin, selection: .all).events.isEmpty)
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

    func testNotificationCheckpointReportsRetainedHistoryGap() async {
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

        let batch = bus.checkpoint(after: cursor, selection: .all)

        XCTAssertEqual(
            batch.gap,
            AccessibilityNotificationGap(droppedThroughSequence: 1)
        )
        XCTAssertEqual(batch.events.map(\.sequence), Array(UInt64(2)...UInt64(65)))
        XCTAssertEqual(batch.events.map(\.kind), Array(repeating: .announcement, count: 64))
    }

    func testNotificationCheckpointPreservesRetainedPayloadOrderAcrossGap() async {
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

        let batch = bus.checkpoint(after: cursor, selection: .all)
        let retainedText = batch.events.compactMap { event -> String? in
            guard case .string(let text) = event.notificationData else { return nil }
            return text
        }

        XCTAssertEqual(retainedText.last, "Expected announcement")
        XCTAssertEqual(batch.events.map(\.sequence), Array(UInt64(2)...UInt64(65)))
        XCTAssertEqual(
            batch.gap,
            AccessibilityNotificationGap(droppedThroughSequence: 1)
        )
    }

    func testStoppingSemanticObservationDoesNotClearRetainedIngress() async {
        let vault = TheVault(tripwire: TheTripwire())
        let heist = vault.accessibilityNotifications.beginHeistScope()
        vault.accessibilityNotifications.recordForTesting(
            code: 1001,
            notificationData: .none,
            associatedElement: .none
        )
        heist.cancel()

        vault.semanticObservationStream.stop()

        let batch = vault.accessibilityNotifications.checkpoint(
            after: .origin,
            selection: .all
        )
        XCTAssertEqual(batch.events.map(\.kind), [.layoutChanged])
        XCTAssertEqual(batch.events.map(\.provenance), [.scoped])
        XCTAssertNil(batch.gap)
    }

    func testEndingHeistScopePreservesEventsForOpenActionWindow() async throws {
        let bus = AccessibilityNotificationBus()
        let heist = bus.beginHeistScope()
        let action = bus.beginActionWindow()
        bus.recordForTesting(code: 1001, notificationData: .none, associatedElement: .none)
        bus.recordForTesting(code: 1005, notificationData: .none, associatedElement: .none)

        heist.cancel()

        let batch = try XCTUnwrap(
            await action.admitCaptured { Optional($0) }
        )
        XCTAssertEqual(batch.events.map(\.kind), [.layoutChanged, .elementUpdate])
        XCTAssertEqual(batch.through.sequence, 2)
        XCTAssertNil(batch.gap)
    }

    func testStringPayloadsFromPublicNotificationsAreCapturedInIngressOrder() async {
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

        let events = bus.checkpoint(after: .origin, selection: .all).events
        let text = events.compactMap { event -> String? in
            guard case .string(let value) = event.notificationData else { return nil }
            return value
        }
        XCTAssertEqual(text, ["Item deleted", "3 items selected", "Checkout"])
        XCTAssertEqual(
            events.map(\.kind),
            [.announcement, .layoutChanged, .screenChanged]
        )
    }

    func testActionAdmissionPreventsHeistAndObserverReadmission() async throws {
        let bus = AccessibilityNotificationBus()
        let heist = bus.beginHeistScope()
        let action = bus.beginActionWindow()

        bus.recordForTesting(code: 1001, notificationData: .none, associatedElement: .none)
        bus.recordForTesting(code: 1005, notificationData: .none, associatedElement: .none)
        bus.recordForTesting(
            code: 1008,
            notificationData: CapturedAccessibilityNotificationPayload("Done" as NSString),
            associatedElement: .none
        )

        let actionBatch = try XCTUnwrap(
            await action.admitCaptured { Optional($0) }
        )
        let heistBatch = try XCTUnwrap(
            await heist.admitCaptured { Optional($0) }
        )

        let expectedKinds: [AccessibilityNotificationKind] = [
            .layoutChanged,
            .elementUpdate,
            .announcement,
        ]
        XCTAssertEqual(actionBatch.events.map(\.kind), expectedKinds)
        XCTAssertTrue(heistBatch.events.isEmpty)
        XCTAssertTrue(bus.checkpoint(after: .origin, selection: .all).events.isEmpty)
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
            [.layoutChanged, .elementUpdate, .announcement]
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

    func testProbeObservesOnlyElementUpdateNotifications() throws {
        let payload = CapturedAccessibilityNotificationPayload("Updated" as NSString)

        XCTAssertNil(
            AccessibilityNotificationProbe.description(
                rawCode: 1001,
                notificationData: payload,
                associatedElement: .none
            )
        )
        XCTAssertNotNil(
            AccessibilityNotificationProbe.description(
                rawCode: 1005,
                notificationData: payload,
                associatedElement: .none
            )
        )
    }

    func testProbeDescriptionPreservesBehaviorTokensFromRawPayload() throws {
        let behavior = [
            "ChangeType": 2,
            "IsQuiet": true,
        ] as NSDictionary
        let notificationData = [
            "data": behavior,
            "token": "kAXValueChangeUserInfoKey",
        ] as NSDictionary
        let associatedElement = NSObject()

        let description = try XCTUnwrap(
            AccessibilityNotificationProbe.description(
                rawCode: 1005,
                notificationData: CapturedAccessibilityNotificationPayload(notificationData),
                associatedElement: CapturedAccessibilityNotificationPayload(associatedElement)
            )
        )

        XCTAssertTrue(description.contains("code=1005(elementUpdate)"))
        XCTAssertTrue(description.contains("notificationData.class="))
        XCTAssertTrue(description.contains("kAXValueChangeUserInfoKey"))
        XCTAssertTrue(description.contains("ChangeType"))
        XCTAssertTrue(description.contains("IsQuiet"))
        XCTAssertTrue(description.contains("associatedElement.class="))
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

    func testCheckpointIncludesScopedEventsAndExcludesAmbientEvents() async throws {
        let bus = AccessibilityNotificationBus()
        bus.recordForTesting(code: 1000, notificationData: .none, associatedElement: .none)
        let heist = bus.beginHeistScope()
        bus.recordForTesting(code: 1001, notificationData: .none, associatedElement: .none)
        let batch = try XCTUnwrap(
            await heist.admitCaptured { Optional($0) }
        )
        bus.recordForTesting(code: 1000, notificationData: .none, associatedElement: .none)

        XCTAssertEqual(batch.events.map(\.sequence), [2])
        XCTAssertEqual(batch.events.map(\.provenance), [.scoped])
        XCTAssertEqual(batch.through.sequence, 2)
    }

    func testCancelledScopesRemainOwnedUntilCycleAdmission() async throws {
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

        var claimed: [PendingAccessibilityNotificationEvent] = []
        _ = await action.admitCaptured { batch -> Bool? in
            claimed = batch.events
            return nil
        }
        action.cancel()

        XCTAssertEqual(claimed.map(\.kind), [.elementUpdate, .announcement])
        XCTAssertEqual(
            bus.checkpoint(after: .origin, selection: .all).events.map(\.kind),
            [.layoutChanged, .elementUpdate, .announcement],
            "Action attribution must not drain the heist-scoped notification stream."
        )

        heist.cancel()
        XCTAssertEqual(
            bus.checkpoint(after: .origin, selection: .all).events.map(\.kind),
            [.layoutChanged, .elementUpdate, .announcement]
        )
        XCTAssertEqual(
            bus.checkpoint(after: .origin, selection: .all).events.map(\.provenance),
            [.ambient, .scoped, .scoped]
        )
        let cycle = try XCTUnwrap(bus.freezeObservationCycleClaim())
        XCTAssertEqual(
            cycle.batch.events.map(\.kind),
            [.elementChanged(.layout), .elementChanged(.value), .announcement]
        )
        XCTAssertTrue(cycle.acknowledge())
        XCTAssertTrue(bus.checkpoint(after: .origin, selection: .all).events.isEmpty)
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

/// Which screen changes reach past a settled commit.
///
/// A settled observation describes the screen it was taken on, so a screen
/// change after it means the observation describes a screen we are no longer
/// looking at. Scope is what decides whether a given change says that: one
/// recorded inside an action's attribution window belongs to the command and
/// counts, one recorded outside it is the host app talking to itself and does
/// not.
///
/// What the reader consults is the bus's scoped-screenChanged sequence against
/// the cursor the commit absorbed, so that pair is what these assert. A commit
/// takes the cursor up to the scoped changes it already knows about, which makes
/// "the bus is ahead" precisely "a scoped screen change arrived since". Neither
/// side moves on a clock, and neither is touched by the other invalidation
/// sources sharing the store's flag.
@MainActor
final class ScreenChangeCursorAdmissionTests: ButtonHeistObservationTestCase {

    private var visibleObservationSource = VisibleObservationSourceFixture()

    override func makeBrains(tripwire: TheTripwire) throws -> TheBrains {
        TheBrains(
            tripwire: tripwire,
            visibleObservationSource: visibleObservationSource.capture
        )
    }

    func testScreenChangedInsideCommandScopeOutrunsTheCommittedCursor() async {
        await commitOverview()

        let actionWindow = brains.vault.accessibilityNotifications.beginActionWindow()
        defer { actionWindow.cancel() }
        recordScreenChanged()

        let committed = await committedScopedScreenChangedCursor()
        XCTAssertGreaterThan(
            brains.vault.accessibilityNotifications.latestScopedScreenChangedSequence,
            committed,
            "A screenChanged inside command scope must outrun the commit, so the next read invalidates it"
        )
    }

    func testScreenChangedOutsideCommandScopeLeavesTheCommittedCursorAhead() async {
        await commitOverview()

        recordScreenChanged()
        let actionWindow = brains.vault.accessibilityNotifications.beginActionWindow()
        defer { actionWindow.cancel() }

        let committed = await committedScopedScreenChangedCursor()
        XCTAssertLessThanOrEqual(
            brains.vault.accessibilityNotifications.latestScopedScreenChangedSequence,
            committed,
            "A screenChanged outside command scope must not outrun the commit, so the next read serves it"
        )
    }

    private func commitOverview() async {
        _ = await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            InterfaceObservation.makeForTests([
                InterfaceObservation.TestEntry(
                    AccessibilityElement.make(label: "Overview", traits: .header),
                    heistId: "overview_header"
                )
            ])
        )
    }

    private func recordScreenChanged() {
        brains.vault.accessibilityNotifications.recordForTesting(
            code: 1000,
            notificationData: .none,
            associatedElement: .none
        )
    }

    private func committedScopedScreenChangedCursor() async -> UInt64 {
        await brains.vault.semanticObservationStream.stateOwner.scopedScreenChangedSequence()
    }
}

#endif
