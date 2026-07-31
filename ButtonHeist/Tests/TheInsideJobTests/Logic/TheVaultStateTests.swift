#if canImport(UIKit)
#if DEBUG
import Foundation
import XCTest

@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import ThePlans
@testable import TheScore

@MainActor
final class TheVaultStateTests: XCTestCase {
    func testHistoryOwnsOrder() throws {
        var history = Observation.History(retentionLimit: 4)
        let events: [Observation.Event] = [
            .noChange,
            .screenChanged(ScreenFacts(idAfter: "Checkout")),
            .elementsChanged(snapshot()),
        ]

        let recorded = history.record(events, protectedBy: nil)

        XCTAssertEqual(recorded, 0..<3)
        XCTAssertEqual(Array(history), events)
    }

    func testPruningRetainsNewestEvents() {
        var history = Observation.History(retentionLimit: 2)
        _ = history.record([
            .screenChanged(ScreenFacts(idAfter: "Checkout")),
            .noChange,
            .noChange,
        ], protectedBy: nil)

        XCTAssertEqual(history.startIndex, 1)
        XCTAssertEqual(Array(history), [.noChange, .noChange])
    }

    func testProtectedBoundaryPreventsEvictionUntilReleased() throws {
        var state = TheVault.State(retentionLimit: 2)
        _ = commit(&state, admission())
        let boundary = state.history.endIndex
        state.protectHistory(from: boundary)

        _ = commit(&state, admission())
        _ = commit(&state, admission())
        _ = commit(&state, admission())

        XCTAssertEqual(state.history.startIndex, boundary)
        XCTAssertEqual(
            Array(try state.history.events(after: boundary)),
            [.noChange, .noChange, .noChange]
        )

        state.releaseHistory(from: boundary)

        XCTAssertEqual(state.history.count, 2)
        XCTAssertThrowsError(try state.history.events(after: boundary)) { error in
            XCTAssertEqual(error as? Observation.History.ReadError, .rangeUnavailable)
        }
    }

    func testAdvancingProtectedBoundaryReleasesCompletedLeafHistory() throws {
        var state = TheVault.State(retentionLimit: 2)
        _ = commit(&state, admission())
        let firstBoundary = state.history.endIndex
        state.protectHistory(from: firstBoundary)

        _ = commit(&state, admission())
        _ = commit(&state, admission())
        let nextBoundary = state.history.endIndex
        state.advanceHistoryProtection(from: firstBoundary, to: nextBoundary)
        _ = commit(&state, admission())

        XCTAssertEqual(state.history.count, 2)
        XCTAssertThrowsError(
            try state.history.events(after: firstBoundary)
        ) { error in
            XCTAssertEqual(
                error as? Observation.History.ReadError,
                .rangeUnavailable
            )
        }
        XCTAssertEqual(
            Array(try state.history.events(after: nextBoundary)),
            [.noChange]
        )
    }

    func testEvictedRangeProducesIncompleteEvidence() {
        var history = Observation.History(retentionLimit: 1)
        _ = history.record([.noChange], protectedBy: nil)
        _ = history.record([.noChange], protectedBy: nil)

        let evidence = history.evidence(
            in: 0..<history.endIndex,
            baseline: snapshot(),
            current: snapshot()
        )

        XCTAssertEqual(evidence.coverage, .incomplete(.historyUnavailable))
        XCTAssertTrue(evidence.events.isEmpty)
    }

    func testIncompleteNotificationBatchCannotConstructAnAdmissionSnapshot() {
        XCTAssertNil(
            Observation.NotificationSnapshot(
                admittedNotifications: [],
                through: AccessibilityNotificationCursor(sequence: 7),
                scopedScreenChangedThrough: 0,
                gap: AccessibilityNotificationGap(droppedThroughSequence: 7)
            )
        )
    }

    func testEqualSettledStateRecordsNoChange() {
        var state = TheVault.State()
        let first = commit(&state, admission())
        let second = commit(&state, admission())

        guard case .elementsChanged(let initial) = first.events.last else {
            return XCTFail("The first parse must establish element truth")
        }
        XCTAssertEqual(initial, first.current.snapshot)
        XCTAssertEqual(second.events, [.noChange])
        XCTAssertEqual(Array(state.history), first.events + second.events)
        XCTAssertEqual(state.current, second.current)
    }

    func testReplacementPublishesNotificationDepartureBoundaryAndArrivalInOrder() throws {
        var state = TheVault.State()
        let baseline = commit(&state, admission(
            keyboardVisible: true,
            timestamp: Date(timeIntervalSince1970: 1)
        ))
        let boundary = state.history.endIndex
        let replacement = commit(&state, admission(
            notifications: [
                Observation.AdmittedNotification(
                    sequence: 1,
                    kind: .announcement,
                    text: "Opening checkout",
                    element: nil
                ),
                Observation.AdmittedNotification(
                    sequence: 2,
                    kind: .screenChanged,
                    text: nil,
                    element: nil
                ),
            ],
            keyboardVisible: false,
            timestamp: Date(timeIntervalSince1970: 2)
        ))

        XCTAssertEqual(replacement.events.count, 4)
        guard case .notification(let notification) = replacement.events[0],
              case .elementsChanged(let departure) = replacement.events[1],
              case .screenChanged = replacement.events[2],
              case .elementsChanged(let arrival) = replacement.events[3]
        else {
            return XCTFail("Expected notification, departure, screen boundary, and arrival")
        }
        XCTAssertEqual(notification.text, "Opening checkout")
        XCTAssertTrue(departure.interface.tree.isEmpty)
        XCTAssertEqual(
            departure.interface.timestamp,
            baseline.current.snapshot.interface.timestamp
        )
        XCTAssertEqual(departure.context, baseline.current.snapshot.context)
        XCTAssertNotEqual(departure.context, arrival.context)
        XCTAssertEqual(arrival, replacement.current.snapshot)
        XCTAssertEqual(
            Array(try state.history.events(after: boundary)),
            replacement.events
        )
    }

