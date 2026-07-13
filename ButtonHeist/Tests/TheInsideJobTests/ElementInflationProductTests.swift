#if canImport(UIKit)
import XCTest
import ButtonHeistSupport
import ThePlans

@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

@MainActor
final class ElementInflationProductTests: XCTestCase {

    private var brains: TheBrains!

    override func setUp() async throws {
        try await super.setUp()
        brains = TheBrains(tripwire: TheTripwire())
        brains.tripwire.startPulse()
        brains.startSemanticObservation()
    }

    override func tearDown() async throws {
        brains?.stopSemanticObservation()
        brains?.tripwire.stopPulse()
        if let brains {
            assertRuntimeStopped(brains)
        }
        brains = nil
        try await super.tearDown()
    }

    func testElementInflationStateMachineDefinesEveryPhaseTransition() {
        typealias Phase = ElementInflation.StatePhase
        let machine = ElementInflation.StateMachine()
        let legalTransitions: [(from: Phase, to: Phase)] = [
            (.resolving, .revealing),
            (.resolving, .refreshing),
            (.resolving, .failed),
            (.revealing, .refreshing),
            (.revealing, .failed),
            (.refreshing, .placing),
            (.refreshing, .inflated),
            (.refreshing, .failed),
            (.placing, .inflated),
            (.placing, .failed),
        ]

        for from in Phase.allCases {
            for to in Phase.allCases {
                let change = machine.advance(from, with: .advance(to: to))
                let isLegal = legalTransitions.contains { $0 == (from, to) }
                if isLegal {
                    XCTAssertEqual(change, .changed(to: to), "Expected \(from) -> \(to) to be legal")
                } else {
                    XCTAssertEqual(
                        change,
                        .rejected(.init(state: from, event: .advance(to: to)), stayingIn: from),
                        "Expected \(from) -> \(to) to be rejected"
                    )
                }
            }
        }
    }

    func testElementInflationCancellationTerminatesEveryAwaitingPhase() {
        let machine = ElementInflation.StateMachine()
        let awaitingPhases: [ElementInflation.StatePhase] = [
            .resolving,
            .revealing,
            .refreshing,
            .placing,
        ]

        for phase in awaitingPhases {
            XCTAssertEqual(
                machine.advance(phase, with: .cancelled),
                .changed(to: .failed),
                "Expected cancellation to terminate \(phase)"
            )
        }

        for phase in [ElementInflation.StatePhase.inflated, .failed] {
            XCTAssertEqual(
                machine.advance(phase, with: .cancelled),
                .rejected(.init(state: phase, event: .cancelled), stayingIn: phase),
                "Expected terminal phase \(phase) to reject cancellation"
            )
        }
    }

    func testHandoffTickCountFollowsNestedScrollMembershipGraph() {
        let outerPath = TreePath([0])
        let innerPath = TreePath([0, 0])
        let element = InterfaceTree.Element(
            heistId: "nested_target",
            scrollMembership: .init(containerPath: innerPath, index: nil),
            element: AccessibilityElement.make(label: "Nested Target", traits: .button)
        )
        let container = AccessibilityContainer(
            type: .none,
            frame: AccessibilityRect(CGRect(x: 0, y: 0, width: 320, height: 640))
        )
        let tree = InterfaceTree(
            elements: [element.heistId: element],
            containers: [
                outerPath: .init(
                    container: container,
                    path: outerPath,
                    containerName: nil,
                    contentFrame: nil
                ),
                innerPath: .init(
                    container: container,
                    path: innerPath,
                    containerName: nil,
                    contentFrame: nil,
                    scrollMembership: .init(containerPath: outerPath, index: nil)
                ),
            ]
        )

        XCTAssertEqual(
            ElementInflation.handoffTickCount(
                for: InterfaceTree.Element(
                    heistId: "visible_target",
                    scrollMembership: nil,
                    element: AccessibilityElement.make(label: "Visible Target", traits: .button)
                ),
                in: .empty
            ),
            2,
            "A direct target keeps the existing two-tick minimum"
        )
        XCTAssertEqual(
            ElementInflation.handoffTickCount(for: element, in: tree),
            3,
            "Two scroll memberships plus one geometry confirmation require three ticks"
        )
    }

    func testMovingGeometryRequiresOneMatchingQuietSample() {
        let initial = geometrySample(x: 20)
        let moved = geometrySample(x: 44)
        let stabilization = ElementInflation.LiveGeometryStabilization(
            initial: initial,
            requiresOnscreen: true
        )

        guard case .awaiting(let movedStabilization) = stabilization.reduce(
            .sample(moved, viewport: geometryViewport)
        ) else {
            return XCTFail("Moving geometry must restart the quiet window")
        }
        guard case .stable = movedStabilization.reduce(.sample(moved, viewport: geometryViewport)) else {
            return XCTFail("One unchanged sample must complete the quiet window")
        }
    }

    func testUnchangedGeometrySettlesDespiteLayerAnimation() {
        let view = UIView()
        view.layer.add(CABasicAnimation(keyPath: "opacity"), forKey: "test-animation")
        let sample = geometrySample(x: 20)
        let stabilization = ElementInflation.LiveGeometryStabilization(
            initial: sample,
            requiresOnscreen: true
        )

        XCTAssertNotNil(view.layer.animation(forKey: "test-animation"))
        guard case .stable = stabilization.reduce(.sample(sample, viewport: geometryViewport)) else {
            return XCTFail("Layer-only animation must not delay stable live geometry")
        }
    }

    func testOffscreenActivationPointAfterPlacementIsTerminal() {
        let sample = geometrySample(x: 20)
        let stabilization = ElementInflation.LiveGeometryStabilization(
            initial: sample,
            requiresOnscreen: true
        )

        guard case .offscreen = stabilization.reduce(.sample(sample, viewport: .zero)) else {
            return XCTFail("An offscreen activation point must fail after placement")
        }
    }

    func testGeometryStabilizationDeadlineIsTerminal() {
        let stabilization = ElementInflation.LiveGeometryStabilization(
            initial: geometrySample(x: 20),
            requiresOnscreen: true
        )

        guard case .timedOut = stabilization.reduce(.deadlineExpired) else {
            return XCTFail("The operation deadline must terminate geometry stabilization")
        }
    }

    func testGeometryStabilizationCancellationIsTerminal() {
        let stabilization = ElementInflation.LiveGeometryStabilization(
            initial: geometrySample(x: 20),
            requiresOnscreen: true
        )

        guard case .cancelled = stabilization.reduce(.cancelled) else {
            return XCTFail("Cancellation must terminate geometry stabilization")
        }
    }

    func testElementInflationRejectsContainerTargetWithTypedResolutionFailure() async {
        let result = await brains.navigation.elementInflation.inflate(
            for: .container(.identifier("content")),
            method: .activate
        )

        guard case .failed(let failure) = result else {
            return XCTFail("Expected container target rejection")
        }
        XCTAssertEqual(failure.failedStep, .targetResolution)
        XCTAssertEqual(failure.targetResolutionFailure, .containerTarget)
    }

    private func geometrySample(x: CGFloat) -> ElementInflation.LiveGeometrySample {
        ElementInflation.LiveGeometrySample(
            frame: CGRect(x: x, y: 40, width: 100, height: 44),
            activationPoint: CGPoint(x: x + 50, y: 62)
        )
    }

    private var geometryViewport: CGRect {
        CGRect(x: 0, y: 0, width: 320, height: 640)
    }

