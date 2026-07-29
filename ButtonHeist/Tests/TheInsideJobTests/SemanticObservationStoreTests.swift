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

    func testEvictedRangeProducesIncompleteEvidence() {
        var history = Observation.History(retentionLimit: 1)
        _ = history.record([.noChange], protectedBy: nil)
        _ = history.record([.noChange], protectedBy: nil)

        let evidence = history.evidence(
            in: 0..<history.endIndex,
            baseline: snapshot(),
            current: snapshot()
        )

        XCTAssertEqual(evidence.completeness, .incomplete)
        XCTAssertTrue(evidence.events.isEmpty)
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

    func testDiscardRecordsScreenReplacementSandwich() {
        var state = TheVault.State()
        _ = state.commitObservation(admission())
        let boundary = state.history.endIndex

        state.discardCurrentObservation()
        let replacement = state.commitObservation(admission())

        XCTAssertEqual(replacement.events.count, 3)
        guard case .elementsChanged(let departure) = replacement.events[0],
              case .screenChanged = replacement.events[1],
              case .elementsChanged(let arrival) = replacement.events[2]
        else {
            return XCTFail("Expected departure, screen boundary, and arrival")
        }
        XCTAssertTrue(departure.interface.projectedElements.isEmpty)
        XCTAssertEqual(arrival, replacement.current.snapshot)
        XCTAssertEqual(state.history.screenGeneration(at: boundary + 1), 0)
        XCTAssertEqual(state.history.screenGeneration(at: boundary + 2), 1)
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
        notifications: [Observation.AdmittedNotification] = []
    ) -> Observation.Admission {
        let observation = InterfaceObservation.makeForTests()
        let through = notifications.map(\.sequence).max() ?? 0
        return Observation.Admission(
            tree: observation.tree,
            tripwireSignal: .empty,
            discoveryCommitPolicy: .mergeIntoInterface,
            lineage: .resting,
            scope: scope,
            notificationAdmission: .action(.init(
                admittedNotifications: notifications,
                through: AccessibilityNotificationCursor(sequence: through),
                scopedScreenChangedThrough: 0
            )),
            keyboardVisible: nil,
            timestamp: Date(timeIntervalSince1970: 0),
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
