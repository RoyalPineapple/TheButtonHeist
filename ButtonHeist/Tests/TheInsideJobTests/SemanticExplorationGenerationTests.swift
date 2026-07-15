#if canImport(UIKit)
#if DEBUG
import XCTest
import UIKit

@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class SemanticExplorationGenerationTests: XCTestCase {

    func testCommittedDiscoveryPagesMergeWithinGeneration() {
        let brains = TheBrains(tripwire: TheTripwire())

        let first = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            screen(header: "Catalog", entries: [("Visible", .staticText, "visible")])
        )
        let second = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            screen(header: "Catalog", entries: [("Discovered", .button, "discovered")])
        )

        XCTAssertEqual(second.generation, first.generation)
        XCTAssertNotNil(brains.stash.interfaceTree.findElement(heistId: "visible"))
        XCTAssertNotNil(brains.stash.interfaceTree.findElement(heistId: "discovered"))
    }

    func testCommittedDiscoveryReplacementRemovesPriorGeneration() {
        let brains = TheBrains(tripwire: TheTripwire())
        let before = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            screen(header: "Home", entries: [("Old Action", .button, "old_action")])
        )
        let actionWindow = brains.stash.accessibilityNotifications.beginActionWindow()
        defer { actionWindow.cancel() }
        brains.stash.accessibilityNotifications.recordForTesting(
            code: UInt32(UIAccessibility.Notification.screenChanged.rawValue),
            notificationData: .none,
            associatedElement: .none
        )
        let after = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            screen(header: "Settings", entries: [("New Action", .button, "new_action")]),
            notificationBatch: actionWindow.capture()
        )

        XCTAssertEqual(after.generation, before.generation.advanced())
        XCTAssertNil(brains.stash.interfaceTree.findElement(heistId: "old_action"))
        XCTAssertNotNil(brains.stash.interfaceTree.findElement(heistId: "new_action"))
    }

    func testDiagnosticEvidenceCannotBecomeCommittedTarget() {
        let brains = TheBrains(tripwire: TheTripwire())
        brains.stash.recordFailedSettleDiagnosticEvidence(
            screen(
                header: "Checkout",
                entries: [("Unsettled Purchase", .button, "unsettled_purchase")]
            )
        )
        brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            screen(header: "Receipt", entries: [("Done", .button, "done")])
        )

        XCTAssertNil(brains.stash.interfaceTree.findElement(heistId: "unsettled_purchase"))
        XCTAssertNotNil(brains.stash.interfaceTree.findElement(heistId: "done"))
    }

    func testScreenReplacementResetsManifestWithoutResettingDiscoveryBound() {
        let oldPath = TreePath([0])
        let newPath = TreePath([1])
        var exploration = Navigation.SemanticExploration(
            baseline: .interfaceMemory(screen(header: "Home")),
            maxScrollsPerContainer: 2,
            maxScrollsPerDiscovery: 2
        )
        exploration.manifest.addPendingScrollPaths([oldPath])
        exploration.manifest.markExplored(oldPath)
        XCTAssertNil(exploration.manifest.recordScrollAttempt(in: oldPath))

        exploration.recordCommittedObservation(
            continuity: .replacement(.screenChangedNotification),
            scrollableContainers: []
        )

        XCTAssertTrue(exploration.manifest.exploredScrollPaths.isEmpty)
        XCTAssertTrue(exploration.manifest.pendingScrollPaths.isEmpty)
        XCTAssertTrue(exploration.manifest.scrollCountByContainerPath.isEmpty)
        XCTAssertEqual(exploration.manifest.scrollCount, 1)
        XCTAssertEqual(exploration.manifest.maxScrollsPerContainer, 2)
        XCTAssertEqual(exploration.manifest.maxScrollsPerDiscovery, 2)
        XCTAssertNil(exploration.manifest.recordScrollAttempt(in: newPath))
        XCTAssertEqual(exploration.manifest.recordScrollAttempt(in: newPath), .discoveryScrollLimit)
    }

    func testCurrentViewportBaselineReplacesOnceThenMergesDiscoveryPages() {
        var exploration = Navigation.SemanticExploration(
            baseline: .currentViewport(screen(header: "Catalog"))
        )

        XCTAssertEqual(exploration.discoveryCommitPolicy, .replaceInterface)

        exploration.recordCommittedObservation(
            continuity: .sameGeneration,
            scrollableContainers: []
        )

        XCTAssertEqual(exploration.discoveryCommitPolicy, .mergeIntoInterface)
    }

    private func screen(
        header: String,
        entries: [(label: String, traits: UIAccessibilityTraits, heistId: HeistId)] = []
    ) -> InterfaceObservation {
        let headerEntry = InterfaceObservation.TestEntry(
            AccessibilityElement.make(label: header, traits: .header),
            heistId: "screen_header"
        )
        let elementEntries = entries.map { entry in
            InterfaceObservation.TestEntry(
                AccessibilityElement.make(label: entry.label, traits: entry.traits),
                heistId: entry.heistId
            )
        }
        return InterfaceObservation.makeForTests([headerEntry] + elementEntries)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
