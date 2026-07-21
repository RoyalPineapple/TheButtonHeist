#if canImport(UIKit)
import ButtonHeistSupport
import XCTest
import ThePlans
import UIKit
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

@MainActor
extension TheBrainsScrollTests {

    func testInflationRecordsDiscoveredOriginWhenExplorationFindsTarget() async throws {
        let baselineObject = retainedLiveObject()
        brains.vault.installObservationForTesting(.makeForTests([
            .init(makeElement(label: "Home"), heistId: "home", object: baselineObject),
        ]))
        let discoveredFrame = CGRect(x: 40, y: 120, width: 240, height: 44)
        let discoveredElement = makeElement(
            label: "Discovered",
            traits: .button,
            shape: .frame(AccessibilityRect(discoveredFrame))
        )
        let discoveredObject = retainLiveObject(makeButton(label: "Discovered", frame: discoveredFrame))
        let discoveredScreen = InterfaceObservation.makeForTests([
            .init(
                discoveredElement,
                heistId: "discovered_button",
                object: discoveredObject
            ),
        ])
        visibleObservationSource.observation = discoveredScreen
        brains.navigation.elementInflation.exploration.discoverTarget = { _ in
            self.brains.vault.observeInterface(discoveredScreen)
            let event = self.brains.vault.semanticObservationStream
                .commitDiscoveryObservationForTesting(discoveredScreen)
            return Navigation.InterfaceExplorationResult(
                event: event,
                progress: .init(),
                didMoveViewport: true
            )
        }
        defer {
            brains.navigation.elementInflation.exploration.discoverTarget = { _ in nil }
        }

        let result = await brains.navigation.elementInflation.inflate(
            for: try resolvedTarget(.label("Discovered").and(.traits([.button]))),
            method: .activate
        )

        guard case .inflated(let inflatedTarget) = result else {
            return XCTFail("Expected discovered target inflation, got \(result)")
        }
        XCTAssertTrue(inflatedTarget.liveTarget.object === discoveredObject)
        XCTAssertEqual(
            inflatedTarget.resolution,
            ActionSubjectResolution(origin: .discovered, adjustments: [.semanticReveal])
        )
    }

    func testInflationUsesNextSettledVisibleEvidenceForCommittedTarget() async throws {
        brains.stopSemanticObservation()
        let targetId: HeistId = "coke_button"
        let staleKnownTarget = makeElement(label: "Coke", traits: .button)
        installScreenWithOffViewportEntry(
            liveHierarchy: [(makeElement(label: "Drink", traits: .header), "drink_header")],
            offViewport: [InterfaceObservation.OffViewportEntry(staleKnownTarget, heistId: targetId)]
        )

        let visibleFrame = CGRect(x: 40, y: 217, width: 300, height: 96)
        let visibleTarget = AccessibilityElement.make(
            label: "Coke",
            traits: .button,
            frame: visibleFrame
        )
        let visibleObject = NSObject()
        let visibleScreen = InterfaceObservation.makeForTests([
            InterfaceObservation.TestEntry(
                visibleTarget,
                heistId: targetId,
                object: visibleObject
            )
        ])
        brains.navigation.elementInflation.exploration.discoverTarget = { _ in nil }
        var revealAttempts = 0
        brains.navigation.elementInflation.exploration.revealKnownTarget = { _ in
            revealAttempts += 1
            return nil
        }
        defer {
            brains.navigation.elementInflation.exploration.discoverTarget = { _ in nil }
            brains.navigation.elementInflation.exploration.revealKnownTarget = { _ in nil }
        }

        let target = try resolvedTarget(AccessibilityTarget.label("Coke").and(.traits([.button])))
        let resultBox = InflationResultBox()
        let inflation = Task { @MainActor in
            resultBox.value = await self.brains.navigation.elementInflation.inflate(
                for: target,
                method: .activate
            )
        }
        await waitForSettledSemanticWaiter()
        visibleObservationSource.observation = visibleScreen
        brains.vault.semanticObservationStream.commitVisibleObservationForTesting(visibleScreen)
        await inflation.value

        guard case .inflated(let inflatedTarget)? = resultBox.value else {
            return XCTFail("Expected visible target inflation, got \(String(describing: resultBox.value))")
        }
        XCTAssertEqual(revealAttempts, 0)
        XCTAssertEqual(inflatedTarget.treeElement.heistId, targetId)
        XCTAssertEqual(inflatedTarget.liveTarget.activationPoint.x, visibleFrame.midX, accuracy: 0.01)
        XCTAssertEqual(inflatedTarget.liveTarget.activationPoint.y, visibleFrame.midY, accuracy: 0.01)
    }