    func testElementInflationRejectsUnresolvedTargetReferenceWithTypedResolutionFailure() async {
        let result = await brains.navigation.elementInflation.inflate(
            for: .ref("row"),
            method: .activate
        )

        guard case .failed(let failure) = result else {
            return XCTFail("Expected unresolved target reference rejection")
        }
        XCTAssertEqual(failure.failedStep, .targetResolution)
        XCTAssertEqual(failure.targetResolutionFailure, .unresolvedReference("row"))
    }

    func testSemanticActivateRevealsOffscreenScrollTargetWithoutManualPreScroll() async throws {
        let fixture = try installOffscreenActivationFixture(
            identifier: "semantic_checkout_submit",
            label: "Submit Order"
        )
        defer { fixture.cleanup() }
        try seedOffViewportTarget(fixture)

        XCTAssertEqual(fixture.scrollView.contentOffset, .zero)

        let result = await brains.executeRuntimeAction(.activate(
            literalTarget(ElementPredicate(identifier: "semantic_checkout_submit", traits: [.button]))
        ))

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "semantic activate failed")
        guard result.outcome.isSuccess else { return }
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(result.subjectEvidence?.source, .resolvedSemanticTarget)
        XCTAssertEqual(result.subjectEvidence?.element.identifier, fixture.knownHeistId.rawValue)
        XCTAssertEqual(fixture.target.activationCount, 1)
        XCTAssertTrue(fixture.scrollView.didReceiveRevealRequest)
    }

    func testSemanticActivateRevealsNestedContainerTarget() async throws {
        let fixture = try installOffscreenActivationFixture(
            identifier: "nested_semantic_checkout_submit",
            label: "Confirm Payment",
            nestedInGroup: true
        )
        defer { fixture.cleanup() }
        try seedOffViewportTarget(fixture)

        let result = await brains.executeRuntimeAction(.activate(
            literalTarget(ElementPredicate(identifier: "nested_semantic_checkout_submit", traits: [.button]))
        ))

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "nested semantic activate failed")
        guard result.outcome.isSuccess else { return }
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(fixture.target.activationCount, 1)
        XCTAssertTrue(fixture.scrollView.didReceiveRevealRequest)
    }

    func testSemanticTypeTextRevealsOffscreenTextTargetWithoutManualPreScroll() async throws {
        let fixture = try installOffscreenTextInputFixture(
            identifier: "semantic_delivery_note",
            label: "Delivery Note"
        )
        defer { fixture.cleanup() }
        try seedOffViewportTextInputTarget(fixture)

        let keyboardImpl = ProductTextInputKeyboardImpl(textField: fixture.target) { [stash = brains.stash] in
            stash.invalidateSettledObservationFromTripwire()
        }
        brains.safecracker.keyboardBridgeProvider = { keyboardImpl.bridge() }

        XCTAssertEqual(fixture.scrollView.contentOffset, .zero)
        XCTAssertFalse(fixture.target.isFirstResponder)

        let result = await brains.executeRuntimeAction(.typeText(TypeTextTarget(
            text: "leave at desk",
            target: literalTarget(ElementPredicate(identifier: .exact(fixture.identifier)))
        )))

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "semantic type_text failed")
        guard result.outcome.isSuccess else { return }
        XCTAssertEqual(result.method, .typeText)
        XCTAssertEqual(result.subjectEvidence?.source, .textInputTarget)
        XCTAssertEqual(result.subjectEvidence?.element.identifier, fixture.knownHeistId.rawValue)
        XCTAssertEqual(fixture.target.text, "leave at desk")
        XCTAssertTrue(fixture.target.isFirstResponder)
        XCTAssertTrue(fixture.scrollView.didReceiveRevealRequest)
        guard case .value(let value) = result.payload else {
            return XCTFail("Expected final text value payload, got \(String(describing: result.payload))")
        }
        XCTAssertEqual(value, "leave at desk")
    }

    func testActivateVisibleTextFieldFallsBackToTapWithoutDiscoveryScroll() async throws {
        let fixture = try installVisibleTextInputFixture(
            identifier: "visible_activation_text_field",
            label: "Customer Name"
        )
        defer { fixture.cleanup() }

        XCTAssertEqual(fixture.scrollView.contentOffset, .zero)
        XCTAssertFalse(fixture.target.isFirstResponder)

        let result = await brains.executeRuntimeAction(.activate(
            literalTarget(ElementPredicate(identifier: .exact(fixture.identifier), traits: [.textEntry]))
        ))

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "visible text field activate failed")
        XCTAssertEqual(result.subjectEvidence?.element.identifier, fixture.knownHeistId.rawValue)
        XCTAssertTrue(fixture.target.isFirstResponder)
        XCTAssertEqual(fixture.scrollView.revealRequestCount, 0)
        XCTAssertEqual(result.activationTrace?.axActivateReturned, false)
        XCTAssertEqual(result.activationTrace?.tapActivationDispatched, true)
        XCTAssertEqual(result.activationTrace?.tapActivationSucceeded, true)
    }

    func testFirstResponderInflationReplacesStaleLiveObjectForCommittedHeistId() async throws {
        let fixture = try installVisibleTextInputFixture(
            identifier: "replacement_first_responder",
            label: "Replacement First Responder"
        )
        defer { fixture.cleanup() }
        let replacement = try XCTUnwrap(fixture.target as? RefusingActivationTextField)
        XCTAssertTrue(replacement.becomeFirstResponder())

        let refreshed = try XCTUnwrap(brains.stash.refreshLiveCapture())
        XCTAssertEqual(refreshed.liveCapture.firstResponderHeistId, fixture.knownHeistId)
        let stale = RefusingActivationTextField(frame: replacement.frame)
        var elementRefs = refreshed.liveCapture.elementRefs
        elementRefs[fixture.knownHeistId] = .init(object: stale, scrollView: fixture.scrollView)
        let staleObservation = try InterfaceObservation.build(
            tree: refreshed.tree,
            dispatchReferences: .init(
                elementRefs: elementRefs,
                containerRefsByPath: refreshed.liveCapture.containerRefsByPath,
                scrollableContainerViewsByPath: refreshed.liveCapture.scrollableContainerViewsByPath
            )
        )
        brains.stash.installScreenForTesting(staleObservation)
        XCTAssertTrue(brains.stash.liveObject(for: fixture.knownHeistId) === stale)
        brains.stash.nextVisibleRefreshScreenForTesting = refreshed

        let result = await brains.actions.executeResignFirstResponder()

        XCTAssertTrue(result.success, result.message ?? "resign first responder failed")
        XCTAssertEqual(result.method, .resignFirstResponder)
        XCTAssertEqual(stale.resignationCount, 0)
        XCTAssertEqual(replacement.resignationCount, 1)
        XCTAssertTrue(brains.stash.liveObject(for: fixture.knownHeistId) === replacement)
        XCTAssertFalse(replacement.isFirstResponder)
        XCTAssertEqual(brains.stash.interfaceTree.firstResponderHeistId, fixture.knownHeistId)
    }

    func testSemanticActivateRevealsTargetInsideNestedOffscreenScrollContainer() async throws {
        let fixture = try installNestedScrollActivationFixture(
            identifier: "nested_scroll_checkout_submit",
            label: "Confirm Nested Payment"
        )
        defer { fixture.cleanup() }
        try seedKnownNestedScrollTarget(fixture)
        var revealOrder: [ObjectIdentifier] = []
        fixture.outerScrollView.onFirstRevealRequest = {
            revealOrder.append(ObjectIdentifier(fixture.outerScrollView))
        }
        fixture.innerScrollView.onFirstRevealRequest = {
            revealOrder.append(ObjectIdentifier(fixture.innerScrollView))
        }

        XCTAssertEqual(fixture.outerScrollView.contentOffset, .zero)
        XCTAssertEqual(fixture.innerScrollView.contentOffset, .zero)

        let result = await brains.executeRuntimeAction(.activate(
            literalTarget(ElementPredicate(identifier: "nested_scroll_checkout_submit", traits: [.button]))
        ))

        XCTAssertTrue(
            result.outcome.isSuccess,
            nestedScrollFailureDescription(result, fixture: fixture)
        )
        guard result.outcome.isSuccess else { return }
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(result.subjectEvidence?.element.identifier, fixture.knownHeistId.rawValue)
        XCTAssertEqual(fixture.target.activationCount, 1)
        XCTAssertEqual(revealOrder, [
            ObjectIdentifier(fixture.outerScrollView),
            ObjectIdentifier(fixture.innerScrollView),
        ])
        XCTAssertTrue(fixture.outerScrollView.didReceiveRevealRequest)
        XCTAssertTrue(fixture.innerScrollView.didReceiveRevealRequest)
    }

    func testSemanticActivateRevealsNestedScrollTargetWhenOtherWindowHasSameSizedScrollView() async throws {
        let fixture = try installNestedScrollActivationFixture(
            identifier: "nested_scroll_with_decoy_submit",
            label: "Confirm Decoy Payment"
        )
        defer { fixture.cleanup() }
        let decoy = try installScrollDecoyWindow(contentSize: fixture.innerScrollView.contentSize)
        defer { decoy.cleanup() }
        try seedKnownNestedScrollTarget(fixture, decoy: .separate(decoy.scrollView))
        XCTAssertTrue(brains.stash.scrollableContainerViewsByPath.values.contains { $0 === decoy.scrollView })

        let result = await brains.executeRuntimeAction(.activate(
            literalTarget(ElementPredicate(identifier: "nested_scroll_with_decoy_submit", traits: [.button]))
        ))

        XCTAssertTrue(
            result.outcome.isSuccess,
            nestedScrollFailureDescription(result, fixture: fixture)
        )
        guard result.outcome.isSuccess else { return }
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(fixture.target.activationCount, 1)
        XCTAssertTrue(fixture.outerScrollView.didReceiveRevealRequest)
        XCTAssertTrue(fixture.innerScrollView.didReceiveRevealRequest)
        XCTAssertEqual(decoy.scrollView.contentOffset, .zero)
        XCTAssertEqual(decoy.scrollView.revealRequestCount, 0)
    }

    func testNestedRevealDoesNotTreatDuplicateOuterScrollViewPathAsInnerAlias() async throws {
        let fixture = try installNestedScrollActivationFixture(
            identifier: "nested_scroll_duplicate_outer_path_submit",
            label: "Confirm Duplicate Path Payment"
        )
        defer { fixture.cleanup() }
        let decoy = try installScrollDecoyWindow(contentSize: fixture.innerScrollView.contentSize)
        defer { decoy.cleanup() }
        try seedKnownNestedScrollTarget(
            fixture,
            decoy: .duplicateOuterReferenceAtDecoyPath(decoy.scrollView)
        )
        XCTAssertEqual(
            brains.stash.scrollableContainerViewsByPath.values.filter { $0 === fixture.outerScrollView }.count,
            2
        )

        let result = await brains.executeRuntimeAction(.activate(
            literalTarget(ElementPredicate(identifier: .exact(fixture.identifier), traits: [.button]))
        ))

        XCTAssertTrue(
            result.outcome.isSuccess,
            nestedScrollFailureDescription(result, fixture: fixture)
        )
        guard result.outcome.isSuccess else { return }
        XCTAssertEqual(result.subjectEvidence?.element.identifier, fixture.knownHeistId.rawValue)
        XCTAssertEqual(fixture.target.activationCount, 1)
        XCTAssertTrue(fixture.outerScrollView.didReceiveRevealRequest)
        XCTAssertTrue(fixture.innerScrollView.didReceiveRevealRequest)
        XCTAssertEqual(decoy.scrollView.contentOffset, .zero)
    }

    func testAmbiguousSemanticActivateFailsBeforeGeometryOrAction() async throws {
        let fixture = try installAmbiguousActivationFixture()
        defer { fixture.cleanup() }

        let result = await brains.executeRuntimeAction(.activate(
            literalTarget(ElementPredicate(label: "Duplicate", traits: [.button]))
        ))

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(result.outcome.errorKind, .elementNotFound)
        XCTAssertEqual(fixture.first.activationCount, 0)
        XCTAssertEqual(fixture.second.activationCount, 0)
        XCTAssertDiagnostic(result.message, contains: [
            "2 elements match",
            "use ordinal",
        ])
    }

    func testRefreshRetainsSelectedHeistIdWhenPredicateOrderingChanges() async throws {
        let fixture = try installAmbiguousActivationFixture()
        defer { fixture.cleanup() }
        let target = literalTarget(
            ElementPredicate(label: "Duplicate", traits: [.button]),
            ordinal: 0
        )
        fixture.second.isHidden = true
        brains.stash.installScreenForTesting(try observation(for: [fixture.first]))
        brains.stash.clearInstalledVisibleRefreshScreenForTesting()
        guard case .success(let selected) = brains.navigation.elementInflation.knownSemanticTarget(target) else {
            return XCTFail("Expected the original element to satisfy the committed predicate")
        }
        XCTAssertEqual(selected.heistId, "duplicate_first")

        fixture.second.isHidden = false
        fixture.first.superview?.insertSubview(fixture.second, belowSubview: fixture.first)
        fixture.window.layoutIfNeeded()
        brains.stash.installScreenForTesting(try observation(for: [fixture.second, fixture.first]))
        brains.stash.clearInstalledVisibleRefreshScreenForTesting()

        let state = await brains.navigation.elementInflation.stateAfterRefresh(
            target: target,
            treeElement: selected,
            didReveal: false,
            method: .activate,
            activationPointPolicy: .liveObjectOnly,
            deadline: SemanticObservationDeadline(start: CFAbsoluteTimeGetCurrent(), timeoutSeconds: 1)
        )
        guard case .inflated(let inflatedTarget) = state else {
            return XCTFail("Expected refresh to reacquire live evidence for the selected identity, got \(state)")
        }
        XCTAssertEqual(inflatedTarget.treeElement.heistId, "duplicate_first")
        XCTAssertTrue(inflatedTarget.liveTarget.object === fixture.first)

        _ = AccessibilityActionDispatcher().activate(inflatedTarget.liveTarget)

        XCTAssertEqual(fixture.first.activationCount, 1)
        XCTAssertEqual(fixture.second.activationCount, 0)
    }

    func testRefreshFailsClosedWhenSelectedHeistIdIsRemoved() async throws {
        let fixture = try installAmbiguousActivationFixture()
        defer { fixture.cleanup() }
        let target = literalTarget(
            ElementPredicate(label: "Duplicate", traits: [.button]),
            ordinal: 0
        )
        fixture.second.isHidden = true
        brains.stash.installScreenForTesting(try observation(for: [fixture.first]))
        brains.stash.clearInstalledVisibleRefreshScreenForTesting()
        guard case .success(let selected) = brains.navigation.elementInflation.knownSemanticTarget(target) else {
            return XCTFail("Expected the original element to satisfy the committed predicate")
        }

        fixture.first.removeFromSuperview()
        fixture.second.isHidden = false
        brains.stash.installScreenForTesting(try observation(for: [fixture.second]))
        brains.stash.clearInstalledVisibleRefreshScreenForTesting()

        let state = await brains.navigation.elementInflation.stateAfterRefresh(
            target: target,
            treeElement: selected,
            didReveal: false,
            method: .activate,
            activationPointPolicy: .liveObjectOnly,
            deadline: SemanticObservationDeadline(start: CFAbsoluteTimeGetCurrent(), timeoutSeconds: 0)
        )
        switch state {
        case .failed:
            break
        case .inflated(let inflatedTarget):
            _ = AccessibilityActionDispatcher().activate(inflatedTarget.liveTarget)
            XCTFail("Refresh retargeted removed identity \(selected.heistId) to \(inflatedTarget.treeElement.heistId)")
        default:
            XCTFail("Expected removed selected identity to fail closed, got \(state)")
        }

        XCTAssertEqual(fixture.first.activationCount, 0)
        XCTAssertEqual(fixture.second.activationCount, 0)
    }

    func testSemanticActivateFailsAmbiguousDuplicateBeforeReachabilityChoosesCandidate() async throws {
        let fixture = try installOffscreenActivationFixture(
            identifier: "reachable_duplicate_submit",
            label: "Duplicate Submit"
        )
        defer { fixture.cleanup() }
        try seedOffViewportTarget(fixture)
        seedKnownUnreachableDuplicate(
            label: fixture.label,
            identifier: "stale_\(fixture.identifier)",
            heistId: HeistId(rawValue: "stale_\(fixture.knownHeistId.rawValue)")
        )

        let result = await brains.executeRuntimeAction(.activate(
            literalTarget(ElementPredicate(label: .exact(fixture.label), traits: [.button]))
        ))

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(result.outcome.errorKind, .elementNotFound)
        XCTAssertEqual(fixture.target.activationCount, 0)
        XCTAssertFalse(fixture.scrollView.didReceiveRevealRequest)
        XCTAssertDiagnostic(result.message, contains: [
            "2 elements match",
            "use ordinal",
        ])
    }

    func testMissingRevealPathFailsAsInflationDiagnostic() async throws {
        let fixture = try installOffscreenActivationFixture(
            identifier: "live_decoy_unrevealable_submit",
            label: "Live Decoy"
        )
        defer { fixture.cleanup() }
        try seedOffViewportTarget(
            fixture,
            semanticIdentifier: "unrevealable_submit",
            semanticLabel: "Submit Order",
            scrollContainerPathOverride: TreePath([99]),
            refreshesFromUIKit: false
        )

        let result = await brains.executeRuntimeAction(.activate(
            literalTarget(ElementPredicate(identifier: "unrevealable_submit", traits: [.button]))
        ))

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .activate)
        XCTAssertDiagnostic(result.message, contains: [
            "element inflation failed [noRevealPath]",
            "no live scrollable ancestor",
        ])
        XCTAssertFalse(result.message?.localizedCaseInsensitiveContains("scroll first") ?? false)
        XCTAssertFalse(result.message?.contains("get_interface") ?? false)
        XCTAssertEqual(fixture.target.activationCount, 0)
    }

    func testHeistSemanticActivateMatchesSingleActionResultSemantics() async throws {
        let single = try await runSemanticActivateThroughCommand(
            identifier: "single_semantic_heist_parity",
            label: "Heist Parity Single",
            heist: false
        )
        let heist = try await runSemanticActivateThroughCommand(
            identifier: "heist_semantic_heist_parity",
            label: "Heist Parity Heist",
            heist: true
        )
        let heistPayload = try XCTUnwrap(heist.result.heistExecutionPayload)
        let step = try XCTUnwrap(heistPayload.steps.first)
        guard case .action(let actionEvidence)? = step.evidence else {
            return XCTFail("Expected heist action evidence, got \(String(describing: step.evidence))")
        }
        let stepResult = try XCTUnwrap(actionEvidence.dispatchResult)

        XCTAssertTrue(single.result.outcome.isSuccess, single.result.message ?? "single activate failed")
        XCTAssertTrue(heist.result.outcome.isSuccess, heistFailureDescription(heist.result))
        guard single.result.outcome.isSuccess, heist.result.outcome.isSuccess else { return }
        XCTAssertEqual(single.activationCount, 1)
        XCTAssertEqual(heist.activationCount, 1)
        XCTAssertEqual(step.kind, .action)
        XCTAssertEqual(step.status, .passed)
        XCTAssertEqual(single.result.method, .activate)
        XCTAssertEqual(stepResult.method, .activate)
        XCTAssertEqual(stepResult.outcome.isSuccess, single.result.outcome.isSuccess)
        XCTAssertEqual(stepResult.method, single.result.method)
        XCTAssertEqual(stepResult.outcome.errorKind, single.result.outcome.errorKind)
    }

    func testExplicitViewportScrollCommandReportsViewportState() async throws {
        let fixture = try installOffscreenActivationFixture(
            identifier: "explicit_scroll_revealed",
            label: "Explicit Scroll Revealed"
        )
        defer { fixture.cleanup() }

        let result = await brains.executeRuntimeAction(.scroll(ScrollTarget(
            target: literalTarget(ElementPredicate(identifier: "visible_anchor_explicit_scroll_revealed")),
            direction: .down
        )))

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "explicit scroll failed")
        XCTAssertEqual(result.method, .scroll)
        XCTAssertGreaterThan(fixture.scrollView.contentOffset.y, 0)
        XCTAssertNotNil(result.accessibilityTrace)
        let trace = try XCTUnwrap(result.accessibilityTrace)
        XCTAssertGreaterThanOrEqual(trace.captures.count, 2)
    }

    private func runSemanticActivateThroughCommand(
        identifier: String,
        label: String,
        heist: Bool
    ) async throws -> (result: ActionResult, activationCount: Int) {
        let localBrains = TheBrains(tripwire: TheTripwire())
        localBrains.tripwire.startPulse()
        localBrains.startSemanticObservation()
        defer {
            localBrains.stopSemanticObservation()
            localBrains.tripwire.stopPulse()
            assertRuntimeStopped(localBrains)
        }
        let fixture = try installOffscreenActivationFixture(
            identifier: identifier,
            label: label
        )
        defer { fixture.cleanup() }
        try seedOffViewportTarget(fixture, in: localBrains)

        if heist {
            let plan = try HeistPlan(body: [
                .action(try ActionStep(command: .activate(.predicate(ElementPredicateTemplate(identifier: .exact(.literal(identifier)), traits: [.button]))))),
            ])
            let result = await localBrains.executeHeistPlan(plan)
            return (result, fixture.target.activationCount)
        }

        let result = await localBrains.executeRuntimeAction(.activate(
            literalTarget(ElementPredicate(identifier: .exact(identifier), traits: [.button]))
        ))
        return (result, fixture.target.activationCount)
    }

    private func heistFailureDescription(_ result: ActionResult) -> String {
        guard let payload = result.heistExecutionPayload else {
            return result.message ?? "heist activate failed"
        }
        guard let failedStep = payload.firstFailedStep else {
            return result.message ?? "heist activate failed without a failed receipt step"
        }
        let actionMessage = failedStep.reportActionResult?.message
        return [
            result.message,
            "failedStep=\(failedStep.path)",
            "kind=\(failedStep.kind.rawValue)",
            failedStep.reportMessage.map { "message=\($0)" },
            actionMessage.map { "actionMessage=\($0)" },
        ]
        .compactMap(\.self)
        .joined(separator: "; ")
    }

    private func assertRuntimeStopped(
        _ brains: TheBrains,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let observationStream = brains.stash.semanticObservationStream
        XCTAssertFalse(brains.semanticObservationIsActive, file: file, line: line)
        XCTAssertFalse(brains.tripwire.isPulseRunning, file: file, line: line)
        XCTAssertFalse(observationStream.isActive, file: file, line: line)
        XCTAssertEqual(observationStream.settledWaiterCount, 0, file: file, line: line)
        XCTAssertEqual(observationStream.cycleWaiterCount, 0, file: file, line: line)
        XCTAssertEqual(observationStream.activeObservationDemandCount, 0, file: file, line: line)
    }

    private func nestedScrollFailureDescription(
        _ result: ActionResult,
        fixture: NestedScrollRevealFixture
    ) -> String {
        [
            result.message ?? "nested scroll semantic activate failed",
            "outerOffset=\(fixture.outerScrollView.contentOffset)",
            "innerOffset=\(fixture.innerScrollView.contentOffset)",
            "outerReveals=\(fixture.outerScrollView.revealRequestCount)",
            "innerReveals=\(fixture.innerScrollView.revealRequestCount)",
            "targetHidden=\(fixture.target.isHidden)",
            "targetAccessible=\(fixture.target.isAccessibilityElement)",
            "liveIds=\(brains.stash.liveHeistIds().map(\.rawValue).sorted())",
            "semanticPath=\(brains.stash.interfaceElement(heistId: fixture.knownHeistId)?.scrollContainerPath?.indices ?? [])",
            brains.stash.liveScrollContainerDiagnostics(),
        ].joined(separator: "; ")
    }

    private func installOffscreenActivationFixture(
        identifier: String,
        label: String,
        nestedInGroup: Bool = false
    ) throws -> SemanticRevealFixture {
        let windowScene = try requireForegroundWindowScene()
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white
        viewController.view.accessibilityViewIsModal = true

        let scrollView = RevealingScrollView(frame: CGRect(x: 24, y: 80, width: 320, height: 280))
        scrollView.contentSize = CGSize(width: 320, height: 1_400)
        scrollView.backgroundColor = .white
        scrollView.isAccessibilityElement = false

        let anchor = UILabel(frame: CGRect(x: 24, y: 24, width: 240, height: 44))
        anchor.text = "Visible Anchor \(identifier)"
        anchor.accessibilityLabel = anchor.text
        anchor.accessibilityIdentifier = "visible_anchor_\(identifier)"
        anchor.isAccessibilityElement = true
        scrollView.addSubview(anchor)

        let target = SemanticActivationView(frame: CGRect(x: 40, y: 900, width: 220, height: 44))
        target.accessibilityLabel = label
        target.accessibilityIdentifier = identifier
        target.accessibilityTraits = .button

        let frameOrigin: CGPoint
        if nestedInGroup {
            let group = UIView(frame: CGRect(x: 24, y: 860, width: 272, height: 120))
            group.accessibilityLabel = "Payment Actions"
            group.accessibilityIdentifier = "payment_actions_\(identifier)"
            group.isAccessibilityElement = false
            target.frame = CGRect(x: 16, y: 40, width: 220, height: 44)
            group.addSubview(target)
            scrollView.addSubview(group)
            frameOrigin = CGPoint(x: group.frame.minX + target.frame.minX, y: group.frame.minY + target.frame.minY)
        } else {
            scrollView.addSubview(target)
            frameOrigin = target.frame.origin
        }

        scrollView.revealedElements = [target]
        scrollView.updateAccessibilityVisibility()
        viewController.view.addSubview(scrollView)

        let window = UIWindow(windowScene: windowScene)
        window.frame = UIScreen.main.bounds
        window.windowLevel = .alert + 80
        window.rootViewController = viewController
        window.isHidden = false
        window.layoutIfNeeded()

        return SemanticRevealFixture(
            window: window,
            scrollView: scrollView,
            target: target,
            identifier: identifier,
            label: label,
            knownHeistId: HeistId(rawValue: identifier),
            frameOrigin: frameOrigin
        )
    }

    private func installAmbiguousActivationFixture() throws -> AmbiguousActivationFixture {
        let windowScene = try requireForegroundWindowScene()
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white
        viewController.view.accessibilityViewIsModal = true

        let first = SemanticActivationView(frame: CGRect(x: 32, y: 120, width: 220, height: 44))
        first.accessibilityLabel = "Duplicate"
        first.accessibilityIdentifier = "duplicate_first"
        first.accessibilityTraits = .button
        first.isAccessibilityElement = true

        let second = SemanticActivationView(frame: CGRect(x: 32, y: 184, width: 220, height: 44))
        second.accessibilityLabel = "Duplicate"
        second.accessibilityIdentifier = "duplicate_second"
        second.accessibilityTraits = .button
        second.isAccessibilityElement = true

        viewController.view.addSubview(first)
        viewController.view.addSubview(second)

        let window = UIWindow(windowScene: windowScene)
        window.frame = UIScreen.main.bounds
        window.windowLevel = .alert + 80
        window.rootViewController = viewController
        window.isHidden = false
        window.layoutIfNeeded()

        return AmbiguousActivationFixture(window: window, first: first, second: second)
    }

    private func installOffscreenTextInputFixture(
        identifier: String,
        label: String
    ) throws -> TextInputRevealFixture {
        let windowScene = try requireForegroundWindowScene()
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white
        viewController.view.accessibilityViewIsModal = true

        let scrollView = RevealingScrollView(frame: CGRect(x: 24, y: 80, width: 320, height: 280))
        scrollView.contentSize = CGSize(width: 320, height: 1_400)
        scrollView.backgroundColor = .white
        scrollView.isAccessibilityElement = false

        let anchor = UILabel(frame: CGRect(x: 24, y: 24, width: 240, height: 44))
        anchor.text = "Visible Anchor \(identifier)"
        anchor.accessibilityLabel = anchor.text
        anchor.accessibilityIdentifier = "visible_anchor_\(identifier)"
        anchor.isAccessibilityElement = true
        scrollView.addSubview(anchor)

        let target = ActivatingTextField(frame: CGRect(x: 40, y: 900, width: 220, height: 44))
        target.borderStyle = .roundedRect
        target.accessibilityLabel = label
        target.accessibilityIdentifier = identifier
        target.accessibilityValue = ""
        target.isAccessibilityElement = true
        scrollView.addSubview(target)

        scrollView.revealedElements = [target]
        scrollView.updateAccessibilityVisibility()
        viewController.view.addSubview(scrollView)

        let window = UIWindow(windowScene: windowScene)
        window.frame = UIScreen.main.bounds
        window.windowLevel = .alert + 80
        window.rootViewController = viewController
        window.isHidden = false
        window.layoutIfNeeded()

        return TextInputRevealFixture(
            window: window,
            scrollView: scrollView,
            target: target,
            identifier: identifier,
            label: label,
            knownHeistId: HeistId(rawValue: identifier),
            frameOrigin: target.frame.origin
        )
    }

    private func installVisibleTextInputFixture(
        identifier: String,
        label: String
    ) throws -> TextInputRevealFixture {
        let windowScene = try requireForegroundWindowScene()
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white
        viewController.view.accessibilityViewIsModal = true

        let scrollView = RevealingScrollView(frame: CGRect(x: 24, y: 80, width: 320, height: 280))
        scrollView.contentSize = CGSize(width: 320, height: 1_400)
        scrollView.backgroundColor = .white
        scrollView.isAccessibilityElement = false

        let target = RefusingActivationTextField(frame: CGRect(x: 40, y: 24, width: 220, height: 44))
        target.borderStyle = .roundedRect
        target.accessibilityLabel = label
        target.accessibilityIdentifier = identifier
        target.accessibilityValue = ""
        target.accessibilityTraits = target.accessibilityTraits.union(.textEntry)
        target.isAccessibilityElement = true
        scrollView.addSubview(target)

        viewController.view.addSubview(scrollView)

        let window = UIWindow(windowScene: windowScene)
        window.frame = UIScreen.main.bounds
        window.windowLevel = .alert + 80
        window.rootViewController = viewController
        window.isHidden = false
        window.layoutIfNeeded()

        return TextInputRevealFixture(
            window: window,
            scrollView: scrollView,
            target: target,
            identifier: identifier,
            label: label,
            knownHeistId: HeistId(rawValue: identifier),
            frameOrigin: target.frame.origin
        )
    }

    private func installNestedScrollActivationFixture(
        identifier: String,
        label: String
    ) throws -> NestedScrollRevealFixture {
        let windowScene = try requireForegroundWindowScene()
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white
        viewController.view.accessibilityViewIsModal = true

        let outerScrollView = RevealingScrollView(frame: CGRect(x: 24, y: 80, width: 320, height: 280))
        outerScrollView.contentSize = CGSize(width: 320, height: 1_400)
        outerScrollView.backgroundColor = .white
        outerScrollView.isAccessibilityElement = false

        let anchor = UILabel(frame: CGRect(x: 24, y: 24, width: 240, height: 44))
        anchor.text = "Visible Nested Anchor \(identifier)"
        anchor.accessibilityLabel = anchor.text
        anchor.accessibilityIdentifier = "visible_nested_anchor_\(identifier)"
        anchor.isAccessibilityElement = true
        outerScrollView.addSubview(anchor)

        let innerScrollView = RevealingScrollView(frame: CGRect(x: 20, y: 820, width: 280, height: 200))
        innerScrollView.contentSize = CGSize(width: 280, height: 900)
        innerScrollView.backgroundColor = .white
        innerScrollView.isAccessibilityElement = false

        let innerAnchor = UILabel(frame: CGRect(x: 20, y: 20, width: 220, height: 44))
        innerAnchor.text = "Visible Inner Anchor \(identifier)"
        innerAnchor.accessibilityLabel = innerAnchor.text
        innerAnchor.accessibilityIdentifier = "visible_inner_anchor_\(identifier)"
        innerAnchor.isAccessibilityElement = true
        innerScrollView.addSubview(innerAnchor)

        let target = SemanticActivationView(frame: CGRect(x: 20, y: 640, width: 220, height: 44))
        target.accessibilityLabel = label
        target.accessibilityIdentifier = identifier
        target.accessibilityTraits = .button
        innerScrollView.addSubview(target)
        innerScrollView.revealedElements = [target]
        innerScrollView.updateAccessibilityVisibility()

        outerScrollView.addSubview(innerScrollView)
        outerScrollView.revealedContainers = [innerScrollView]
        outerScrollView.updateAccessibilityVisibility()
        viewController.view.addSubview(outerScrollView)

        let window = UIWindow(windowScene: windowScene)
        window.frame = UIScreen.main.bounds
        window.windowLevel = .alert + 80
        window.rootViewController = viewController
        window.isHidden = false
        window.layoutIfNeeded()

        return NestedScrollRevealFixture(
            window: window,
            outerScrollView: outerScrollView,
            innerScrollView: innerScrollView,
            target: target,
            identifier: identifier,
            label: label,
            knownHeistId: HeistId(rawValue: identifier),
            innerFrameOrigin: innerScrollView.frame.origin,
            targetFrameOrigin: target.frame.origin
        )
    }

    private func installScrollDecoyWindow(contentSize: CGSize) throws -> ScrollDecoyFixture {
        let windowScene = try requireForegroundWindowScene()
        let viewController = UIViewController()
        viewController.view.backgroundColor = .clear

        let scrollView = RevealingScrollView(frame: CGRect(x: 12, y: 120, width: 280, height: 200))
        scrollView.contentSize = contentSize
        scrollView.backgroundColor = .clear
        scrollView.isAccessibilityElement = false
        let anchor = UILabel(frame: CGRect(x: 20, y: 20, width: 220, height: 44))
        anchor.text = "Separate Window Scroll Decoy"
        anchor.accessibilityLabel = anchor.text
        anchor.isAccessibilityElement = true
        scrollView.addSubview(anchor)
        viewController.view.addSubview(scrollView)

        let window = UIWindow(windowScene: windowScene)
        window.frame = UIScreen.main.bounds
        window.windowLevel = .alert + 90
        window.rootViewController = viewController
        window.isHidden = false
        window.layoutIfNeeded()
        return ScrollDecoyFixture(window: window, scrollView: scrollView)
    }

    private func seedOffViewportTarget(
        _ fixture: SemanticRevealFixture,
        in targetBrains: TheBrains? = nil,
        semanticIdentifier: String? = nil,
        semanticLabel: String? = nil,
        scrollContainerPathOverride: TreePath? = nil,
        refreshesFromUIKit: Bool = true
    ) throws {
        let targetBrains = targetBrains ?? brains!
        let screen = try XCTUnwrap(targetBrains.stash.refreshLiveCapture())
        let identifier = semanticIdentifier ?? fixture.identifier
        let label = semanticLabel ?? fixture.label
        let scrollContainerPath: TreePath
        if let scrollContainerPathOverride {
            scrollContainerPath = scrollContainerPathOverride
        } else {
            scrollContainerPath = try XCTUnwrap(
                firstLiveScrollableContainerPath(in: screen),
                "Expected fixture to expose a live scroll container. \(scrollContainerDiagnostics(in: screen))"
            )
        }
        let element = makeElement(
            label: label,
            identifier: identifier,
            frame: CGRect(
                origin: fixture.frameOrigin,
                size: fixture.target.bounds.size
            )
        )
        let observedActivationPoint = try observedContentActivationPoint(
            origin: fixture.frameOrigin,
            size: fixture.target.bounds.size
        )
        let entry = InterfaceTree.Element(
            heistId: fixture.knownHeistId,
            scrollMembership: InterfaceTree.ScrollMembership(containerPath: scrollContainerPath, index: nil),
            observedScrollContentActivationPoint: observedActivationPoint,
            element: element
        )
        var elements = screen.tree.elements
        elements[entry.heistId] = entry

        targetBrains.stash.installScreenForTesting(InterfaceObservation.makeForTests(
            tree: InterfaceTree(elements: elements, containers: screen.tree.containers),
            liveCapture: screen.liveCapture
        ))
        if refreshesFromUIKit {
            targetBrains.stash.clearInstalledVisibleRefreshScreenForTesting()
        }
    }

    private func seedOffViewportTextInputTarget(
        _ fixture: TextInputRevealFixture
    ) throws {
        let screen = try XCTUnwrap(brains.stash.refreshLiveCapture())
        let scrollContainerPath = try XCTUnwrap(
            firstLiveScrollableContainerPath(in: screen),
            "Expected fixture to expose a live scroll container. \(scrollContainerDiagnostics(in: screen))"
        )
        let element = makeElement(
            label: fixture.label,
            identifier: fixture.identifier,
            traits: UIAccessibilityTraits.fromNames(["textEntry"]),
            frame: CGRect(
                origin: fixture.frameOrigin,
                size: fixture.target.bounds.size
            )
        )
        let observedActivationPoint = try observedContentActivationPoint(
            origin: fixture.frameOrigin,
            size: fixture.target.bounds.size
        )
        let entry = InterfaceTree.Element(
            heistId: fixture.knownHeistId,
            scrollMembership: InterfaceTree.ScrollMembership(containerPath: scrollContainerPath, index: nil),
            observedScrollContentActivationPoint: observedActivationPoint,
            element: element
        )
        var elements = screen.tree.elements
        elements[entry.heistId] = entry

        brains.stash.installScreenForTesting(InterfaceObservation.makeForTests(
            tree: InterfaceTree(elements: elements, containers: screen.tree.containers),
            liveCapture: screen.liveCapture
        ))
        brains.stash.clearInstalledVisibleRefreshScreenForTesting()
    }

    private func seedKnownUnreachableDuplicate(
        label: String,
        identifier: String,
        heistId: HeistId
    ) {
        let tree = brains.stash.interfaceTree
        let entry = InterfaceTree.Element(
            heistId: heistId,
            scrollMembership: nil,
            element: makeElement(label: label, identifier: identifier)
        )
        var elements = tree.elements
        elements[heistId] = entry
        brains.stash.installScreenForTesting(InterfaceObservation.makeForTests(
            tree: InterfaceTree(elements: elements, containers: tree.containers),
            liveCapture: brains.stash.latestObservation.liveCapture
        ))
    }

    private func seedKnownNestedScrollTarget(
        _ fixture: NestedScrollRevealFixture,
        decoy: NestedScrollDecoy = .absent
    ) throws {
        let screen = try XCTUnwrap(brains.stash.refreshLiveCapture())
        let outerContainerPath = try XCTUnwrap(
            liveScrollableContainerPath(for: fixture.outerScrollView, in: screen),
            "Expected nested fixture to expose the live outer scroll view. \(scrollContainerDiagnostics(in: screen))"
        )
        let decoyContainerPath: TreePath?
        switch decoy {
        case .absent:
            decoyContainerPath = nil
        case .separate(let scrollView), .duplicateOuterReferenceAtDecoyPath(let scrollView):
            decoyContainerPath = try XCTUnwrap(
                liveScrollableContainerPath(for: scrollView, in: screen),
                "Expected separate-window decoy in the parser capture. \(scrollContainerDiagnostics(in: screen))"
            )
        }
        let innerContainerPath = nestedInnerScrollContainerPath(
            for: fixture.innerScrollView,
            below: outerContainerPath,
            in: screen
        )
        let capturedInnerContainer = screen.tree.containers[innerContainerPath]
        let innerContainer = capturedInnerContainer?.container ?? AccessibilityContainer(
            type: .none, scrollableContentSize: AccessibilitySize(fixture.innerScrollView.contentSize),
            frame: AccessibilityRect(fixture.innerScrollView.frame)
        )
        let innerContainerName = capturedInnerContainer?.containerName ?? TheBurglar.containerName(
            for: innerContainer,
            contentFrame: ContentRect(CGRect(origin: .zero, size: fixture.innerScrollView.frame.size))
        )
        let element = makeElement(
            label: fixture.label,
            identifier: fixture.identifier,
            frame: CGRect(
                origin: fixture.targetFrameOrigin,
                size: fixture.target.bounds.size
            )
        )
        let observedTargetActivationPoint = try observedContentActivationPoint(
            origin: fixture.targetFrameOrigin,
            size: fixture.target.bounds.size
        )
        let entry = InterfaceTree.Element(
            heistId: fixture.knownHeistId,
            scrollMembership: InterfaceTree.ScrollMembership(containerPath: innerContainerPath, index: nil),
            observedScrollContentActivationPoint: observedTargetActivationPoint,
            element: element
        )
        var elements = screen.tree.elements
        elements[entry.heistId] = entry

        var containers = screen.tree.containers
        let observedContainerActivationPoint = try capturedInnerContainer?.observedScrollContentActivationPoint
            ?? observedContentActivationPoint(
            origin: fixture.innerFrameOrigin,
            size: fixture.innerScrollView.frame.size
        )
        containers[innerContainerPath] = InterfaceTree.Container(
            container: innerContainer,
            path: innerContainerPath,
            containerName: innerContainerName,
            contentFrame: CGRect(origin: .zero, size: fixture.innerScrollView.frame.size),
            scrollMembership: capturedInnerContainer?.scrollMembership
                ?? InterfaceTree.ScrollMembership(containerPath: outerContainerPath, index: nil),
            observedScrollContentActivationPoint: observedContainerActivationPoint
        )

        let liveCapture: LiveCapture
        switch decoy {
        case .absent, .separate:
            liveCapture = screen.liveCapture
        case .duplicateOuterReferenceAtDecoyPath:
            var scrollableViews = screen.liveCapture.scrollableContainerViewsByPath
            scrollableViews[try XCTUnwrap(decoyContainerPath)] = .init(view: fixture.outerScrollView)
            liveCapture = LiveCapture.makeForTests(
                snapshot: screen.liveCapture.snapshot,
                dispatchReferences: .init(
                    elementRefs: screen.liveCapture.elementRefs,
                    containerRefsByPath: screen.liveCapture.containerRefsByPath,
                    scrollableContainerViewsByPath: scrollableViews
                )
            )
        }

        brains.stash.installScreenForTesting(InterfaceObservation.makeForTests(
            tree: InterfaceTree(elements: elements, containers: containers),
            liveCapture: liveCapture
        ))
        brains.stash.clearInstalledVisibleRefreshScreenForTesting()
    }

    private func observedContentActivationPoint(
        origin: CGPoint,
        size: CGSize
    ) throws -> InterfaceTree.ObservedScrollContentActivationPoint {
        try XCTUnwrap(InterfaceTree.ObservedScrollContentActivationPoint(CGPoint(
            x: origin.x + size.width / 2,
            y: origin.y + size.height / 2
        )))
    }

    private func observation(
        for views: [SemanticActivationView]
    ) throws -> InterfaceObservation {
        InterfaceObservation.makeForTests(try views.map { view in
            let label = try XCTUnwrap(view.accessibilityLabel)
            let identifier = try XCTUnwrap(view.accessibilityIdentifier)
            return InterfaceObservation.TestEntry(
                label: label,
                heistId: HeistId(rawValue: identifier),
                identifier: identifier,
                traits: .button,
                frame: view.convert(view.bounds, to: nil),
                object: view
            )
        })
    }

    private func firstLiveScrollableContainerPath(in screen: InterfaceObservation) -> TreePath? {
        for item in screen.liveCapture.hierarchy.scrollablePathIndexedContainers {
            guard screen.liveCapture.scrollView(forContainerPath: item.path) != nil else { continue }
            return item.path
        }
        return nil
    }

    private func liveScrollableContainerPath(for scrollView: UIScrollView, in screen: InterfaceObservation) -> TreePath? {
        let matchingPaths = screen.liveCapture.scrollableContainerViewsByPath
            .compactMap { path, ref -> TreePath? in
                guard ref.view === scrollView else { return nil }
                return path
            }
            .sorted { $0.indices.lexicographicallyPrecedes($1.indices) }
        return matchingPaths.first {
            screen.liveCapture.containerObject(forPath: $0) === scrollView
        } ?? matchingPaths.first
    }

    private func nestedInnerScrollContainerPath(
        for scrollView: UIScrollView,
        below outerContainerPath: TreePath,
        in screen: InterfaceObservation
    ) -> TreePath {
        if let path = liveScrollableContainerPath(for: scrollView, in: screen) {
            return path
        }

        // Hidden nested scroll views are absent before reveal; the parser assigns
        // the revealed inner scroll view as the first child container.
        return outerContainerPath.appending(0)
    }

    private func scrollContainerDiagnostics(in screen: InterfaceObservation) -> String {
        let summaries = screen.liveCapture.hierarchy.scrollablePathIndexedContainers
            .map { item -> String in
                let name = screen.liveCapture.containerNamesByPath[item.path]
                let hasLiveScroll = screen.liveCapture.scrollView(forContainerPath: item.path) != nil
                return "path=\(item.path.indices) name=\(name ?? "<nil>") liveScroll=\(hasLiveScroll)"
            }
        return "scrollContainers=[\(summaries.joined(separator: "; "))]"
    }

    private func makeElement(
        label: String,
        identifier: String,
        traits: UIAccessibilityTraits = .button,
        frame: CGRect = CGRect(x: 20, y: 20, width: 160, height: 44)
    ) -> AccessibilityElement {
        .make(
            label: label,
            identifier: identifier,
            traits: traits,
            frame: frame,
            respondsToUserInteraction: true
        )
    }

    private func requireForegroundWindowScene() throws -> UIWindowScene {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else {
            throw XCTSkip("No foreground-active UIWindowScene available in test host")
        }
        return scene
    }

    private func XCTAssertDiagnostic(
        _ message: String?,
        contains fragments: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let message else {
            XCTFail("Expected diagnostic message", file: file, line: line)
            return
        }
        for fragment in fragments {
            XCTAssertTrue(
                message.contains(fragment),
                "Expected diagnostic to contain '\(fragment)'. Message: \(message)",
                file: file,
                line: line
            )
        }
    }

}

