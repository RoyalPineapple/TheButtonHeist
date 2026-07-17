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
        let stream = brains.stash.semanticObservationStream
        let committed = observation(label: "Committed", heistId: "committed")
        _ = stream.commitVisibleObservationForTesting(committed)
        let committedHash = brains.stash.interfaceTree.interfaceHash
        let retainedCount = stream.retainedObservationEntries(scope: .visible).count

        let raw = observation(label: "Raw", heistId: "raw")
        brains.stash.nextVisibleRefreshObservationForTesting = raw
        let refreshed = brains.stash.refreshLiveCapture()

        XCTAssertEqual(refreshed?.tree.interfaceHash, raw.tree.interfaceHash)
        XCTAssertEqual(brains.stash.latestObservation.tree.interfaceHash, raw.tree.interfaceHash)
        XCTAssertEqual(brains.stash.interfaceTree.interfaceHash, committedHash)
        XCTAssertNotNil(brains.stash.interfaceTree.findElement(heistId: "committed"))
        XCTAssertNil(brains.stash.interfaceTree.findElement(heistId: "raw"))
        XCTAssertEqual(stream.retainedObservationEntries(scope: .visible).count, retainedCount)

        let diagnostic = observation(label: "Diagnostic", heistId: "diagnostic")
        brains.stash.recordFailedSettleDiagnosticEvidence(diagnostic)

        XCTAssertEqual(
            brains.stash.latestFailedSettleDiagnosticEvidence?.tree.interfaceHash,
            diagnostic.tree.interfaceHash
        )
        XCTAssertEqual(brains.stash.interfaceTree.interfaceHash, committedHash)
        XCTAssertNotNil(brains.stash.interfaceTree.findElement(heistId: "committed"))
        XCTAssertNil(brains.stash.interfaceTree.findElement(heistId: "diagnostic"))
        XCTAssertEqual(stream.retainedObservationEntries(scope: .visible).count, retainedCount)
    }

    func testCommittedObservationAdmitsPreviouslyRawEvidenceToInterfaceTree() {
        let brains = TheBrains(tripwire: TheTripwire())
        let stream = brains.stash.semanticObservationStream
        let raw = observation(label: "Raw", heistId: "raw")
        brains.stash.nextVisibleRefreshObservationForTesting = raw
        _ = brains.stash.refreshLiveCapture()

        XCTAssertTrue(brains.stash.interfaceTree.orderedElements.isEmpty)

        let event = stream.commitVisibleObservationForTesting(raw)

        XCTAssertNotNil(event.settledCapture)
        XCTAssertNotNil(brains.stash.interfaceTree.findElement(heistId: "raw"))
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