    func testRevealRetryResolvesTargetFromNextSettledObservation() async throws {
        brains.stopSemanticObservation()
        let targetId: HeistId = "coke_button"
        let overviewVisible = makeElement(label: "Combo Overview", traits: .header)
        let staleCoke = makeElement(label: "Coke", traits: .button)
        installScreenWithOffViewportEntry(
            liveHierarchy: [(overviewVisible, "combo_overview_header")],
            offViewport: [InterfaceObservation.OffViewportEntry(staleCoke, heistId: targetId)]
        )

        let arrivedFrame = CGRect(
            x: ElementInflation.interactionComfortZone.midX - 150,
            y: ElementInflation.interactionComfortZone.midY - 48,
            width: 300,
            height: 96
        )
        let arrivedCoke = AccessibilityElement.make(
            label: "Coke",
            traits: .button,
            frame: arrivedFrame
        )
        let arrivedObject = retainLiveObject(makeButton(label: "Coke", frame: arrivedFrame))
        let arrivedScreen = InterfaceObservation.makeForTests([
            InterfaceObservation.TestEntry(
                arrivedCoke,
                heistId: targetId,
                object: arrivedObject
            )
        ])
        brains.navigation.elementInflation.exploration.discoverTarget = { _ in nil }
        brains.navigation.elementInflation.exploration.revealKnownTarget = { _ in nil }
        defer {
            brains.navigation.elementInflation.exploration.discoverTarget = { _ in nil }
            brains.navigation.elementInflation.exploration.revealKnownTarget = { _ in nil }
        }

        let target = try resolvedTarget(AccessibilityTarget.label("Coke").and(.traits([.button])))
        let resultBox = InflationResultBox()
        let inflation = Task { @MainActor in
            resultBox.value = await self.brains.navigation.elementInflation.inflate(
                for: target,
                method: .activate
            )
        }
        await waitForSettledSemanticWaiter()
        visibleObservationSource.observation = arrivedScreen
        brains.vault.semanticObservationStream.commitVisibleObservationForTesting(arrivedScreen)

        await inflation.value

        guard case .inflated(let inflatedTarget)? = resultBox.value else {
            return XCTFail(
                "Expected settled-observation recovery of arriving target, got \(String(describing: resultBox.value))"
            )
        }
        XCTAssertEqual(inflatedTarget.treeElement.heistId, targetId)
        XCTAssertEqual(inflatedTarget.liveTarget.activationPoint.x, arrivedFrame.midX, accuracy: 0.01)
        XCTAssertEqual(inflatedTarget.liveTarget.activationPoint.y, arrivedFrame.midY, accuracy: 0.01)
        XCTAssertTrue(inflatedTarget.liveTarget.object === arrivedObject)
    }

    func testRevealRetryAttemptsFreshKnownTargetOnlyOnce() async throws {
        brains.stopSemanticObservation()
        let overviewVisible = makeElement(label: "Combo Overview", traits: .header)
        let staleCoke = makeElement(label: "Coke", traits: .button)
        installScreenWithOffViewportEntry(
            liveHierarchy: [(overviewVisible, "combo_overview_header")],
            offViewport: [InterfaceObservation.OffViewportEntry(staleCoke, heistId: "stale_coke_button")]
        )

        let freshKnownScreen = InterfaceObservation.makeForTests(
            elements: [(overviewVisible, HeistId(rawValue: "combo_overview_header"))],
            offViewport: [
                InterfaceObservation.OffViewportEntry(
                    staleCoke,
                    heistId: "stale_coke_button",
                    scrollContainerPath: TreePath([0])
                )
            ]
        )
        brains.navigation.elementInflation.exploration.discoverTarget = { _ in nil }
        var revealAttempts = 0
        brains.navigation.elementInflation.exploration.revealKnownTarget = { _ in
            revealAttempts += 1
            return nil
        }
        defer {
            brains.navigation.elementInflation.exploration.discoverTarget = { _ in nil }
            brains.navigation.elementInflation.exploration.revealKnownTarget = { _ in nil }
        }

        let target = try resolvedTarget(AccessibilityTarget.label("Coke").and(.traits([.button])))
        let resultBox = InflationResultBox()
        let inflation = Task { @MainActor in
            resultBox.value = await self.brains.navigation.elementInflation.inflate(
                for: target,
                method: .activate
            )
        }
        await waitForSettledSemanticWaiter()
        visibleObservationSource.observation = freshKnownScreen
        brains.vault.semanticObservationStream.commitVisibleObservationForTesting(freshKnownScreen)
        await waitForSettledSemanticWaiter()
        XCTAssertEqual(revealAttempts, 0)
        brains.vault.semanticObservationStream.commitVisibleObservationForTesting(freshKnownScreen)
        await waitForSettledSemanticWaiter()
        XCTAssertEqual(revealAttempts, 0)
        inflation.cancel()

        await inflation.value
        guard case .failed(let failure)? = resultBox.value else {
            return XCTFail("Expected typed cancellation after reveal retry")
        }
        XCTAssertEqual(failure.failedStep, .cancelled)
    }

    func testRevealRetryFailsNoRevealPathAtActionDeadline() async throws {
        let overviewVisible = makeElement(label: "Combo Overview", traits: .header)
        let staleCoke = makeElement(label: "Coke", traits: .button)
        installScreenWithOffViewportEntry(
            liveHierarchy: [(overviewVisible, "combo_overview_header")],
            offViewport: [InterfaceObservation.OffViewportEntry(staleCoke, heistId: "stale_coke_button")]
        )
        brains.navigation.elementInflation.exploration.discoverTarget = { _ in nil }
        brains.navigation.elementInflation.exploration.revealKnownTarget = { _ in nil }
        defer {
            brains.navigation.elementInflation.exploration.discoverTarget = { _ in nil }
            brains.navigation.elementInflation.exploration.revealKnownTarget = { _ in nil }
        }

        let result = await brains.navigation.elementInflation.inflate(
            for: try resolvedTarget(.label("Coke").and(.traits([.button]))),
            method: .activate
        )

        guard case .failed(let failure) = result else {
            return XCTFail("Expected noRevealPath failure at the action deadline, got \(result)")
        }
        XCTAssertEqual(failure.failedStep, ElementInflation.ElementInflationFailureStep.noRevealPath)
        XCTAssertTrue(failure.message.contains("element inflation failed [noRevealPath]"))
        XCTAssertTrue(failure.message.contains("before the action deadline"))
        XCTAssertTrue(failure.message.contains("Coke"))
    }

}

#endif