private struct SemanticRevealFixture {
    let window: UIWindow
    let scrollView: RevealingScrollView
    let target: SemanticActivationView
    let identifier: String
    let label: String
    let knownHeistId: HeistId
    let frameOrigin: CGPoint

    @MainActor
    func cleanup() {
        window.rootViewController?.view.accessibilityViewIsModal = false
        window.isHidden = true
        window.rootViewController = nil
    }
}

private struct TextInputRevealFixture {
    let window: UIWindow
    let scrollView: RevealingScrollView
    let target: UITextField
    let identifier: String
    let label: String
    let knownHeistId: HeistId
    let frameOrigin: CGPoint

    @MainActor
    func cleanup() {
        _ = target.resignFirstResponder()
        window.rootViewController?.view.accessibilityViewIsModal = false
        window.isHidden = true
        window.rootViewController = nil
    }
}

private struct NestedScrollRevealFixture {
    let window: UIWindow
    let outerScrollView: RevealingScrollView
    let innerScrollView: RevealingScrollView
    let target: SemanticActivationView
    let identifier: String
    let label: String
    let knownHeistId: HeistId
    let innerFrameOrigin: CGPoint
    let targetFrameOrigin: CGPoint

    @MainActor
    func cleanup() {
        window.rootViewController?.view.accessibilityViewIsModal = false
        window.isHidden = true
        window.rootViewController = nil
    }
}

