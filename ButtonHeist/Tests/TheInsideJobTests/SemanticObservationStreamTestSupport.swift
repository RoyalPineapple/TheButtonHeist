#if canImport(UIKit)
#if DEBUG
import Foundation
import XCTest

import ButtonHeistTestSupport

@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
class SemanticObservationStreamTestCase: XCTestCase {
    var vault: TheVault!

    override func setUp() async throws {
        vault = TheVault(tripwire: TheTripwire())
    }

    override func tearDown() async throws {
        vault.semanticObservationStream.stop()
        vault = nil
    }

    func observation(label: String, heistId: HeistId) -> InterfaceObservation {
        .makeForTests(elements: [
            (AccessibilityElement.make(label: label, traits: .header), heistId),
        ])
    }

    func scrollObservation(
        headerId: HeistId,
        rowLabel: String,
        rowId: HeistId,
        headerObject: NSObject,
        rowObject: NSObject
    ) -> InterfaceObservation {
        let containerPath = TreePath([0])
        let headerPath = containerPath.appending(0)
        let rowPath = containerPath.appending(1)
        let header = AccessibilityElement.make(label: "Menu", traits: .header)
        let row = AccessibilityElement.make(label: rowLabel, traits: .button)
        let scroll = AccessibilityContainer(
            type: .list,
            scrollableContentSize: AccessibilitySize(width: 320, height: 1_200),
            frame: AccessibilityRect(x: 0, y: 80, width: 320, height: 560)
        )
        let membership = InterfaceTree.ScrollMembership(containerPath: containerPath, index: nil)
        return InterfaceObservation.makeForTests(
            elements: [
                headerId: InterfaceTree.Element(
                    heistId: headerId,
                    scrollMembership: membership,
                    element: header
                ),
                rowId: InterfaceTree.Element(
                    heistId: rowId,
                    scrollMembership: membership,
                    element: row
                ),
            ],
            hierarchy: [
                .container(scroll, children: [
                    .element(header, traversalIndex: 0),
                    .element(row, traversalIndex: 1),
                ]),
            ],
            heistIdsByPath: [
                headerPath: headerId,
                rowPath: rowId,
            ],
            elementRefs: [
                headerId: .init(object: headerObject, scrollView: nil),
                rowId: .init(object: rowObject, scrollView: nil),
            ],
            firstResponderHeistId: nil
        )
    }

    func screenChangedBatch() -> AccessibilityNotificationBatch {
        AccessibilityNotificationBatch(
            events: [PendingAccessibilityNotificationEvent(
                sequence: 1,
                kind: .screenChanged,
                timestamp: Date(timeIntervalSince1970: 0),
                notificationData: .none,
                associatedElement: .none,
                provenance: .scoped
            )],
            through: AccessibilityNotificationCursor(sequence: 1),
            scopedScreenChangedThrough: 1,
            gap: nil
        )
    }

    func settleResult(
        _ outcome: SettleOutcome,
        observation: InterfaceObservation,
        tripwireSignal: TheTripwire.TripwireSignal
    ) -> SettleSession.Result {
        SettleSession.Result(
            outcome: outcome,
            events: [],
            finalObservation: SettleSessionFinalObservation(observation: observation),
            elementsByKey: [:],
            tripwireSignal: tripwireSignal
        )
    }

    func tripwireSignal(sequence: UInt64) -> TheTripwire.TripwireSignal {
        TheTripwire.TripwireSignal(
            topmostVC: nil,
            navigation: .empty,
            windowStack: .empty,
            accessibilityNotificationSequence: sequence
        )
    }

    func installSettler(
        signal: @escaping @MainActor () -> TheTripwire.TripwireSignal,
        beforeSettle: @escaping @MainActor () async -> Void = {}
    ) -> @MainActor () -> Int {
        var count = 0
        vault.semanticObservationStream.readTripwireSignal = signal
        vault.semanticObservationStream.settleVisibleObservation = { vault, _, _, baseline, _ in
            count += 1
            await beforeSettle()
            let observation = self.observation(label: "Stable", heistId: "stable")
            vault.observeInterface(observation)
            return self.settleResult(
                .settled(timeMs: count),
                observation: observation,
                tripwireSignal: baseline
            )
        }
        return { count }
    }

    func admittedVisibleObservation() async throws -> Observation.Store.AdmittedObservation {
        let evidence = await vault.semanticObservationStream.admittedVisibleObservation(timeout: 1)
        return try XCTUnwrap(evidence)
    }

    func waitForSettleCount(
        _ expectedCount: Int,
        current: @escaping () -> Int
    ) async {
        for _ in 0..<1_000 {
            guard current() != expectedCount else { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for \(expectedCount) settle sessions")
    }

    func waitForObservationWaiterCount(_ expectedCount: Int) async {
        for _ in 0..<1_000 {
            guard vault.semanticObservationStream.observationWaiterCount != expectedCount else {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for \(expectedCount) observation waiters")
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
