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
    func testPathOnlyScrollReplacementDiscardsPriorDiscoveryAndLiveEvidence() async {
        let oldHeader = NSObject()
        let oldRow = NSObject()
        let newHeader = NSObject()
        let newRow = NSObject()
        let firstEvent = await vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            scrollObservation(
                headerId: "old_header",
                rowLabel: "Orders",
                rowId: "old_row",
                headerObject: oldHeader,
                rowObject: oldRow
            )
        )
        let secondEvent = await vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            scrollObservation(
                headerId: "new_header",
                rowLabel: "Products",
                rowId: "new_row",
                headerObject: newHeader,
                rowObject: newRow
            )
        )

        XCTAssertEqual(secondEvent.generation, firstEvent.generation.advanced())
        XCTAssertEqual(
            secondEvent.continuity,
            .replacement(.inferred(.semanticIdentityDisjoint))
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

        let history = await vault.semanticObservationStream.storeOwner.readLog {
            $0.events(since: discovery.moment)
        }
        let visibleMoment = await vault.semanticObservationStream.latestCommittedObservationMoment(scope: .visible)
        let discoveryMoment = await vault.semanticObservationStream.latestCommittedObservationMoment(scope: .discovery)
        XCTAssertEqual(history, .events([.snapshot(visible)]))
        XCTAssertEqual(visibleMoment, visible.moment)
        XCTAssertEqual(discoveryMoment, discovery.moment)
    }

    func testDiscoveryPublicationCarriesCanonicalGraphAndEvidenceAcrossFulfilledScopes() async throws {
        let visible = AccessibilityElement.make(label: "Visible", traits: .header)
        let offViewport = AccessibilityElement.make(label: "Off Viewport", traits: .button)
        let observation = InterfaceObservation.makeForTests(
            [.init(visible, heistId: "visible")],
            offViewport: [.init(offViewport, heistId: "off_viewport")]
        )

        let discoveryEvent = await vault.semanticObservationStream.commitDiscoveryObservationForTesting(observation)
        let visibleEvent = discoveryEvent

        XCTAssertEqual(discoveryEvent.snapshot.observation.tree.elementIDs, ["visible", "off_viewport"])
        XCTAssertEqual(discoveryEvent.snapshot.observation.captureID, observation.captureID)
        XCTAssertEqual(
            discoveryEvent.trace.captures.last?.interface.projectedElements.compactMap(\.label),
            ["Visible", "Off Viewport"]
        )
        XCTAssertEqual(visibleEvent.snapshot.observation.tree.elementIDs, ["visible", "off_viewport"])
        XCTAssertEqual(visibleEvent.snapshot.observation.captureID, observation.captureID)
        XCTAssertEqual(
            visibleEvent.trace.captures.last?.interface.projectedElements.compactMap(\.label),
            ["Visible", "Off Viewport"]
        )
        XCTAssertEqual(visibleEvent, discoveryEvent)
        XCTAssertEqual(vault.latestObservation.captureID, observation.captureID)
    }

    func testDiscoverySettlementRejectsTripwireChangeBeforeCommit() async {
        let observation = observation(label: "Candidate", heistId: "candidate")
        vault.observeInterface(observation)
        let settledSignal = tripwireSignal(sequence: 1)
        let currentSignal = tripwireSignal(sequence: 2)
        vault.semanticObservationStream.readTripwireSignal = { currentSignal }
        let event = await vault.semanticObservationStream.commitSettledDiscoveryObservation(
            settleResult(
                .settled(timeMs: 1),
                observation: observation,
                tripwireSignal: settledSignal
            ),
            discoveryCommitPolicy: .mergeIntoInterface,
            afterViewportMovement: true
        )

        XCTAssertNil(event)
        XCTAssertNil(vault.interfaceTree.findElement(heistId: "candidate"))
    }

    func testDiscoveryAfterVisibleReplacementUsesGlobalGenerationAndPredecessor() async throws {
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

        XCTAssertEqual(replacementVisible.generation, initialDiscovery.generation.advanced())
        XCTAssertEqual(replacementDiscovery.generation, replacementVisible.generation)
        XCTAssertEqual(replacementDiscovery.previousMoment, replacementVisible.moment)
        XCTAssertEqual(
            replacementDiscovery.trace.captures.first?.hash,
            replacementVisible.trace.captures.last?.hash
        )

        let history = await vault.semanticObservationStream.storeOwner.readLog {
            $0.events(since: initialDiscovery.moment)
        }
        XCTAssertEqual(history, .events([.snapshot(replacementVisible), .snapshot(replacementDiscovery)]))
        guard case .sameGeneration(let previous) = replacementDiscovery.transition else {
            return XCTFail("Expected the skipped discovery scope to cross the retained screen boundary")
        }
        XCTAssertEqual(previous, replacementVisible.moment)
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
