#if canImport(UIKit)
#if DEBUG
import UIKit
import XCTest

@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class RawParserEvidenceAdmissionTests: XCTestCase {
    func testRawParserAndDiagnosticEvidenceCannotMutateCommittedInterfaceTree() {
        let brains = TheBrains(tripwire: TheTripwire())
        let stream = brains.vault.semanticObservationStream
        let committed = observation(label: "Committed", heistId: "committed")
        _ = stream.commitVisibleObservationForTesting(committed)
        let committedHash = brains.vault.interfaceTree.interfaceHash
        let retainedCount = stream.retainedObservationEntries(scope: .visible).count

        let raw = observation(label: "Raw", heistId: "raw")
        brains.vault.nextVisibleRefreshObservationForTesting = raw
        let refreshed = brains.vault.refreshLiveCapture()

        XCTAssertEqual(refreshed?.tree.interfaceHash, raw.tree.interfaceHash)
        XCTAssertEqual(brains.vault.latestObservation.tree.interfaceHash, raw.tree.interfaceHash)
        XCTAssertEqual(brains.vault.interfaceTree.interfaceHash, committedHash)
        XCTAssertNotNil(brains.vault.interfaceTree.findElement(heistId: "committed"))
        XCTAssertNil(brains.vault.interfaceTree.findElement(heistId: "raw"))
        XCTAssertEqual(stream.retainedObservationEntries(scope: .visible).count, retainedCount)

        let diagnostic = observation(label: "Diagnostic", heistId: "diagnostic")
        brains.vault.recordFailedSettleDiagnosticEvidence(diagnostic)

        XCTAssertEqual(
            brains.vault.latestFailedSettleDiagnosticEvidence?.tree.interfaceHash,
            diagnostic.tree.interfaceHash
        )
        XCTAssertEqual(brains.vault.interfaceTree.interfaceHash, committedHash)
        XCTAssertNotNil(brains.vault.interfaceTree.findElement(heistId: "committed"))
        XCTAssertNil(brains.vault.interfaceTree.findElement(heistId: "diagnostic"))
        XCTAssertEqual(stream.retainedObservationEntries(scope: .visible).count, retainedCount)
    }

    func testCommittedObservationAdmitsPreviouslyRawEvidenceToInterfaceTree() {
        let brains = TheBrains(tripwire: TheTripwire())
        let stream = brains.vault.semanticObservationStream
        let raw = observation(label: "Raw", heistId: "raw")
        brains.vault.nextVisibleRefreshObservationForTesting = raw
        _ = brains.vault.refreshLiveCapture()

        XCTAssertTrue(brains.vault.interfaceTree.orderedElements.isEmpty)

        let event = stream.commitVisibleObservationForTesting(raw)

        XCTAssertNotNil(event.settledCapture)
        XCTAssertNotNil(brains.vault.interfaceTree.findElement(heistId: "raw"))
        XCTAssertEqual(stream.retainedObservationEntries(scope: .visible).count, 1)
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