private enum NestedScrollDecoy {
    case absent
    case separate(RevealingScrollView)
    case duplicateOuterReferenceAtDecoyPath(RevealingScrollView)
}

private struct ScrollDecoyFixture {
    let window: UIWindow
    let scrollView: RevealingScrollView

    @MainActor
    func cleanup() {
        window.isHidden = true
        window.rootViewController = nil
    }
}

private struct AmbiguousActivationFixture {
    let window: UIWindow
    let first: SemanticActivationView
    let second: SemanticActivationView

    @MainActor
    func cleanup() {
        window.rootViewController?.view.accessibilityViewIsModal = false
        window.isHidden = true
        window.rootViewController = nil
    }
}

private final class SemanticActivationView: UIView {
    private(set) var activationCount = 0

    override var accessibilityTraits: UIAccessibilityTraits {
        get { super.accessibilityTraits.union(.button) }
        set { super.accessibilityTraits = newValue.union(.button) }
    }

    override func accessibilityActivate() -> Bool {
        activationCount += 1
        return true
    }
}

private final class RefusingActivationTextField: UITextField {
    private(set) var resignationCount = 0

    override func accessibilityActivate() -> Bool {
        false
    }

    override func resignFirstResponder() -> Bool {
        resignationCount += 1
        return super.resignFirstResponder()
    }
}

