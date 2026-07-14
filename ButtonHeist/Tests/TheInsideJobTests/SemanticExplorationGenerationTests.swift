#if canImport(UIKit)
#if DEBUG
import XCTest
import UIKit

@testable import AccessibilitySnapshotParser
import ButtonHeistSupport
@testable import TheInsideJob
import ThePlans
@testable import TheScore

@MainActor
final class SemanticExplorationGenerationTests: XCTestCase {

    func testSameGenerationPagesUnion() {
        var exploration = Navigation.SemanticExploration(
            baseline: .interfaceMemory(
                screen(header: "Catalog", entries: [("Visible", .staticText, "visible")])
            )
        )

        exploration.absorb(screen(header: "Catalog", entries: [("Discovered", .button, "discovered")]))

        XCTAssertNotNil(exploration.screen.findElement(heistId: "visible"))
        XCTAssertNotNil(exploration.screen.findElement(heistId: "discovered"))
    }

    func testScreenReplacementRemovesOldOnlyNodes() {
        var exploration = Navigation.SemanticExploration(
            baseline: .interfaceMemory(
                screen(header: "Home", entries: [("Old Action", .button, "old_action")])
            )
        )

        exploration.absorb(screen(header: "Settings", entries: [("New Action", .button, "new_action")]))

        XCTAssertNil(exploration.screen.findElement(heistId: "old_action"))
        XCTAssertNotNil(exploration.screen.findElement(heistId: "new_action"))
    }

    func testPlannedScrollDoesNotInferReplacementFromViewportShape() throws {
        var exploration = Navigation.SemanticExploration(
            baseline: .interfaceMemory(
                screen(header: "Home", entries: [("Old Action", .button, "old_action")])
            )
        )
        let notificationBus = AccessibilityNotificationBus()
        let window = notificationBus.beginActionWindow()
        defer { window.cancel() }

        let classification = exploration.absorbScrolledPage(
            screen(header: "Settings", entries: [("New Action", .button, "new_action")]),
            notificationBatch: try XCTUnwrap(window.capture())
        )

        XCTAssertEqual(classification, .sameGeneration)
        XCTAssertNotNil(exploration.screen.findElement(heistId: "old_action"))
        XCTAssertNotNil(exploration.screen.findElement(heistId: "new_action"))
    }

    func testPlannedScrollWithoutNotificationBatchDoesNotInferReplacementFromViewportShape() {
        var exploration = Navigation.SemanticExploration(
            baseline: .interfaceMemory(
                screen(header: "Home", entries: [("Old Action", .staticText, "old_action")])
            )
        )

        let classification = exploration.absorbScrolledPage(
            screen(header: "Settings", entries: [("New Action", .button, "new_action")]),
            notificationBatch: nil
        )

        XCTAssertEqual(classification, .sameGeneration)
        XCTAssertNotNil(exploration.screen.findElement(heistId: "old_action"))
        XCTAssertNotNil(exploration.screen.findElement(heistId: "new_action"))
    }

    func testPlannedScrollUsesScopedScreenChangedAsReplacementEvidence() throws {
        var exploration = Navigation.SemanticExploration(
            baseline: .interfaceMemory(
                screen(header: "Home", entries: [("Old Action", .button, "old_action")])
            )
        )
        let notificationBus = AccessibilityNotificationBus()
        let window = notificationBus.beginActionWindow()
        defer { window.cancel() }
        notificationBus.recordForTesting(
            code: UInt32(UIAccessibility.Notification.screenChanged.rawValue),
            notificationData: .none,
            associatedElement: .none
        )

        let classification = exploration.absorbScrolledPage(
            screen(header: "Settings", entries: [("New Action", .button, "new_action")]),
            notificationBatch: try XCTUnwrap(window.capture())
        )

        XCTAssertEqual(classification, .screenChangedNotification)
        XCTAssertNil(exploration.screen.findElement(heistId: "old_action"))
        XCTAssertNotNil(exploration.screen.findElement(heistId: "new_action"))
    }

