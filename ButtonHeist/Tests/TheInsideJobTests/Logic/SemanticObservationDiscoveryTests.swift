#if canImport(UIKit)
#if DEBUG
import Foundation
import XCTest

import ButtonHeistTestSupport

@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class SemanticObservationDiscoveryTests: SemanticObservationStreamTestCase {
    func testTripwireChangeInvalidatesAdmissionWithoutDiscardingDiscoveryTruth() async {
        let initialSignal = tripwireSignal(sequence: 1)
        vault.semanticObservationStream.readTripwireSignal = { initialSignal }
        _ = await vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            InterfaceObservation.makeForTests(
                elements: [(AccessibilityElement.make(label: "Visible"), "visible")],
                offViewport: [InterfaceObservation.OffViewportEntry(
                    AccessibilityElement.make(label: "Known"),
                    heistId: "known",
                    scrollContainerPath: TreePath([0])
                )]
            )
        )

        let changedSignal = tripwireSignal(sequence: 2)
        vault.semanticObservationStream.readTripwireSignal = { changedSignal }
        let staleAdmission = vault.semanticObservationStream.admittedObservation(
            scope: .visible,
            after: nil
        )

        XCTAssertNil(staleAdmission)
        XCTAssertNotNil(vault.interfaceTree.findElement(heistId: "known"))

        let refreshed = await vault.semanticObservationStream.commitVisibleObservationForTesting(
            InterfaceObservation.makeForTests(
                elements: [(AccessibilityElement.make(label: "Visible"), "visible")]
            )
        )
        XCTAssertNotNil(vault.interfaceTree.findElement(heistId: "known"))
        XCTAssertEqual(refreshed.current.continuity, .sameGeneration)
    }

    func testPathOnlyScrollReplacementDiscardsPriorDiscoveryAndLiveEvidence() async throws {
        let oldHeader = NSObject()
        let oldRow = NSObject()
        let newHeader = NSObject()
        let newRow = NSObject()
        let firstPublication = await vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            scrollObservation(
                headerId: "old_header",
                rowLabel: "Orders",
                rowId: "old_row",
                headerObject: oldHeader,
                rowObject: oldRow
            )
        )
        let secondPublication = await vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            scrollObservation(
                headerId: "new_header",
                rowLabel: "Products",
                rowId: "new_row",
                headerObject: newHeader,
                rowObject: newRow
            )
        )
        let replacementEvents = try retainedEvents(
            after: firstPublication.historyRange.upperBound
        )

        XCTAssertEqual(
            secondPublication.current.continuity,
            .replacement(.inferred(.semanticIdentityDisjoint))
        )
        XCTAssertEqual(replacementEvents, secondPublication.events)
        XCTAssertEqual(
            replacementEvents.filter(\.isScreenChanged).count,
            1
        )
        XCTAssertNil(vault.interfaceTree.findElement(heistId: "old_row"))
        XCTAssertNotNil(vault.interfaceTree.findElement(heistId: "new_row"))
        XCTAssertNil(vault.latestObservation.liveCapture.object(for: "old_row"))
        XCTAssertTrue(vault.latestObservation.liveCapture.object(for: "new_row") === newRow)
    }

    func testDiscoveryPublicationProjectsOneLogAcrossFulfilledScopes() async throws {
        let first = observation(label: "First", heistId: "first")
        let second = observation(label: "Second", heistId: "second")
        let discovery = await vault.semanticObservationStream.commitDiscoveryObservationForTesting(first)
        let visible = await vault.semanticObservationStream.commitVisibleObservationForTesting(second)

        let events = try retainedEvents(after: discovery.historyRange.upperBound)
        XCTAssertEqual(discovery.historyRange.upperBound, visible.historyRange.lowerBound)
        XCTAssertEqual(events, visible.events)
        XCTAssertEqual(events.count, 3)
        guard case .elementsChanged(let departure) = events[0],
              case .screenChanged = events[1],
              case .elementsChanged(let arrival) = events[2] else {
            return XCTFail("Expected departure, screen boundary, and actual arrival")
        }
        XCTAssertTrue(departure.interface.tree.isEmpty)
        XCTAssertEqual(departure.context, discovery.current.snapshot.context)
        XCTAssertEqual(arrival, visible.current.snapshot)
        XCTAssertEqual(discovery.current.scope, .discovery)
        XCTAssertEqual(visible.current.scope, .visible)
    }

    func testDiscoveryPublicationCarriesCanonicalSnapshotAndEvents() async throws {
        let visible = AccessibilityElement.make(label: "Visible", traits: .header)
        let offViewport = AccessibilityElement.make(label: "Off Viewport", traits: .button)
        let observation = InterfaceObservation.makeForTests(
            [.init(visible, heistId: "visible")],
            offViewport: [.init(offViewport, heistId: "off_viewport")]
        )

        let publication = await vault.semanticObservationStream.commitDiscoveryObservationForTesting(observation)
        let snapshot = publication.current.snapshot
        let retained = try retainedEvents(
            after: publication.historyRange.lowerBound
        )

        XCTAssertEqual(
            snapshot.interface.projectedElements.compactMap(\.semantics.assertable.label),
            ["Visible", "Off Viewport"]
        )
        XCTAssertEqual(publication.current.scope, .discovery)
        XCTAssertEqual(publication.events.compactMap(\.snapshot), [snapshot])
        XCTAssertEqual(retained, publication.events)
    }

    func testDiscoverySettlementRejectsHierarchyChangeBeforeCommit() async {
        let observation = observation(label: "Candidate", heistId: "candidate")
        vault.observeInterface(observation)
        let currentSignal = TheTripwire.TripwireSignal(
            topmostVC: ObjectIdentifier(vault),
            navigation: .empty,
            windowStack: .empty,
            accessibilityNotificationSequence: 1
        )
        vault.semanticObservationStream.readTripwireSignal = { currentSignal }
        let admission = vault.semanticObservationStream.admitCurrentObservation(
            vault: vault,
            tripwireSignal: tripwireSignal(sequence: 1),
            discoveryCommitPolicy: .mergeIntoInterface,
            lineage: .viewportMovement
        )

        guard case .failure(.hierarchyChangedDuringCapture) = admission else {
            return XCTFail("Expected hierarchy-changed capture failure")
        }
        XCTAssertNil(vault.interfaceTree.findElement(heistId: "candidate"))
    }

    func testDiscoveryAfterVisibleReplacementContinuesOneOrderedHistory() async throws {
        let initialDiscovery = await vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            observation(label: "First Screen", heistId: "first_screen")
        )
        let replacementVisible = await vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Second Screen", heistId: "second_screen"),
            notificationBatch: screenChangedBatch()
        )
        let replacementDiscovery = await vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            observation(label: "Second Screen", heistId: "second_screen")
        )

        XCTAssertEqual(
            replacementVisible.current.continuity,
            .replacement(.screenChangedNotification)
        )
        XCTAssertEqual(replacementDiscovery.current.continuity, .sameGeneration)
        XCTAssertEqual(
            initialDiscovery.historyRange.upperBound,
            replacementVisible.historyRange.lowerBound
        )
        XCTAssertEqual(
            replacementVisible.historyRange.upperBound,
            replacementDiscovery.historyRange.lowerBound
        )

        let events = try retainedEvents(after: initialDiscovery.historyRange.upperBound)
        XCTAssertEqual(events, replacementVisible.events + replacementDiscovery.events)
        XCTAssertEqual(events.count, 4)
        guard case .elementsChanged(let departure) = events[0],
              case .screenChanged = events[1],
              case .elementsChanged(let arrival) = events[2] else {
            return XCTFail("Expected departure, screen boundary, and arrival")
        }
        XCTAssertTrue(departure.interface.tree.isEmpty)
        XCTAssertEqual(departure.context, initialDiscovery.current.snapshot.context)
        XCTAssertEqual(arrival, replacementVisible.current.snapshot)
        XCTAssertEqual(events[3], .noChange)
        XCTAssertEqual(
            replacementVisible.current.snapshot.interface.projectedElements
                .map(\.semantics),
            replacementDiscovery.current.snapshot.interface.projectedElements
                .map(\.semantics)
        )
    }
}

private extension Observation.Event {
    var isScreenChanged: Bool {
        if case .screenChanged = self { return true }
        return false
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