private final class ActivatingTextField: UITextField {
    override func accessibilityActivate() -> Bool {
        becomeFirstResponder()
    }
}

@MainActor
private final class ProductTextInputKeyboardImpl: NSObject {
    private final class TextInputDelegate: NSObject, UIKeyInput {
        var hasText: Bool { false }
        func insertText(_ text: String) {}
        func deleteBackward() {}
    }

    private let inputDelegate = TextInputDelegate()
    private weak var textField: UITextField?
    private let onInput: @MainActor () -> Void

    init(textField: UITextField, onInput: @escaping @MainActor () -> Void) {
        self.textField = textField
        self.onInput = onInput
    }

    @objc(delegate)
    func delegate() -> AnyObject? {
        guard textField?.isFirstResponder == true else { return nil }
        return inputDelegate
    }

    @objc(addInputString:)
    func addInputString(_ text: NSString) {
        guard textField?.isFirstResponder == true else { return }
        let nextValue = (textField?.text ?? "") + (text as String)
        textField?.text = nextValue
        textField?.accessibilityValue = nextValue
        onInput()
    }

    @objc(taskQueue)
    func taskQueue() -> AnyObject? {
        self
    }

    @objc(waitUntilAllTasksAreFinished)
    func waitUntilAllTasksAreFinished() {}