    func testExploredReplacementRemainsAuthoritativeWithElementChangedNotification() throws {
        let brains = TheBrains(tripwire: TheTripwire())
        let oldScreen = screen(
            header: "Home",
            entries: [("Old Action", .button, "old_action")]
        )
        let oldEvent = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(oldScreen)
        let replacement = screen(
            header: "Settings",
            entries: [("New Action", .button, "new_action")]
        )
        brains.stash.recordParsedObservedEvidence(replacement)
        var exploration = Navigation.SemanticExploration(baseline: .interfaceMemory(oldScreen))
        exploration.absorb(replacement)
        let explored = exploration.finish(startTime: CACurrentMediaTime())
        let actionWindow = brains.stash.accessibilityNotifications.beginActionWindow()
        defer { actionWindow.cancel() }
        brains.stash.accessibilityNotifications.recordForTesting(
            code: 1001,
            notificationData: .none,
            associatedElement: .none
        )
        let notificationBatch = try XCTUnwrap(actionWindow.capture())

        let replacementEvent = try XCTUnwrap(
            brains.stash.semanticObservationStream.commitExploredDiscoveryObservation(
                explored,
                notificationBatch: notificationBatch
            )
        )

        XCTAssertNotEqual(replacementEvent.generation, oldEvent.generation)
        XCTAssertNil(brains.stash.interfaceTree.findElement(heistId: "old_action"))
        XCTAssertNotNil(brains.stash.interfaceTree.findElement(heistId: "new_action"))
    }

    func testDiagnosticBaselineCannotBecomeCommittedTarget() {
        let brains = TheBrains(tripwire: TheTripwire())
        let diagnostic = screen(
            header: "Checkout",
            entries: [("Unsettled Purchase", .button, "unsettled_purchase")]
        )
        brains.stash.recordFailedSettleDiagnosticEvidence(diagnostic)
        var exploration = Navigation.SemanticExploration(baseline: .interfaceMemory(diagnostic))
        exploration.absorb(screen(header: "Receipt", entries: [("Done", .button, "done")]))

        brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(exploration.screen)

        let staleTarget = literalTarget(ElementPredicate.label("Unsettled Purchase"))
        guard case .notFound = brains.stash.resolveTarget(staleTarget) else {
            return XCTFail("Failed-settle diagnostic element became committed targetable state")
        }
        XCTAssertNotNil(brains.stash.resolveTarget(literalTarget(ElementPredicate.label("Done"))).resolved)
    }

    func testScreenReplacementResetsGraphWithoutResettingDiscoveryBound() {
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

        exploration.absorb(screen(header: "Settings"))

        XCTAssertTrue(exploration.manifest.exploredScrollPaths.isEmpty)
        XCTAssertTrue(exploration.manifest.pendingScrollPaths.isEmpty)
        XCTAssertTrue(exploration.manifest.scrollCountByContainerPath.isEmpty)
        XCTAssertEqual(exploration.manifest.scrollCount, 1)
        XCTAssertEqual(exploration.manifest.maxScrollsPerContainer, 2)
        XCTAssertEqual(exploration.manifest.maxScrollsPerDiscovery, 2)
        XCTAssertNil(exploration.manifest.recordScrollAttempt(in: newPath))
        XCTAssertEqual(
            exploration.manifest.recordScrollAttempt(in: newPath),
            .discoveryScrollLimit
        )
    }

    func testScreenReplacementFinishesContainerScanWithoutRestore() {
        var driver = StateDriver(
            initial: Navigation.ScrollContainerScanState.idle,
            machine: Navigation.ScrollContainerScanMachine()
        )
        _ = driver.send(.begin)

        let change = driver.send(.scanCompleted(.screenReplaced))

        XCTAssertEqual(change.effects, [.finish(.screenReplaced)])
        XCTAssertEqual(driver.state, .finished(.screenReplaced))
    }

    private func screen(
        header: String,
        entries: [(label: String, traits: UIAccessibilityTraits, heistId: HeistId)] = []
    ) -> InterfaceObservation {
        let headerEntry = InterfaceObservation.TestEntry(
            AccessibilityElement.make(label: header, traits: .header),
            heistId: HeistId(rawValue: "screen_header")
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
