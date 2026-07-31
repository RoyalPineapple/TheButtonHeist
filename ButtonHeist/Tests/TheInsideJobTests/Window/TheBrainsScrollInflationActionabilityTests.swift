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

    func testActivationPointPlacementAddsTypedAdjustment() async throws {
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
        await brains.vault.semanticObservationStream
            .commitVisibleObservationForTesting(initialScreen)
        guard assertPlacementTargetIsLiveAndScrollable(
            heistId: targetId,
            in: scrollView
        ) else { return }

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
        let inflation = brains.navigation.elementInflation
        let originalMoveViewport = inflation.exploration.moveViewport
        inflation.exploration.moveViewport = { _, _ in
            object.accessibilityFrame = placedFrame
            object.accessibilityActivationPoint = placedActivationPoint
            self.visibleObservationSource.observation = placedScreen
            let current = await self.brains.vault.semanticObservationStream
                .commitDiscoveryObservationAfterViewportMovementForTesting(placedScreen)
                .current
            return Navigation.ViewportTransition(
                outcome: .moved,
                previousVisibleIds: [targetId],
                current: current
            )
        }
        defer {
            inflation.exploration.moveViewport = originalMoveViewport
        }

        let result = await inflation.inflate(
            for: try resolvedTarget(AccessibilityTarget.label("Placed Target").and(.traits([.button]))),
            method: .activate,
            deadline: semanticRevealDeadline()
        )

        guard case .inflated(let inflatedTarget) = result else {
            return XCTFail("Expected activation-point placement inflation, got \(result)")
        }
        XCTAssertEqual(
            inflatedTarget.resolution,
            ActionSubjectResolution(origin: .visible, adjustments: [.activationPointPlacement])
        )
    }

    private func assertPlacementTargetIsLiveAndScrollable(
        heistId: HeistId,
        in expectedScrollView: UIScrollView
    ) -> Bool {
        guard let committed = brains.vault.interfaceElement(heistId: heistId) else {
            XCTFail("Expected placement target in committed semantic state")
            return false
        }
        switch brains.vault.resolveLiveActionTarget(for: committed) {
        case .resolved:
            break
        case .objectUnavailable:
            XCTFail("Expected placement target to have a live object")
            return false
        case .geometryUnavailable:
            XCTFail(
                "Expected placement target to have fresh live geometry: "
                    + String(
                        describing: brains.vault.currentInterfaceObservation.tree
                            .findElement(heistId: heistId)?
                            .element.shape
                    )
            )
            return false
        }
        XCTAssertTrue(brains.vault.liveScrollView(for: committed) === expectedScrollView)
        return true
    }

    func testOffViewportTargetWithoutLiveScrollParentTimesOutWithoutRevealPath() async throws {
        let scrollView = RecordingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        let visible = makeElement(label: "Visible")
        let offscreen = makeElement(label: "Offscreen")
        await installScreenWithOffViewport(
            visible: InterfaceObservation.TestEntry(visible, heistId: "visible_element"),
            offscreen: OffViewportScrollTarget(
                offscreen,
                heistId: "offscreen_button",
                viewActivationPoint: CGPoint(x: 0, y: 1_200),
                scrollView: scrollView
            ),
            includeLiveScrollAncestor: false
        )
        let result = await brains.navigation.elementInflation.inflate(
            for: try resolvedTarget(.label("Offscreen")),
            method: .scrollToVisible,
            deadline: semanticRevealDeadline()
        )

        guard case .failed(let failure) = result else {
            return XCTFail("Expected timeout while awaiting a reveal path, got \(result)")
        }
        XCTAssertEqual(
            failure.failedStep,
            ElementInflation.ElementInflationFailureStep.timedOut,
            failure.message
        )
        XCTAssertEqual(failure.failureKind, .timeout)
        XCTAssertTrue(failure.message.contains("element inflation failed [timedOut]"))
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
            path: TreePath([0]),
            scrollMembership: nil,
            geometry: testGeometry(
                for: element,
                ownerPath: .root,
                screen: .offscreen
            ),
            element: element
        )
        await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            InterfaceObservation.makeForTests(
            elements: [entry.heistId: entry],
            hierarchy: [.element(element, traversalIndex: 0)],
            heistIdsByPath: [TreePath([0]): entry.heistId],
            elementRefs: [entry.heistId: .init(object: object, scrollView: nil)],
            firstResponderHeistId: nil,
            )
        )

        let result = await brains.navigation.elementInflation.inflate(
            for: try resolvedTarget(.label("Escaped")),
            method: .scrollToVisible,
            deadline: semanticRevealDeadline()
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
        let offscreenActivationPoint = CGPoint(x: elementFrame.midX, y: -4)
        let element = AccessibilityElement.make(
            label: "Escaped",
            traits: .button,
            shape: .frame(AccessibilityRect(elementFrame)),
            activationPoint: offscreenActivationPoint
        )
        let entry = InterfaceTree.Element(
            heistId: "escaped_button",
            path: TreePath([0]),
            scrollMembership: nil,
            geometry: testGeometry(
                for: element,
                ownerPath: .root,
                screen: TheVault.onscreenSpace(for: element)
            ),
            element: element
        )
        await installSyntheticObservation(InterfaceObservation.makeForTests(
            elements: [entry.heistId: entry],
            hierarchy: [.element(element, traversalIndex: 0)],
            heistIdsByPath: [TreePath([0]): entry.heistId],
            elementRefs: [entry.heistId: .init(object: object, scrollView: nil)],
            firstResponderHeistId: nil,
        ))

        let result = await brains.navigation.elementInflation.inflate(
            for: try resolvedTarget(.label("Escaped")),
            method: .scrollToVisible,
            deadline: semanticRevealDeadline()
        )

        guard case .failed(let failure) = result else {
            return XCTFail("Expected not-actionable failure, got \(result)")
        }
        XCTAssertEqual(failure.failedStep, ElementInflation.ElementInflationFailureStep.geometryNotActionable)
        XCTAssertTrue(failure.message.contains("element inflation failed [geometryNotActionable]"))
    }

    func testElementActionsConsumeElementInflationTimeoutBeforeDispatch() async throws {
        let visible = makeElement(label: "Visible")
        let offscreen = makeElement(label: "Offscreen")
        await installScreenWithOffViewportEntry(
            liveHierarchy: [(visible, "visible_element")],
            offViewport: [InterfaceObservation.OffViewportEntry(offscreen, heistId: "offscreen_button")]
        )
        var didDispatch = false
        var timing = ActionTiming()

        let result = await brains.actions.performElementAction(
            target: try resolvedTarget(.label("Offscreen")),
            payload: .activate,
            deadline: semanticRevealDeadline(),
            timing: &timing,
            requireInteractive: false
        ) { _ in
            didDispatch = true
            return TheSafecracker.ActionDispatchResult.success(payload: .activate)
        }

        XCTAssertFalse(didDispatch)
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, ActionMethod.activate)
        XCTAssertEqual(result.failureKind, .timeout)
        XCTAssertTrue(result.message?.contains("element inflation failed [timedOut]") == true)
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
        await brains.vault.semanticObservationStream
            .commitVisibleObservationForTesting(screen)
        visibleObservationSource.observation = screen
        let target = try resolvedTarget(AccessibilityTarget.label("Refreshable").and(.traits([.button])))
        let finalResolution = ActionSubjectResolution(
            origin: .known,
            adjustments: [.staleTargetRefresh]
        )
        var timing = ActionTiming()

        let result = await brains.actions.performElementAction(
            target: target,
            payload: .activate,
            deadline: semanticRevealDeadline(),
            timing: &timing,
            requireInteractive: false
        ) { context in
            .success(
                payload: .activate,
                subjectEvidence: ActionSubjectEvidence(
                    source: .resolvedSemanticTarget,
                    target: target,
                    element: TheVault.WireConversion.convert(
                        context.treeElement.element,
                        geometry: context.treeElement.geometry
                    ),
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
        await installScreenWithOffViewport(
            visible: InterfaceObservation.TestEntry(staleVisible, heistId: "old_visible"),
            offscreen: OffViewportScrollTarget(
                staleOffscreen,
                heistId: "old_offscreen",
                viewActivationPoint: CGPoint(x: 0, y: 1_200),
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
        _ = try await publishedVisibleObservation()
        visibleObservationSource.useLiveCapture()

        let result = await brains.executeRuntimeAction(
            .activate(.label("Old Offscreen"))
        )

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(result.outcome.failureKind, .elementNotFound)
        XCTAssertEqual(staleScrollView.contentOffset, .zero)
        XCTAssertFalse(
            result.message?.contains("after semantic reveal") ?? false,
            "Stale offscreen memory must not drive operation-local semantic reveal after a fresh screen change"
        )
    }

}

#endif
