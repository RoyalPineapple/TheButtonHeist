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

    func testStaleLiveObjectRawRefreshDoesNotPromoteSemanticTruth() async throws {
        brains.stopSemanticObservation()
        let targetId = HeistId(rawValue: "gone_target")
        let staleTarget = AccessibilityElement.make(
            label: "Gone Target",
            traits: .button,
            frame: CGRect(x: 40, y: 120, width: 240, height: 44)
        )
        await brains.vault.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: [(staleTarget, targetId)],
            objects: [targetId: nil]
        ))

        let rawTarget = AccessibilityElement.make(
            label: "Raw Replacement",
            traits: .button,
            frame: CGRect(x: 48, y: 136, width: 260, height: 44)
        )
        visibleObservationSource.observation = InterfaceObservation.makeForTests([
            InterfaceObservation.TestEntry(
                rawTarget,
                heistId: targetId,
                object: retainedLiveObject()
            )
        ])

        let target = try resolvedTarget(AccessibilityTarget.label("Gone Target").and(.traits([.button])))
        let resultBox = InflationResultBox()
        let inflation = Task { @MainActor in
            resultBox.value = await self.brains.navigation.elementInflation.inflate(
                for: target,
                method: .activate
            )
        }
        await waitForSettledSemanticWaiter()

        XCTAssertEqual(brains.vault.latestObservation.tree.orderedElements.first?.element.label, "Raw Replacement")
        XCTAssertEqual(brains.vault.interfaceTree.orderedElements.first?.element.label, "Gone Target")
        if let committed = brains.vault.interfaceElement(heistId: targetId) {
            XCTAssertNil(brains.vault.visibleLiveElementAliasing(committed))
        } else {
            XCTFail("Expected committed semantic target to remain available")
        }

        inflation.cancel()
        await inflation.value
        guard case .failed(let failure)? = resultBox.value else {
            return XCTFail("Expected typed cancellation while waiting for settled target evidence")
        }
        XCTAssertEqual(failure.failedStep, .cancelled)
    }

    func testStaleLiveObjectRefreshResolvesNextSettledObservation() async throws {
        brains.stopSemanticObservation()
        let targetId = HeistId(rawValue: "recycled_target")
        let staleFrame = CGRect(x: 40, y: 120, width: 240, height: 44)
        let staleTarget = AccessibilityElement.make(
            label: "Recycled Target",
            traits: .button,
            frame: staleFrame
        )
        await brains.vault.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: [(staleTarget, targetId)],
            objects: [targetId: nil]
        ))

        let recoveredFrame = CGRect(x: 48, y: 136, width: 260, height: 44)
        let recoveredTarget = AccessibilityElement.make(
            label: "Recycled Target",
            traits: .button,
            frame: recoveredFrame
        )
        let recoveredObject = retainedLiveObject()
        let recoveredScreen = InterfaceObservation.makeForTests([
            InterfaceObservation.TestEntry(
                recoveredTarget,
                heistId: targetId,
                object: recoveredObject
            )
        ])
        let target = try resolvedTarget(AccessibilityTarget.label("Recycled Target").and(.traits([.button])))
        let resultBox = InflationResultBox()
        let inflation = Task { @MainActor in
            resultBox.value = await self.brains.navigation.elementInflation.inflate(
                for: target,
                method: .scrollToVisible
            )
        }
        await waitForSettledSemanticWaiter()
        visibleObservationSource.observation = recoveredScreen
        await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(recoveredScreen)

        await inflation.value

        guard case .inflated(let inflatedTarget)? = resultBox.value else {
            return XCTFail(
                "Expected settled-observation refresh to recover target, got \(String(describing: resultBox.value))"
            )
        }
        XCTAssertEqual(inflatedTarget.treeElement.heistId, targetId)
        XCTAssertEqual(inflatedTarget.liveTarget.activationPoint.x, recoveredFrame.midX, accuracy: 0.01)
        XCTAssertEqual(inflatedTarget.liveTarget.activationPoint.y, recoveredFrame.midY, accuracy: 0.01)
        XCTAssertTrue(inflatedTarget.liveTarget.object === recoveredObject)
        XCTAssertEqual(
            inflatedTarget.resolution,
            ActionSubjectResolution(
                origin: .visible,
                adjustments: [.objectDeallocationRefresh]
            )
        )
    }

    func testStaleSemanticTargetRefreshPreservesTypedWitness() async throws {
        brains.stopSemanticObservation()
        let targetId: HeistId = "restored_target"
        let target = try resolvedTarget(AccessibilityTarget.label("Restored Target").and(.traits([.button])))
        let originalScreen = InterfaceObservation.makeForTests([
            .init(
                makeElement(label: "Restored Target", traits: .button),
                heistId: targetId,
                object: retainedLiveObject()
            ),
        ])
        await brains.vault.installObservationForTesting(originalScreen)
        let selected = try XCTUnwrap(brains.vault.interfaceElement(heistId: targetId))

        let emptyScreen = InterfaceObservation.makeForTests()
        await brains.vault.installObservationForTesting(emptyScreen)
        visibleObservationSource.observation = emptyScreen

        let recoveredFrame = CGRect(x: 40, y: 120, width: 240, height: 44)
        let recoveredElement = makeElement(
            label: "Restored Target",
            traits: .button,
            shape: .frame(AccessibilityRect(recoveredFrame))
        )
        let recoveredObject = retainLiveObject(makeButton(label: "Restored Target", frame: recoveredFrame))
        let recoveredScreen = InterfaceObservation.makeForTests([
            .init(
                recoveredElement,
                heistId: targetId,
                object: recoveredObject
            ),
        ])
        let resolutionTask = Task { @MainActor in
            let state = await self.brains.navigation.elementInflation.stateAfterRefresh(
                target: target,
                treeElement: selected,
                resolution: ActionSubjectResolution(origin: .visible),
                method: .activate,
                activationPointPolicy: .liveObjectOnly,
                deadline: SemanticObservationDeadline(
                    start: RuntimeElapsed.now,
                    timeoutSeconds: 3
                )
            )
            guard case .inflated(let inflatedTarget) = state else {
                XCTFail("Expected stale target refresh to recover, got \(state)")
                return nil as ActionSubjectResolution?
            }
            XCTAssertTrue(inflatedTarget.liveTarget.object === recoveredObject)
            return inflatedTarget.resolution
        }
        await waitForSettledSemanticWaiter()
        visibleObservationSource.observation = recoveredScreen
        await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(recoveredScreen)

        let resolution = await resolutionTask.value
        XCTAssertEqual(
            resolution,
            ActionSubjectResolution(origin: .visible, adjustments: [.staleTargetRefresh])
        )
    }

}

#endif
