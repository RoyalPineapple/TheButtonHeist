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
        let committedPublication = await stream.commitVisibleObservationForTesting(committed)
        let committedHash = brains.vault.interfaceTree.interfaceHash

        let raw = observation(label: "Raw", heistId: "raw")
        visibleObservationSource.observation = raw
        let refreshed = brains.vault.refreshLiveCapture()

        XCTAssertEqual(refreshed?.tree.interfaceHash, raw.tree.interfaceHash)
        XCTAssertEqual(brains.vault.latestObservation.tree.interfaceHash, raw.tree.interfaceHash)
        XCTAssertEqual(brains.vault.interfaceTree.interfaceHash, committedHash)
        XCTAssertNotNil(brains.vault.interfaceTree.findElement(heistId: "committed"))
        XCTAssertNil(brains.vault.interfaceTree.findElement(heistId: "raw"))
        let retainedAfterRefresh = try await stream.stateOwner
            .events(after: committedPublication.historyRange.upperBound)
            .get()
        let currentAfterRefresh = await stream.stateOwner.current()
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
        _ = brains.vault.refreshLiveCapture()

        XCTAssertTrue(brains.vault.interfaceTree.orderedElements.isEmpty)

        let boundary = await stream.stateOwner.historyEndIndex()
        let publication = await stream.commitVisibleObservationForTesting(raw)

        XCTAssertEqual(publication.historyRange.lowerBound, boundary)
        XCTAssertNotNil(brains.vault.interfaceTree.findElement(heistId: "raw"))
        let retained = try await stream.stateOwner.events(after: boundary).get()
        let current = await stream.stateOwner.current()
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