    func bridge() -> KeyboardBridge {
        KeyboardBridge(
            impl: self,
            textInjection: UIKeyboardImplTextInjection(impl: self)
        )
    }
}

private final class RevealingScrollView: UIScrollView {
    var revealedElements: [UIView] = []
    var revealedContainers: [UIView] = []
    var onFirstRevealRequest: (() -> Void)?
    private(set) var revealRequestCount = 0
    var didReceiveRevealRequest: Bool { revealRequestCount > 0 }
    private let revealThreshold: CGFloat = 500

    override var contentOffset: CGPoint {
        didSet {
            updateAccessibilityVisibility()
        }
    }

    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        if contentOffset.y >= revealThreshold {
            if revealRequestCount == 0 {
                onFirstRevealRequest?()
            }
            revealRequestCount += 1
        }
        super.setContentOffset(contentOffset, animated: animated)
        updateAccessibilityVisibility(for: contentOffset)
    }

    func updateAccessibilityVisibility(for offset: CGPoint? = nil) {
        let isRevealed = (offset ?? contentOffset).y >= revealThreshold
        for container in revealedContainers {
            container.isHidden = !isRevealed
            container.accessibilityElementsHidden = !isRevealed
        }
        for element in revealedElements {
            element.isHidden = !isRevealed
            element.isAccessibilityElement = isRevealed
            element.accessibilityElementsHidden = !isRevealed
        }
    }
}

private extension ActionResult {
    var heistExecutionPayload: HeistExecutionResult? {
        guard case .heistExecution(let payload) = payload else { return nil }
        return payload
    }
}

#endif // canImport(UIKit)
