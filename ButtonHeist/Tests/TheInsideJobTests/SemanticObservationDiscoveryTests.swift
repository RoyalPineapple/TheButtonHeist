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
    func testPathOnlyScrollReplacementDiscardsPriorDiscoveryAndLiveEvidence() {
        let oldHeader = NSObject()
        let oldRow = NSObject()
        let newHeader = NSObject()
        let newRow = NSObject()
        let firstEvent = vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            scrollObservation(
                headerId: "old_header",
                rowLabel: "Orders",
                rowId: "old_row",
                headerObject: oldHeader,
                rowObject: oldRow
            )
        )
        let secondEvent = vault.semanticObservationStream.commitDiscoveryObservationForTesting(
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

    func testDiscoveryPublicationMaintainsIndependentScopeLineage() throws {
        let first = observation(label: "First", heistId: "first")
        let second = observation(label: "Second", heistId: "second")
        _ = vault.semanticObservationStream.commitDiscoveryObservationForTesting(first)
        _ = vault.semanticObservationStream.commitVisibleObservationForTesting(second)

        let visibleEntries = vault.semanticObservationStream.retainedObservationEntries(scope: .visible)
        let discoveryEntries = vault.semanticObservationStream.retainedObservationEntries(scope: .discovery)

        XCTAssertEqual(visibleEntries.count, 2)
        XCTAssertEqual(discoveryEntries.count, 1)
        XCTAssertEqual(visibleEntries.map(\.cursor.scope), [.visible, .visible])
        XCTAssertEqual(discoveryEntries.map(\.cursor.scope), [.discovery])
        XCTAssertEqual(
            vault.semanticObservationStream.latestCommittedObservationCursor(scope: .visible),
            visibleEntries.last?.cursor
        )
        XCTAssertEqual(
            vault.semanticObservationStream.latestCommittedObservationCursor(scope: .discovery),
            discoveryEntries.last?.cursor
        )
    }

    func testDiscoveryPublicationCarriesCanonicalGraphAndEvidenceAcrossFulfilledScopes() throws {
        let visible = AccessibilityElement.make(label: "Visible", traits: .header)
        let offViewport = AccessibilityElement.make(label: "Off Viewport", traits: .button)
        let observation = InterfaceObservation.makeForTests(
            [.init(visible, heistId: "visible")],
            offViewport: [.init(offViewport, heistId: "off_viewport")]
        )

        let discoveryEvent = vault.semanticObservationStream.commitDiscoveryObservationForTesting(observation)
        let visibleEvent = try XCTUnwrap(
            vault.semanticObservationStream.retainedObservationEntries(scope: .visible).last?.event
        )

        XCTAssertEqual(discoveryEvent.settledObservation.observation.tree.elementIDs, ["visible", "off_viewport"])
        XCTAssertEqual(discoveryEvent.settledObservation.observation.captureID, observation.captureID)
        XCTAssertEqual(
            discoveryEvent.trace.captures.last?.interface.projectedElements.compactMap(\.label),
            ["Visible", "Off Viewport"]
        )
        XCTAssertEqual(visibleEvent.settledObservation.observation.tree.elementIDs, ["visible", "off_viewport"])
        XCTAssertEqual(visibleEvent.settledObservation.observation.captureID, observation.captureID)
        XCTAssertEqual(
            visibleEvent.trace.captures.last?.interface.projectedElements.compactMap(\.label),
            ["Visible", "Off Viewport"]
        )
        XCTAssertEqual(vault.latestObservation.captureID, observation.captureID)
    }

    func testDiscoverySettlementRejectsTripwireChangeBeforeCommit() {
        let observation = observation(label: "Candidate", heistId: "candidate")
        vault.observeInterface(observation)
        let settledSignal = tripwireSignal(sequence: 1)
        let currentSignal = tripwireSignal(sequence: 2)
        vault.semanticObservationStream.readTripwireSignal = { currentSignal }
        let event = vault.semanticObservationStream.commitSettledDiscoveryObservation(
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

    func testDiscoveryAfterVisibleReplacementUsesGlobalGenerationAndScopedPredecessor() throws {
        let initialDiscovery = vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            observation(label: "First Screen", heistId: "first_screen")
        )
        let replacementVisible = vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Second Screen", heistId: "second_screen"),
            notificationBatch: screenChangedBatch()
        )
        let replacementDiscovery = vault.semanticObservationStream.commitDiscoveryObservationForTesting(
            observation(label: "Second Screen", heistId: "second_screen")
        )

        XCTAssertEqual(replacementVisible.generation, initialDiscovery.generation.advanced())
        XCTAssertEqual(replacementDiscovery.generation, replacementVisible.generation)
        XCTAssertEqual(replacementDiscovery.previousCursor, initialDiscovery.cursor)
        XCTAssertEqual(
            replacementDiscovery.trace.captures.first?.hash,
            initialDiscovery.trace.captures.last?.hash
        )

        let discoveryEntries = vault.semanticObservationStream.retainedObservationEntries(scope: .discovery)
        XCTAssertEqual(discoveryEntries.count, 2)
        guard case .screenBoundary(let transition) = discoveryEntries[1].transition else {
            return XCTFail("Expected the skipped discovery scope to cross the retained screen boundary")
        }
        XCTAssertEqual(transition.previousCursor, discoveryEntries[0].cursor)
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
