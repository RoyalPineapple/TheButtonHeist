#if canImport(UIKit)
#if DEBUG
import Foundation
import XCTest

@testable import TheInsideJob
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
        history.record([
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
        _ = state.readObservation(admission())
        let boundary = state.history.endIndex
        state.protectHistory(from: boundary)

        _ = state.readObservation(admission())
        _ = state.readObservation(admission())
        _ = state.readObservation(admission())

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
        history.record([.noChange], protectedBy: nil)
        history.record([.noChange], protectedBy: nil)

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
        let first = state.readObservation(admission())
        let second = state.readObservation(admission())

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
        _ = state.readObservation(admission())
        let boundary = state.history.endIndex

        state.discardCurrentObservation()
        let replacement = state.readObservation(admission())

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
        _ = state.readObservation(admission())
        let notification = Observation.AdmittedNotification(
            sequence: 1,
            kind: .elementChanged(.layout),
            text: "Updated",
            element: nil
        )

        let read = state.readObservation(admission(notifications: [notification]))

        XCTAssertEqual(
            read.events.first,
            .notification(try XCTUnwrap(Observation.Notification(
                text: "Updated",
                element: nil
            )))
        )
        guard case .elementsChanged(let snapshot) = read.events.last else {
            return XCTFail("Layout notification must force an element-change event")
        }
        XCTAssertEqual(snapshot, read.current.snapshot)
    }

    func testCurrentAfterBoundaryUsesHistoryAvailability() {
        var state = TheVault.State(retentionLimit: 1)
        _ = state.readObservation(admission())
        let boundary = state.history.endIndex

        XCTAssertEqual(
            try state.current(after: boundary, scope: .visible).get(),
            nil
        )

        let current = state.readObservation(admission()).current

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
            captureID: observation.captureID,
            tripwireSignal: .empty,
            discoveryCommitPolicy: .mergeIntoInterface,
            lineage: .resting,
            scope: scope,
            notificationAdmission: .action(.init(
                evidence: [],
                admittedNotifications: notifications,
                through: AccessibilityNotificationCursor(sequence: through),
                scopedScreenChangedThrough: 0,
                gap: nil
            )),
            keyboardVisible: nil,
            timestamp: Date(timeIntervalSince1970: 0),
            viewportFrames: observation.tree.viewportFrames,
            geometryTolerance: CoarseFrameComparison.currentTolerance
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
