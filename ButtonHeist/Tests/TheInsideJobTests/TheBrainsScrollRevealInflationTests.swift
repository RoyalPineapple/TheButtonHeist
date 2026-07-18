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

    func testSemanticRevealNoOpsWhenAlreadyVisible() async {
        let scrollView = RecordingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        let visibleEntry = InterfaceTree.Element(
            heistId: "visible_element",
            scrollMembership: InterfaceTree.ScrollMembership(containerPath: TreePath([0]), index: nil),
            element: makeElement(label: "Visible")
        )
        installLiveScrollTarget(visibleEntry, scrollView: scrollView, containerName: "visible_scroll")

        let result = await brains.navigation.elementInflation.revealSemanticTarget(
            visibleEntry, deadline: semanticRevealDeadline()
        )

        guard case .alreadyVisible = result else {
            return XCTFail("Expected already-visible no-op, got \(result)")
        }
        XCTAssertEqual(scrollView.setContentOffsetAnimations, [])
        XCTAssertEqual(scrollView.contentOffset, .zero)
    }

    func testDirectSemanticRevealRejectsReusedIdReplacementWithoutStaleRestore() async throws {
        let scrollView = RecordingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        scrollView.contentOffset = CGPoint(x: 0, y: 80)
        let targetId: HeistId = "direct_reused_target"
        installScreenWithOffViewport(
            visible: .init(makeElement(label: "Visible"), heistId: "visible_element"),
            offscreen: .init(
                makeElement(label: "Original Target", traits: .button),
                heistId: targetId,
                contentActivationPoint: CGPoint(x: 0, y: 1_200),
                scrollView: scrollView
            )
        )
        brains.vault.nextVisibleRefreshObservationForTesting = InterfaceObservation.makeForTests([
            .init(
                makeElement(label: "Replacement Target", traits: .button),
                heistId: targetId,
                object: retainedLiveObject()
            ),
        ])
        brains.navigation.elementInflation.exploration.revealKnownTarget = { _ in nil }
        scrollView.setContentOffsetAnimations.removeAll()
        let treeElement = try XCTUnwrap(brains.vault.interfaceElement(heistId: targetId))

        let result = await brains.navigation.elementInflation.revealSemanticTarget(
            treeElement,
            deadline: semanticRevealDeadline()
        )

        guard case .failed(.noLiveScrollableAncestor) = result else {
            return XCTFail("Expected direct reused-ID evidence to fail closed, got \(result)")
        }
        XCTAssertEqual(scrollView.setContentOffsetAnimations, [false])
        XCTAssertNotEqual(scrollView.contentOffset, CGPoint(x: 0, y: 80))
    }

    func testSemanticRevealFailsWithoutProvenLiveScrollAncestor() async throws {
        let scrollView = RecordingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        let visible = makeElement(label: "Visible")
        let offscreen = makeElement(label: "Settings")
        installScreenWithOffViewport(
            visible: InterfaceObservation.TestEntry(visible, heistId: "visible_element"),
            offscreen: OffViewportScrollTarget(
                offscreen,
                heistId: "settings_button",
                contentActivationPoint: CGPoint(x: 0, y: 1_200),
                scrollView: scrollView
            ),
            includeLiveScrollAncestor: false
        )

        let entry = try XCTUnwrap(
            brains.vault.interfaceTree.findElement(heistId: "settings_button")
        )
        let result = await brains.navigation.elementInflation.revealSemanticTarget(
            entry, deadline: semanticRevealDeadline()
        )

        guard case .failed(.noLiveScrollableAncestor) = result else {
            return XCTFail("Expected missing live scroll ancestor failure, got \(result)")
        }
        XCTAssertEqual(scrollView.setContentOffsetAnimations, [])
        XCTAssertEqual(scrollView.contentOffset, .zero)
    }

    func testKnownTargetRevealReturnsTimedOutInflationFailureBeforeWork() async throws {
        let scrollView = RecordingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        installScreenWithOffViewport(
            visible: .init(makeElement(label: "Visible"), heistId: "visible_element"),
            offscreen: .init(
                makeElement(label: "Settings"),
                heistId: "settings_button",
                contentActivationPoint: CGPoint(x: 0, y: 1_200),
                scrollView: scrollView
            ),
            includeLiveScrollAncestor: false
        )
        let entry = try XCTUnwrap(brains.vault.interfaceTree.findElement(heistId: "settings_button"))
        var knownTargetAttempts = 0
        brains.navigation.elementInflation.exploration.revealKnownTarget = { _ in
            knownTargetAttempts += 1
            return nil
        }
        let deadline = SemanticObservationDeadline(
            start: CFAbsoluteTimeGetCurrent() - 1,
            timeoutSeconds: 0
        )

        let state = await brains.navigation.elementInflation.stateAfterReveal(
            entry,
            target: try resolvedTarget(.label("Settings")),
            deadline: deadline,
            resolution: ActionSubjectResolution(origin: .known),
            transaction: .init(vault: brains.vault)
        )

        guard case .failed(let failure) = state else {
            return XCTFail("Expected typed deadline failure, got \(state)")
        }
        XCTAssertEqual(failure.failedStep, .timedOut)
        XCTAssertEqual(knownTargetAttempts, 0)
        XCTAssertEqual(scrollView.setContentOffsetAnimations, [])
    }

    func testKnownTargetRevealReturnsCancelledInflationFailureBeforeWork() async throws {
        let scrollView = RecordingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        installScreenWithOffViewport(
            visible: .init(makeElement(label: "Visible"), heistId: "visible_element"),
            offscreen: .init(
                makeElement(label: "Settings"),
                heistId: "settings_button",
                contentActivationPoint: CGPoint(x: 0, y: 1_200),
                scrollView: scrollView
            ),
            includeLiveScrollAncestor: false
        )
        let entry = try XCTUnwrap(brains.vault.interfaceTree.findElement(heistId: "settings_button"))
        var knownTargetAttempts = 0
        brains.navigation.elementInflation.exploration.revealKnownTarget = { _ in
            knownTargetAttempts += 1
            return nil
        }
        let target = try resolvedTarget(AccessibilityTarget.label("Settings"))
        let revealTask = Task { @MainActor in
            let state = await self.brains.navigation.elementInflation.stateAfterReveal(
                entry,
                target: target,
                deadline: self.semanticRevealDeadline(),
                resolution: ActionSubjectResolution(origin: .known),
                transaction: .init(vault: self.brains.vault)
            )
            guard case .failed(let failure) = state else { return false }
            return failure.failedStep == .cancelled
        }
        revealTask.cancel()

        let wasCancelled = await revealTask.value
        XCTAssertTrue(wasCancelled)
        XCTAssertEqual(knownTargetAttempts, 0)
        XCTAssertEqual(scrollView.setContentOffsetAnimations, [])
    }

    func testScrollToVisibleUnknownTargetUsesCurrentSemanticDiagnostics() async throws {
        let visible = makeElement(label: "Visible")
        brains.vault.installObservationForTesting(.makeForTests(
            elements: [(visible, HeistId(rawValue: "visible_element"))]
        ))

        let result = await brains.navigation.executeScrollToVisible(
            target: try resolvedScrollToVisibleTarget(
                ScrollToVisibleTarget(target: .label("Missing Button"))
            )
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .scrollToVisible)
        XCTAssertEqual(result.failureKind, .targetUnavailable)
        XCTAssertTrue(result.message?.contains("element inflation failed [notFound]") == true)
        XCTAssertTrue(result.message?.contains("No match for") == true)
        XCTAssertTrue(result.message?.contains("Missing Button") == true)
        XCTAssertFalse(result.message?.contains("get_interface") == true)
    }

    func testElementInflationNamesNoRevealPathFailure() async throws {
        let visible = makeElement(label: "Visible")
        let offscreen = makeElement(label: "Offscreen")
        installScreenWithOffViewportEntry(
            liveHierarchy: [(visible, "visible_element")],
            offViewport: [InterfaceObservation.OffViewportEntry(offscreen, heistId: "offscreen_button")]
        )

        let result = await brains.navigation.elementInflation.inflate(
            for: try resolvedTarget(.label("Offscreen")),
            method: .activate
        )

        guard case .failed(let failure) = result else {
            return XCTFail("Expected element inflation failure, got \(result)")
        }
        XCTAssertEqual(
            failure.failedStep,
            ElementInflation.ElementInflationFailureStep.noRevealPath,
            failure.message
        )
        XCTAssertTrue(failure.message.contains("element inflation failed [noRevealPath]"))
    }

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
        brains.vault.nextVisibleRefreshObservationForTesting = discoveredScreen
        brains.navigation.elementInflation.exploration.discoverTarget = { _ in
            self.brains.vault.recordParsedObservedEvidence(discoveredScreen)
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
        brains.vault.nextVisibleRefreshObservationForTesting = visibleScreen
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
        brains.vault.nextVisibleRefreshObservationForTesting = arrivedScreen
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
        brains.vault.nextVisibleRefreshObservationForTesting = freshKnownScreen
        brains.vault.semanticObservationStream.commitVisibleObservationForTesting(freshKnownScreen)
        await waitForSettledSemanticWaiter()
        XCTAssertEqual(revealAttempts, 1)
        brains.vault.semanticObservationStream.commitVisibleObservationForTesting(freshKnownScreen)
        await waitForSettledSemanticWaiter()
        XCTAssertEqual(revealAttempts, 1)
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

    func testStaleLiveObjectRawRefreshDoesNotPromoteSemanticTruth() async throws {
        brains.stopSemanticObservation()
        let targetId = HeistId(rawValue: "gone_target")
        let staleTarget = AccessibilityElement.make(
            label: "Gone Target",
            traits: .button,
            frame: CGRect(x: 40, y: 120, width: 240, height: 44)
        )
        brains.vault.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: [(staleTarget, targetId)],
            objects: [targetId: nil]
        ))

        let rawTarget = AccessibilityElement.make(
            label: "Raw Replacement",
            traits: .button,
            frame: CGRect(x: 48, y: 136, width: 260, height: 44)
        )
        brains.vault.nextVisibleRefreshObservationForTesting = InterfaceObservation.makeForTests([
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
        brains.vault.installObservationForTesting(InterfaceObservation.makeForTests(
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
        brains.vault.nextVisibleRefreshObservationForTesting = recoveredScreen
        brains.vault.semanticObservationStream.commitVisibleObservationForTesting(recoveredScreen)

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
        brains.vault.installObservationForTesting(originalScreen)
        let selected = try XCTUnwrap(brains.vault.interfaceElement(heistId: targetId))

        let emptyScreen = InterfaceObservation.makeForTests()
        brains.vault.installObservationForTesting(emptyScreen)
        brains.vault.nextVisibleRefreshObservationForTesting = emptyScreen

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
                    start: CFAbsoluteTimeGetCurrent(),
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
        brains.vault.nextVisibleRefreshObservationForTesting = recoveredScreen
        brains.vault.semanticObservationStream.commitVisibleObservationForTesting(recoveredScreen)

        let resolution = await resolutionTask.value
        XCTAssertEqual(
            resolution,
            ActionSubjectResolution(origin: .visible, adjustments: [.staleTargetRefresh])
        )
    }

    func testActivationPointPlacementAddsTypedAdjustment() async throws {
        brains.stopSemanticObservation()
        let targetId: HeistId = "placed_target"
        let scrollView = RecordingScrollView(frame: ScreenMetrics.current.bounds)
        scrollView.contentSize = CGSize(
            width: ScreenMetrics.current.bounds.width,
            height: ScreenMetrics.current.bounds.height * 3
        )
        let object = retainLiveObject(UIButton(type: .system))
        let initialFrame = CGRect(
            x: 40,
            y: ScreenMetrics.current.bounds.maxY + 120,
            width: 200,
            height: 44
        )
        object.accessibilityLabel = "Placed Target"
        object.accessibilityFrame = initialFrame
        let initialActivationPoint = CGPoint(x: initialFrame.midX, y: initialFrame.midY)
        object.accessibilityActivationPoint = initialActivationPoint
        let initialElement = AccessibilityElement.make(
            label: "Placed Target",
            traits: .button,
            shape: .frame(AccessibilityRect(initialFrame)),
            activationPoint: initialActivationPoint
        )
        let initialScreen = makePlacementScreen(
            targetId: targetId,
            element: initialElement,
            object: object,
            scrollView: scrollView
        )
        brains.vault.installObservationForTesting(initialScreen)
        guard let committed = brains.vault.interfaceElement(heistId: targetId) else {
            return XCTFail("Expected placement target in committed semantic state")
        }
        switch brains.vault.resolveLiveActionTarget(for: committed) {
        case .resolved:
            break
        case .objectUnavailable:
            return XCTFail("Expected placement target to have a live object")
        case .geometryUnavailable:
            return XCTFail(
                "Expected placement target to have fresh live geometry: "
                    + String(describing: brains.vault.liveInterfaceElement(heistId: targetId)?.element.shape)
            )
        }
        XCTAssertTrue(brains.vault.liveScrollView(for: committed) === scrollView)

        let placedFrame = CGRect(
            x: ElementInflation.interactionComfortZone.midX - 100,
            y: ElementInflation.interactionComfortZone.midY - 22,
            width: 200,
            height: 44
        )
        let placedActivationPoint = CGPoint(x: placedFrame.midX, y: placedFrame.midY)
        let placedElement = AccessibilityElement.make(
            label: "Placed Target",
            traits: .button,
            shape: .frame(AccessibilityRect(placedFrame)),
            activationPoint: placedActivationPoint
        )
        let placedScreen = makePlacementScreen(
            targetId: targetId,
            element: placedElement,
            object: object,
            scrollView: scrollView
        )
        let originalMoveViewport = brains.navigation.elementInflation.exploration.moveViewport
        brains.navigation.elementInflation.exploration.moveViewport = { intent in
            object.accessibilityFrame = placedFrame
            object.accessibilityActivationPoint = placedActivationPoint
            self.brains.vault.nextVisibleRefreshObservationForTesting = placedScreen
            return await originalMoveViewport(intent)
        }
        defer {
            brains.navigation.elementInflation.exploration.moveViewport = originalMoveViewport
        }

        let result = await brains.navigation.elementInflation.inflate(
            for: try resolvedTarget(AccessibilityTarget.label("Placed Target").and(.traits([.button]))),
            method: .activate
        )

        guard case .inflated(let inflatedTarget) = result else {
            return XCTFail("Expected activation-point placement inflation, got \(result)")
        }
        XCTAssertEqual(
            inflatedTarget.resolution,
            ActionSubjectResolution(origin: .visible, adjustments: [.activationPointPlacement])
        )
    }

    func testOffViewportTargetWithoutLiveScrollParentFailsNoRevealPath() async throws {
        let scrollView = RecordingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        let visible = makeElement(label: "Visible")
        let offscreen = makeElement(label: "Offscreen")
        installScreenWithOffViewport(
            visible: InterfaceObservation.TestEntry(visible, heistId: "visible_element"),
            offscreen: OffViewportScrollTarget(
                offscreen,
                heistId: "offscreen_button",
                contentActivationPoint: CGPoint(x: 0, y: 1_200),
                scrollView: scrollView
            ),
            includeLiveScrollAncestor: false
        )
        let result = await brains.navigation.elementInflation.inflate(
            for: try resolvedTarget(.label("Offscreen")),
            method: .scrollToVisible
        )

        guard case .failed(let failure) = result else {
            return XCTFail("Expected no-reveal-path inflation failure, got \(result)")
        }
        XCTAssertEqual(
            failure.failedStep,
            ElementInflation.ElementInflationFailureStep.noRevealPath,
            failure.message
        )
        XCTAssertTrue(failure.message.contains("element inflation failed [noRevealPath]"))
        XCTAssertTrue(failure.message.contains("no live scrollable ancestor"))
        XCTAssertTrue(failure.message.contains("expectedScrollContainerPath=[0]"), failure.message)
        XCTAssertTrue(failure.message.contains("available live scroll containers: path=[0]"), failure.message)
    }

    func testVisibleTargetOutsideViewportWithoutLiveScrollParentFailsGeometryNotActionable() async throws {
        let elementFrame = CGRect(
            x: 24,
            y: ScreenMetrics.current.bounds.maxY + 80,
            width: 180,
            height: 44
        )
        let object = UIButton(type: .system)
        object.accessibilityLabel = "Escaped"
        object.accessibilityFrame = elementFrame
        object.accessibilityActivationPoint = CGPoint(x: elementFrame.midX, y: elementFrame.midY)
        let element = makeElement(
            label: "Escaped",
            traits: .button,
            shape: .frame(AccessibilityRect(elementFrame))
        )
        let entry = InterfaceTree.Element(
            heistId: "escaped_button",
            scrollMembership: nil,
            element: element
        )
        brains.vault.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: [entry.heistId: entry],
            hierarchy: [.element(element, traversalIndex: 0)],
            heistIdsByPath: [TreePath([0]): entry.heistId],
            elementRefs: [entry.heistId: .init(object: object, scrollView: nil)],
            firstResponderHeistId: nil,
        ))

        let result = await brains.navigation.elementInflation.inflate(
            for: try resolvedTarget(.label("Escaped")),
            method: .scrollToVisible
        )

        guard case .failed(let failure) = result else {
            return XCTFail("Expected no-reveal-path failure, got \(result)")
        }
        XCTAssertEqual(failure.failedStep, ElementInflation.ElementInflationFailureStep.noRevealPath)
        XCTAssertTrue(failure.message.contains("element inflation failed [noRevealPath]"))
    }

    func testInflationRequiresActivationPointOnScreenWhenFrameIntersectsViewport() async throws {
        let elementFrame = CGRect(x: 24, y: -24, width: 180, height: 44)
        let object = UIButton(type: .system)
        object.accessibilityLabel = "Escaped"
        object.accessibilityFrame = elementFrame
        object.accessibilityActivationPoint = CGPoint(x: elementFrame.midX, y: -4)
        let element = AccessibilityElement.make(
            label: "Escaped",
            traits: .button,
            shape: .frame(AccessibilityRect(elementFrame)),
            activationPoint: object.accessibilityActivationPoint
        )
        let entry = InterfaceTree.Element(
            heistId: "escaped_button",
            scrollMembership: nil,
            element: element
        )
        brains.vault.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: [entry.heistId: entry],
            hierarchy: [.element(element, traversalIndex: 0)],
            heistIdsByPath: [TreePath([0]): entry.heistId],
            elementRefs: [entry.heistId: .init(object: object, scrollView: nil)],
            firstResponderHeistId: nil,
        ))

        let result = await brains.navigation.elementInflation.inflate(
            for: try resolvedTarget(.label("Escaped")),
            method: .scrollToVisible
        )

        guard case .failed(let failure) = result else {
            return XCTFail("Expected not-actionable failure, got \(result)")
        }
        XCTAssertEqual(failure.failedStep, ElementInflation.ElementInflationFailureStep.geometryNotActionable)
        XCTAssertTrue(failure.message.contains("element inflation failed [geometryNotActionable]"))
    }

    func testElementActionsConsumeElementInflationFailureBeforeDispatch() async throws {
        let visible = makeElement(label: "Visible")
        let offscreen = makeElement(label: "Offscreen")
        installScreenWithOffViewportEntry(
            liveHierarchy: [(visible, "visible_element")],
            offViewport: [InterfaceObservation.OffViewportEntry(offscreen, heistId: "offscreen_button")]
        )
        var didDispatch = false

        let result = await brains.actions.performElementAction(
            target: try resolvedTarget(.label("Offscreen")),
            method: .activate,
            requireInteractive: false
        ) { _ in
            didDispatch = true
            return TheSafecracker.ActionDispatchOutcome.success(method: .activate)
        }

        XCTAssertFalse(didDispatch)
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, ActionMethod.activate)
        XCTAssertTrue(result.message?.contains("element inflation failed [noRevealPath]") == true)
    }

    func testElementActionPreservesFinalDispatchSubjectResolution() async throws {
        let frame = CGRect(x: 40, y: 120, width: 240, height: 44)
        let element = makeElement(
            label: "Refreshable",
            traits: .button,
            shape: .frame(AccessibilityRect(frame))
        )
        let object = retainLiveObject(makeButton(label: "Refreshable", frame: frame))
        let screen = InterfaceObservation.makeForTests([
            .init(element, heistId: "refreshable_button", object: object),
        ])
        brains.vault.installObservationForTesting(screen)
        brains.vault.nextVisibleRefreshObservationForTesting = screen
        let target = try resolvedTarget(AccessibilityTarget.label("Refreshable").and(.traits([.button])))
        let finalResolution = ActionSubjectResolution(
            origin: .known,
            adjustments: [.staleTargetRefresh]
        )

        let result = await brains.actions.performElementAction(
            target: target,
            method: .activate,
            requireInteractive: false
        ) { context in
            .success(
                method: .activate,
                subjectEvidence: ActionSubjectEvidence(
                    source: .resolvedSemanticTarget,
                    target: target,
                    element: TheVault.WireConversion.convert(context.treeElement.element),
                    resolution: finalResolution
                )
            )
        }

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.subjectEvidence?.resolution, finalResolution)
    }

    func testTargetedActionDoesNotRecoverFromStaleOffscreenSnapshotAfterFreshScreenChange() async throws {
        let staleScrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        staleScrollView.contentSize = CGSize(width: 320, height: 1_600)
        let staleVisible = makeElement(label: "Old Visible")
        let staleOffscreen = makeElement(label: "Old Offscreen")
        installScreenWithOffViewport(
            visible: InterfaceObservation.TestEntry(staleVisible, heistId: "old_visible"),
            offscreen: OffViewportScrollTarget(
                staleOffscreen,
                heistId: "old_offscreen",
                contentActivationPoint: CGPoint(x: 0, y: 1_200),
                scrollView: staleScrollView
            )
        )

        let rootView = UIView()
        rootView.backgroundColor = .white
        rootView.addSubview(makeButton(label: "Fresh Visible", frame: CGRect(x: 40, y: 120, width: 240, height: 44)))
        let window = try installModalWindow(rootView: rootView)
        defer {
            window.rootViewController?.view.accessibilityViewIsModal = false
            window.isHidden = true
        }
        await brains.tripwire.yieldFrames(3)
        brains.vault.clearInstalledVisibleRefreshObservationForTesting()

        let result = await brains.executeRuntimeAction(
            .activate(try resolvedTarget(.label("Old Offscreen")))
        )

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(result.outcome.errorKind, .elementNotFound)
        XCTAssertEqual(staleScrollView.contentOffset, .zero)
        XCTAssertFalse(
            result.message?.contains("after semantic reveal") ?? false,
            "Stale offscreen memory must not drive operation-local semantic reveal after a fresh screen change"
        )
    }

}

#endif