    func testNotificationPrecedesForcedElementChange() throws {
        var state = TheVault.State()
        _ = commit(&state, admission())
        let notification = Observation.AdmittedNotification(
            sequence: 1,
            kind: .layoutChanged,
            text: "Updated",
            element: nil
        )

        let publication = commit(&state, admission(notifications: [notification]))

        XCTAssertEqual(
            publication.events.first,
            .notification(try XCTUnwrap(Observation.Notification(
                text: "Updated",
                element: nil
            )))
        )
        guard case .elementsChanged(let snapshot) = publication.events.last else {
            return XCTFail("Layout notification must force an element-change event")
        }
        XCTAssertEqual(snapshot, publication.current.snapshot)
    }

    func testCurrentAfterBoundaryUsesHistoryAvailability() {
        var state = TheVault.State(retentionLimit: 1)
        _ = commit(&state, admission())
        let boundary = state.history.endIndex

        XCTAssertEqual(
            try state.current(after: boundary, scope: .visible).get(),
            nil
        )

        let current = commit(&state, admission()).current

        XCTAssertEqual(
            try state.current(after: boundary, scope: .visible).get(),
            current
        )
    }

    func testRejectedLiveCaptureReattachmentLeavesCommittedStateUntouched() {
        var state = TheVault.State()
        let retained = InterfaceObservation.makeForTests(
            elements: [(AccessibilityElement.make(label: "Retained"), "retained")]
        )
        let initial = requireCommitted(
            state.commitObservation(
                admission(observation: retained),
                sourceObservation: retained,
                beginningNewBaseline: false
            )
        )
        let priorHistoryEnd = state.history.endIndex
        let priorNotificationIndex = state.notificationIndex
        let priorCurrent = state.current
        let priorObservation = state.interfaceObservation
        let replacement = InterfaceObservation.makeForTests(
            elements: [(AccessibilityElement.make(label: "Replacement"), "replacement")]
        )

        let rejected = state.commitObservation(
            admission(observation: replacement),
            sourceObservation: retained,
            beginningNewBaseline: false
        )

        guard case .failure(.liveCaptureReattachmentFailed) = rejected else {
            return XCTFail("Expected capture reattachment to reject the commit")
        }
        XCTAssertEqual(state.history.endIndex, priorHistoryEnd)
        XCTAssertEqual(state.notificationIndex, priorNotificationIndex)
        XCTAssertEqual(state.current, priorCurrent)
        XCTAssertEqual(state.interfaceObservation?.tree, priorObservation?.tree)
        XCTAssertEqual(initial.current, priorCurrent)
    }

    private func admission(
        scope: SemanticObservationScope = .visible,
        notifications: [Observation.AdmittedNotification] = [],
        keyboardVisible: Bool? = nil,
        timestamp: Date = Date(timeIntervalSince1970: 0),
        observation: InterfaceObservation = .empty
    ) -> Observation.Admission {
        let through = notifications.map(\.sequence).max() ?? 0
        return Observation.Admission(
            tree: observation.tree,
            tripwireSignal: .empty,
            discoveryCommitPolicy: .mergeIntoInterface,
            lineage: .resting,
            scope: scope,
            notifications: Observation.NotificationSnapshot(
                admittedNotifications: notifications,
                through: AccessibilityNotificationCursor(sequence: through),
                scopedScreenChangedThrough: 0
            )!,
            keyboardVisible: keyboardVisible,
            timestamp: timestamp,
            viewportFrames: observation.tree.viewportFrames,
            geometryTolerance: CoarseFrameComparison.currentGeometryTolerance
        )
    }

    private func commit(
        _ state: inout TheVault.State,
        _ admission: Observation.Admission
    ) -> Observation.Publication {
        requireCommitted(state.commitObservation(
            admission,
            sourceObservation: .empty,
            beginningNewBaseline: false
        ))
    }

    private func requireCommitted(
        _ result: Result<Observation.Publication, Observation.CaptureFailure>
    ) -> Observation.Publication {
        switch result {
        case .success(let publication):
            publication
        case .failure(let failure):
            preconditionFailure("Test observation was rejected: \(failure.diagnostic)")
        }
    }

    private func snapshot() -> Observation.Snapshot {
        Observation.Snapshot(
            interface: Interface(
                timestamp: Date(timeIntervalSince1970: 0),
                tree: []
            ),
            context: .empty
        )
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
