#if canImport(UIKit)
#if DEBUG
import Foundation
import XCTest

import ButtonHeistTestSupport

@testable import AccessibilitySnapshotParser
@_spi(ButtonHeistInternals) @testable import ThePlans
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

    func tripwireSignal(sequence: UInt64) -> TheTripwire.TripwireSignal {
        TheTripwire.TripwireSignal(
            topmostVC: nil,
            navigation: .empty,
            windowStack: .empty,
            accessibilityNotificationSequence: sequence
        )
    }

    /// Counts visible readings and makes the tree stable, so a test can ask
    /// whether a second consumer started its own reading or joined the first.
    func installSettler(
        signal: @escaping @MainActor () -> TheTripwire.TripwireSignal,
        beforeSettle: @escaping @MainActor () async -> Void = {}
    ) -> @MainActor () -> Int {
        var count = 0
        vault.semanticObservationStream.readTripwireSignal = signal
        vault.semanticObservationStream.beforeVisibleReading = { [self] in
            count += 1
            await beforeSettle()
            vault.observeInterface(observation(label: "Stable", heistId: "stable"))
        }
        return { count }
    }

    /// A tree that moved and then stopped, as the two recorded events that say so.
    struct Reading {
        let changed: TheVault.State.ReadObservation
        let settled: TheVault.State.ReadObservation
    }

    /// A reading of a tree holding one header, that moved and then went quiet.
    func commitSettling(label: String) async -> Reading {
        await commitSettling(
            observation(label: label, heistId: HeistId(rawValue: label.lowercased()))
        )
    }

    /// A reading of `observation`, then the quiet reading that follows it.
    ///
    /// Two commits of the same tree: the second finds nothing changed, which is
    /// the only proof of stillness there is. A run needs it to settle, so the
    /// pair is what "the tree moved and then stopped" looks like as events.
    func commitSettling(_ observation: InterfaceObservation) async -> Reading {
        let changed = await vault.semanticObservationStream
            .commitVisibleObservationForTesting(observation)
        let settled = await vault.semanticObservationStream
            .commitVisibleObservationForTesting(observation)
        precondition(
            changed.current.isChange && !settled.current.isChange,
            "Second reading must be quiet"
        )
        return Reading(changed: changed, settled: settled)
    }

    func admittedVisibleObservation() async throws -> TheVault.State.AdmittedObservation {
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
