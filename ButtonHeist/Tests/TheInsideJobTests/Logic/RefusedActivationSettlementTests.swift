#if canImport(UIKit)
#if DEBUG
import XCTest

@testable import TheInsideJob
@testable import TheScore

@MainActor
final class RefusedActivationSettlementTests: SemanticObservationStreamTestCase {
    func testTwoUnchangedPostActionCapturesSettleQuiescent() async throws {
        let stream = vault.semanticObservationStream
        _ = await stream.commitVisibleObservationForTesting(
            observation(label: "Still", heistId: "screen")
        )
        let boundary = try XCTUnwrap(stream.refusedActivationBoundary())
        var quiescence = Observation.Stream.RefusedActivationQuiescence(boundary: boundary)

        let first = await stream.commitVisibleObservationForTesting(
            observation(label: "Still", heistId: "screen")
        )
        let second = await stream.commitVisibleObservationForTesting(
            observation(label: "Still", heistId: "screen")
        )

        XCTAssertEqual(quiescence.reduce(snapshot: first.current.snapshot), .awaiting)
        XCTAssertEqual(quiescence.reduce(snapshot: second.current.snapshot), .quiescent)
    }

    func testChangedCandidateRequiresTwoPostActionCapturesToObserveEffect() async throws {
        let stream = vault.semanticObservationStream
        _ = await stream.commitVisibleObservationForTesting(
            observation(label: "Before", heistId: "screen")
        )
        let boundary = try XCTUnwrap(stream.refusedActivationBoundary())
        var quiescence = Observation.Stream.RefusedActivationQuiescence(boundary: boundary)

        let first = await stream.commitVisibleObservationForTesting(
            observation(label: "After", heistId: "screen")
        )
        let second = await stream.commitVisibleObservationForTesting(
            observation(label: "After", heistId: "screen")
        )

        XCTAssertEqual(quiescence.reduce(snapshot: first.current.snapshot), .awaiting)
        XCTAssertEqual(quiescence.reduce(snapshot: second.current.snapshot), .effectObserved)
    }

    func testTransientChangedSnapshotFollowedByOriginalStateSettlesQuiescent() async throws {
        let stream = vault.semanticObservationStream
        _ = await stream.commitVisibleObservationForTesting(
            observation(label: "Before", heistId: "screen")
        )
        let boundary = try XCTUnwrap(stream.refusedActivationBoundary())
        var quiescence = Observation.Stream.RefusedActivationQuiescence(boundary: boundary)

        let transient = await stream.commitVisibleObservationForTesting(
            observation(label: "After", heistId: "screen")
        )
        let firstOriginal = await stream.commitVisibleObservationForTesting(
            observation(label: "Before", heistId: "screen")
        )
        let secondOriginal = await stream.commitVisibleObservationForTesting(
            observation(label: "Before", heistId: "screen")
        )

        XCTAssertEqual(quiescence.reduce(snapshot: transient.current.snapshot), .awaiting)
        XCTAssertEqual(quiescence.reduce(snapshot: firstOriginal.current.snapshot), .awaiting)
        XCTAssertEqual(quiescence.reduce(snapshot: secondOriginal.current.snapshot), .quiescent)
    }

    func testAmbientNotificationSnapshotsSettleQuiescentWhenStateIsUnchanged() async throws {
        let stream = vault.semanticObservationStream
        _ = await stream.commitVisibleObservationForTesting(
            observation(label: "Still", heistId: "screen")
        )
        let boundary = try XCTUnwrap(stream.refusedActivationBoundary())
        var quiescence = Observation.Stream.RefusedActivationQuiescence(boundary: boundary)
        let firstStable = await stream.commitVisibleObservationForTesting(
            observation(label: "Still", heistId: "screen"),
            notificationBatch: ambientNotificationBatch(sequence: 1)
        )
        let secondStable = await stream.commitVisibleObservationForTesting(
            observation(label: "Still", heistId: "screen"),
            notificationBatch: ambientNotificationBatch(sequence: 2)
        )

        XCTAssertEqual(firstStable.events, [.elementsChanged(firstStable.current.snapshot)])
        XCTAssertEqual(secondStable.events, [.elementsChanged(secondStable.current.snapshot)])
        XCTAssertEqual(quiescence.reduce(snapshot: firstStable.current.snapshot), .awaiting)
        XCTAssertEqual(quiescence.reduce(snapshot: secondStable.current.snapshot), .quiescent)
    }

    private func ambientNotificationBatch(sequence: UInt64) -> AccessibilityNotificationBatch {
        AccessibilityNotificationBatch(
            events: [PendingAccessibilityNotificationEvent(
                sequence: sequence,
                kind: .layoutChanged,
                timestamp: Date(timeIntervalSince1970: 0),
                notificationData: .none,
                associatedElement: .none,
                provenance: .ambient
            )],
            through: AccessibilityNotificationCursor(sequence: sequence),
            scopedScreenChangedThrough: 0,
            gap: nil
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
