#if canImport(UIKit)
#if DEBUG
import UIKit
import XCTest

@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class RawParserEvidenceAdmissionTests: XCTestCase {
    func testRawParserAndDiagnosticEvidenceCannotMutateCommittedInterfaceTree() async {
        let visibleObservationSource = VisibleObservationSourceFixture()
        let brains = TheBrains(
            tripwire: TheTripwire(),
            visibleObservationSource: visibleObservationSource.capture
        )
        let stream = brains.vault.semanticObservationStream
        let committed = observation(label: "Committed", heistId: "committed")
        let committedEvent = await stream.commitVisibleObservationForTesting(committed)
        let committedHash = brains.vault.interfaceTree.interfaceHash

        let raw = observation(label: "Raw", heistId: "raw")
        visibleObservationSource.observation = raw
        let refreshed = brains.vault.refreshLiveCapture()

        XCTAssertEqual(refreshed?.tree.interfaceHash, raw.tree.interfaceHash)
        XCTAssertEqual(brains.vault.latestObservation.tree.interfaceHash, raw.tree.interfaceHash)
        XCTAssertEqual(brains.vault.interfaceTree.interfaceHash, committedHash)
        XCTAssertNotNil(brains.vault.interfaceTree.findElement(heistId: "committed"))
        XCTAssertNil(brains.vault.interfaceTree.findElement(heistId: "raw"))
        let retainedAfterRefresh = await stream.latestCommittedEvent()
        XCTAssertEqual(retainedAfterRefresh, committedEvent)

        let diagnostic = observation(label: "Diagnostic", heistId: "diagnostic")
        await brains.vault.recordFailedSettleDiagnosticEvidence(diagnostic)

        XCTAssertEqual(
            brains.vault.latestFailedSettleDiagnosticEvidence?.tree.interfaceHash,
            diagnostic.tree.interfaceHash
        )
        XCTAssertEqual(brains.vault.interfaceTree.interfaceHash, committedHash)
        XCTAssertNotNil(brains.vault.interfaceTree.findElement(heistId: "committed"))
        XCTAssertNil(brains.vault.interfaceTree.findElement(heistId: "diagnostic"))
        let retainedAfterDiagnostic = await stream.latestCommittedEvent()
        XCTAssertEqual(retainedAfterDiagnostic, committedEvent)
    }

    func testCommittedObservationAdmitsPreviouslyRawEvidenceToInterfaceTree() async {
        let visibleObservationSource = VisibleObservationSourceFixture()
        let brains = TheBrains(
            tripwire: TheTripwire(),
            visibleObservationSource: visibleObservationSource.capture
        )
        let stream = brains.vault.semanticObservationStream
        let raw = observation(label: "Raw", heistId: "raw")
        visibleObservationSource.observation = raw
        _ = brains.vault.refreshLiveCapture()

        XCTAssertTrue(brains.vault.interfaceTree.orderedElements.isEmpty)

        let event = await stream.commitVisibleObservationForTesting(raw)

        XCTAssertNotNil(event.moment)
        XCTAssertNotNil(brains.vault.interfaceTree.findElement(heistId: "raw"))
        let committedEvent = await stream.latestCommittedEvent()
        XCTAssertEqual(committedEvent, event)
    }

    private func observation(label: String, heistId: HeistId) -> InterfaceObservation {
        .makeForTests([
            .init(
                .make(
                    label: label,
                    traits: .button,
                    respondsToUserInteraction: true
                ),
                heistId: heistId
            ),
        ])
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
