#if canImport(UIKit)
#if DEBUG
import Foundation
import XCTest

@testable import TheInsideJob
@testable import ThePlans
@testable import TheScore

@MainActor
final class SemanticObservationStoreTests: XCTestCase {
    func testHistoryOwnsOrderAndDerivesScreenGenerationFromPosition() throws {
        var history = Observation.History(retentionLimit: 4)
        let events: [Observation.Event] = [
            .noChange,
            .screenChanged(ScreenFacts(idAfter: "Checkout")),
            .elementsChanged(snapshot()),
        ]

        let recorded = history.record(events, protectedBy: nil)

        XCTAssertEqual(recorded, 0..<3)
        XCTAssertEqual(Array(history), events)
        XCTAssertEqual(history.screenGeneration(at: 0), 0)
        XCTAssertEqual(history.screenGeneration(at: 1), 0)
        XCTAssertEqual(history.screenGeneration(at: 2), 1)
        XCTAssertEqual(history.screenGeneration(at: history.endIndex), 1)
    }

    func testPruningRetainsDerivedScreenGeneration() {
        var history = Observation.History(retentionLimit: 2)
        _ = history.record([
            .screenChanged(ScreenFacts(idAfter: "Checkout")),
            .noChange,
            .noChange,
        ], protectedBy: nil)

        XCTAssertEqual(history.startIndex, 1)
        XCTAssertEqual(Array(history), [.noChange, .noChange])
        XCTAssertEqual(history.screenGeneration(at: history.startIndex), 1)
        XCTAssertEqual(history.screenGeneration(at: history.endIndex), 1)
    }

    func testProtectedBoundaryPreventsEvictionUntilReleased() throws {
        var state = TheVault.State(retentionLimit: 2)
        _ = state.commitObservation(admission())
        let boundary = state.history.endIndex
        state.protectHistory(from: boundary)

        _ = state.commitObservation(admission())
        _ = state.commitObservation(admission())
        _ = state.commitObservation(admission())

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
        _ = state.commitObservation(admission())
        let firstBoundary = state.history.endIndex
        state.protectHistory(from: firstBoundary)

        _ = state.commitObservation(admission())
        _ = state.commitObservation(admission())
        let nextBoundary = state.history.endIndex
        state.advanceHistoryProtection(from: firstBoundary, to: nextBoundary)
        _ = state.commitObservation(admission())

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
        let first = state.commitObservation(admission())
        let second = state.commitObservation(admission())

        guard case .elementsChanged(let initial) = first.events.last else {
            return XCTFail("The first parse must establish element truth")
        }
        XCTAssertEqual(initial, first.current.snapshot)
        XCTAssertEqual(second.events, [.noChange])
        XCTAssertEqual(Array(state.history), first.events + second.events)
        XCTAssertEqual(state.current, second.current)
    }

    func testReplacementPublishesNotificationDepartureBoundaryAndArrivalInOrder() {
        var state = TheVault.State()
        let baseline = state.commitObservation(admission(
            keyboardVisible: true,
            timestamp: Date(timeIntervalSince1970: 1)
        ))
        let boundary = state.history.endIndex
        let replacement = state.commitObservation(admission(
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
        XCTAssertEqual(state.history.screenGeneration(at: boundary), 0)
        XCTAssertEqual(state.history.screenGeneration(at: boundary + 1), 0)
        XCTAssertEqual(state.history.screenGeneration(at: boundary + 2), 0)
        XCTAssertEqual(state.history.screenGeneration(at: boundary + 3), 1)
        XCTAssertEqual(state.history.screenGeneration(at: boundary + 4), 1)
    }

    func testNotificationPrecedesForcedElementChange() throws {
        var state = TheVault.State()
        _ = state.commitObservation(admission())
        let notification = Observation.AdmittedNotification(
            sequence: 1,
            kind: .layoutChanged,
            text: "Updated",
            element: nil
        )

        let publication = state.commitObservation(admission(notifications: [notification]))

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
        _ = state.commitObservation(admission())
        let boundary = state.history.endIndex

        XCTAssertEqual(
            try state.current(after: boundary, scope: .visible).get(),
            nil
        )

        let current = state.commitObservation(admission()).current

        XCTAssertEqual(
            try state.current(after: boundary, scope: .visible).get(),
            current
        )
    }

    private func admission(
        scope: SemanticObservationScope = .visible,
        notifications: [Observation.AdmittedNotification] = [],
        keyboardVisible: Bool? = nil,
        timestamp: Date = Date(timeIntervalSince1970: 0)
    ) -> Observation.Admission {
        let observation = InterfaceObservation.makeForTests()
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
