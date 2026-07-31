#if canImport(UIKit)
#if DEBUG
import UIKit
import XCTest

@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class RawParserEvidenceAdmissionTests: XCTestCase {
    func testRawParserEvidenceCannotMutateCommittedInterfaceTree() async throws {
        let visibleObservationSource = VisibleObservationSourceFixture()
        let brains = TheBrains(
            tripwire: TheTripwire(),
            visibleObservationSource: visibleObservationSource.capture
        )
        let stream = brains.vault.semanticObservationStream
        let committed = observation(label: "Committed", heistId: "committed")
        let committedReceipt = await capturePublication(in: brains.vault) {
            await stream.commitVisibleObservationForTesting(committed)
        }
        let committedPublication = committedReceipt.publication
        let committedElementIDs = brains.vault.interfaceTree.elementIDs

        let raw = observation(label: "Raw", heistId: "raw")
        visibleObservationSource.observation = raw
        let captured = visibleObservationSource.capture(from: brains.vault)

        XCTAssertEqual(captured?.tree.elementIDs, raw.tree.elementIDs)
        XCTAssertEqual(brains.vault.interfaceTree.elementIDs, committedElementIDs)
        XCTAssertNotNil(brains.vault.interfaceTree.findElement(heistId: "committed"))
        XCTAssertNil(brains.vault.interfaceTree.findElement(heistId: "raw"))
        let retainedAfterRefresh = try stream
            .events(after: committedReceipt.historyRange.upperBound)
            .get()
        let currentAfterRefresh = brains.vault.state.current
        XCTAssertTrue(retainedAfterRefresh.isEmpty)
        XCTAssertEqual(currentAfterRefresh, committedPublication.current)
    }

    func testCommittedObservationAdmitsPreviouslyRawEvidenceToInterfaceTree() async throws {
        let visibleObservationSource = VisibleObservationSourceFixture()
        let brains = TheBrains(
            tripwire: TheTripwire(),
            visibleObservationSource: visibleObservationSource.capture
        )
        let stream = brains.vault.semanticObservationStream
        let raw = observation(label: "Raw", heistId: "raw")
        visibleObservationSource.observation = raw
        let captured = try XCTUnwrap(visibleObservationSource.capture(from: brains.vault))

        XCTAssertTrue(brains.vault.interfaceTree.orderedElements.isEmpty)

        let boundary = brains.vault.state.history.endIndex
        let receipt = await capturePublication(in: brains.vault) {
            await stream.commitVisibleObservationForTesting(captured)
        }
        let publication = receipt.publication

        XCTAssertEqual(receipt.historyRange.lowerBound, boundary)
        XCTAssertNotNil(brains.vault.interfaceTree.findElement(heistId: "raw"))
        let retained = try stream.events(after: receipt.historyRange.lowerBound).get()
        let current = brains.vault.state.current
        XCTAssertEqual(retained, publication.events)
        XCTAssertEqual(current, publication.current)
        XCTAssertEqual(
            publication.events.compactMap(\.snapshot),
            [publication.current.snapshot]
        )
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
