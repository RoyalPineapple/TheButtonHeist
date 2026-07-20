#if canImport(UIKit)
import ButtonHeistSupport
import ButtonHeistTestSupport
import XCTest
@testable import AccessibilitySnapshotParser
@_spi(ButtonHeistInternals) @testable import ThePlans
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

@MainActor
extension TheBrainsActionTests {

    func testActionEvidenceProjectorCaptureReturnsEmptySnapshotWhenRegistryEmpty() {
        let before = brains.actionEvidenceProjector.projectBaseline()
        XCTAssertTrue(before.elements.isEmpty,
                      "Elements should be empty when no hierarchy set")
    }

    func testActionEvidenceProjectorCaptureIncludesRegisteredElements() {
        let element = makeElement(label: "Title", traits: .header)
        let heistId: HeistId = "header_title"
        installScreen(elements: [(element, heistId)])

        let before = brains.actionEvidenceProjector.projectBaseline()
        XCTAssertEqual(before.observation.tree.orderedElements.count, 1)
        XCTAssertEqual(before.observation.tree.orderedElements.first?.heistId, heistId)
        XCTAssertEqual(before.elements.count, 1)
    }

    func testInteractionCoordinatorBeforeStateDoesNotReuseInvalidatedSettledObservation() async {
        installScreen(elements: [(makeElement(label: "Title", traits: .header), "header_title")])
        brains.vault.invalidateSettledObservationFromTripwire()

        let current = await withNoTraversableWindows {
            await brains.interactionCoordinator.admittedBaseline(timeout: 0.001)
        }

        XCTAssertNil(
            current,
            "invalidated settled observation must not be returned when no live tree is readable"
        )
    }

    func testExecuteIncrementFailsWhenElementIsNotAdjustable() async throws {
        let heistId: HeistId = "live_button"
        let liveObject = UIButton(type: .system)
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Live", traits: .button),
            object: liveObject
        )

        let target = try AccessibilityTarget.label("Live").resolve(in: .empty)
        let result = await brains.actions.executeIncrement(target)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .increment)
        XCTAssertDiagnostic(result.message, contains: [
            "adjustable action failed",
            "label=\"Live\"",
            "traits=[button]",
            "actions=[activate]",
            "try target an element with trait adjustable",
        ])
    }

    func testExecuteDecrementFailsWhenElementIsNotAdjustable() async throws {
        let heistId: HeistId = "live_button"
        let liveObject = UIButton(type: .system)
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Live", traits: .button),
            object: liveObject
        )

        let target = try AccessibilityTarget.label("Live").resolve(in: .empty)
        let result = await brains.actions.executeDecrement(target)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .decrement)
        XCTAssertDiagnostic(result.message, contains: [
            "adjustable action failed",
            "label=\"Live\"",
            "traits=[button]",
            "actions=[activate]",
            "try target an element with trait adjustable",
        ])
    }

    func testExecuteCustomActionMissingReportsAvailableCustomActions() async throws {
        let heistId: HeistId = "options_button"
        let liveObject = ActionActivationOverrideView()
        registerScreenElement(
            heistId: heistId,
            element: makeElement(
                label: "Options",
                traits: .button,
                customActions: ["Delete", "Archive"]
            ),
            object: liveObject
        )

        let result = await brains.actions.executeCustomAction(
            name: "Share",
            target: try AccessibilityTarget.label("Options").resolve(in: .empty)
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .customAction)
        XCTAssertDiagnostic(result.message, contains: [
            "custom action failed",
            "requestedAction=\"Share\"",
            "label=\"Options\"",
            "actions=[activate, Archive, Delete]",
            "try use one of custom actions [\"Archive\", \"Delete\"]",
        ])
    }

    func testExecuteCustomActionDeclinedReportsAlternatives() async throws {
        let heistId: HeistId = "options_button"
        let liveObject = ActionActivationOverrideView()
        liveObject.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Delete") { _ in false },
            UIAccessibilityCustomAction(name: "Archive") { _ in true },
        ]
        registerScreenElement(
            heistId: heistId,
            element: makeElement(
                label: "Options",
                traits: .button,
                customActions: ["Delete", "Archive"]
            ),
            object: liveObject
        )

        let result = await brains.actions.executeCustomAction(
            name: "Delete",
            target: try AccessibilityTarget.label("Options").resolve(in: .empty)
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .customAction)
        XCTAssertDiagnostic(result.message, contains: [
            "custom action failed",
            "requestedAction=\"Delete\" declined by handler",
            "label=\"Options\"",
            "actions=[activate, Archive, Delete]",
            "try use another custom action [\"Archive\"]",
        ])
    }

    func testExecuteCustomActionDispatchesLiveCustomAction() async throws {
        let heistId: HeistId = "live_custom_action_host"
        let liveObject = UIView()
        let customActionTarget = CustomActionTargetObject()
        liveObject.accessibilityCustomActions = [
            UIAccessibilityCustomAction(
                name: "Archive",
                target: customActionTarget,
                selector: #selector(CustomActionTargetObject.archive(_:))
            ),
        ]
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Options", traits: .button),
            object: liveObject
        )

        let result = await brains.actions.executeCustomAction(
            name: "Archive",
            target: try AccessibilityTarget.label("Options").resolve(in: .empty)
        )

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.method, .customAction)
        XCTAssertEqual(customActionTarget.invocationCount, 1)
    }

    func testExecuteCustomActionSelectorDeclineReportsFailure() async throws {
        let heistId: HeistId = "declining_custom_action_host"
        let liveObject = UIView()
        let customActionTarget = CustomActionTargetObject()
        liveObject.accessibilityCustomActions = [
            UIAccessibilityCustomAction(
                name: "Archive",
                target: customActionTarget,
                selector: #selector(CustomActionTargetObject.decline(_:))
            ),
        ]
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Options", traits: .button, customActions: ["Archive"]),
            object: liveObject
        )

        let result = await brains.actions.executeCustomAction(
            name: "Archive",
            target: try AccessibilityTarget.label("Options").resolve(in: .empty)
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .customAction)
        XCTAssertEqual(customActionTarget.invocationCount, 1)
        XCTAssertDiagnostic(result.message, contains: [
            "custom action failed",
            "requestedAction=\"Archive\" declined by handler",
            "label=\"Options\"",
        ])
    }

    func testExecuteActivateSucceedsForNoTraitElementWithActivationOverride() async throws {
        let rootView = UIView(frame: UIScreen.main.bounds)
        rootView.backgroundColor = .white
        let liveObject = ActionActivationOverrideView(
            frame: CGRect(x: 80, y: 180, width: 180, height: 44)
        )
        liveObject.isAccessibilityElement = true
        liveObject.accessibilityLabel = "Plain action"
        liveObject.accessibilityIdentifier = "plain_action"
        liveObject.accessibilityTraits = .none
        rootView.addSubview(liveObject)

        let window = try installModalWindow(rootView: rootView)
        defer {
            window.rootViewController?.view.accessibilityViewIsModal = false
            window.isHidden = true
        }
        await brains.tripwire.yieldFrames(3)

        let target = try AccessibilityTarget.identifier("plain_action").resolve(in: .empty)
        let result = await brains.actions.executeActivate(target)

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(liveObject.activationCount, 1)
    }

    func testExecuteActivateDispatchesNoTraitElementWithoutActivationImplementation() async throws {
        let heistId: HeistId = "plain_label"
        let liveObject = UIView()
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Plain label"),
            object: liveObject
        )

        let target = try AccessibilityTarget.label("Plain label").resolve(in: .empty)
        let result = await brains.actions.executeActivate(target)

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(result.activationTrace?.axActivateReturned, false)
        XCTAssertEqual(result.activationTrace?.implementsAccessibilityActivation, false)
        XCTAssertTrue(result.activationTrace?.tapActivationDispatched == true)
        XCTAssertEqual(result.activationTrace?.tapActivationSucceeded, true)
        XCTAssertEqual(result.subjectEvidence?.element.label, "Plain label")
        XCTAssertEqual(result.subjectEvidence?.element.actions, [])
    }

    func testExecuteCommandFailedActivateCarriesPostActionTraceLikeSuccessfulAction() async throws {
        brains.tripwire.startPulse()
        let rootView = UIView(frame: UIScreen.main.bounds)
        rootView.backgroundColor = .white

        let successful = ActionActivationOverrideView(frame: CGRect(x: 40, y: 140, width: 220, height: 44))
        successful.isAccessibilityElement = true
        successful.accessibilityLabel = "Trace Success"
        successful.accessibilityIdentifier = "trace_success"
        successful.accessibilityTraits = .button
        rootView.addSubview(successful)

        let failing = UIView(frame: CGRect(x: 40, y: 220, width: 220, height: 44))
        failing.isAccessibilityElement = true
        failing.accessibilityLabel = "Trace Failure"
        failing.accessibilityIdentifier = "trace_failure"
        failing.accessibilityTraits = .notEnabled
        rootView.addSubview(failing)

        let window = try installModalWindow(rootView: rootView)
        defer {
            brains.stopSemanticObservation()
            brains.tripwire.stopPulse()
            window.rootViewController?.view.accessibilityViewIsModal = false
            window.isHidden = true
        }
        await brains.tripwire.yieldFrames(3)

        let successCommand = try HeistActionCommand.activate(.identifier("trace_success")).resolve(in: .empty)
        let success = await brains.executeRuntimeAction(successCommand)
        XCTAssertTrue(success.outcome.isSuccess, success.message ?? "activate failed")
        XCTAssertNotNil(success.accessibilityTrace?.captures.last)

        let failureCommand = try HeistActionCommand.activate(.identifier("trace_failure")).resolve(in: .empty)
        let failure = await brains.executeRuntimeAction(failureCommand)
        XCTAssertFalse(failure.outcome.isSuccess)
        XCTAssertEqual(failure.method, .activate)
        let afterCapture = try XCTUnwrap(failure.accessibilityTrace?.captures.last)
        XCTAssertTrue(afterCapture.interface.projectedElements.contains {
            $0.identifier == "trace_failure"
        })
    }

    func testExecuteActivateBlocksDisabledElementWithActivationOverride() async throws {
        let heistId: HeistId = "disabled_action"
        let liveObject = ActionActivationOverrideView()
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Disabled action", traits: .notEnabled),
            object: liveObject
        )

        let target = try AccessibilityTarget.label("Disabled action").resolve(in: .empty)
        let result = await brains.actions.executeActivate(target)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .activate)
        XCTAssertTrue(result.message?.contains("disabled") ?? false)
        XCTAssertEqual(liveObject.activationCount, 0)
    }

    func testExecuteIncrementSucceedsWhenElementObjectIsLive() async throws {
        let heistId: HeistId = "live_slider"
        let liveObject = UISlider()
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Live", traits: .adjustable),
            object: liveObject
        )

        let target = try AccessibilityTarget.label("Live").resolve(in: .empty)
        let result = await brains.actions.executeIncrement(target)

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.method, .increment)
    }

    func testActionsExecuteIncrementUsesCurrentAccessibilityCaptureGeometry() async throws {
        let heistId: HeistId = "moving_slider"
        let staleObjectPoint = CGPoint(x: 20, y: 20)
        let staleObjectFrame = CGRect(x: 0, y: 0, width: 40, height: 40)
        let capturePoint = CGPoint(x: 190, y: 302)
        let captureFrame = CGRect(x: 150, y: 280, width: 80, height: 44)
        let element = AccessibilityElement.make(
            label: "Moving",
            traits: .adjustable,
            shape: .frame(AccessibilityRect(captureFrame)),
            activationPoint: capturePoint
        )
        let liveObject = AdjustableGeometryView(frame: staleObjectFrame, activationPoint: staleObjectPoint)
        installScreen(elements: [(element, heistId)], objects: [heistId: liveObject])

        let target = try AccessibilityTarget.label("Moving").resolve(in: .empty)
        let resolved = brains.vault.resolveTarget(target).resolvedElement
        let liveTarget: TheVault.LiveActionTarget?
        if let resolved,
           case .resolved(let target) = brains.vault.resolveLiveActionTarget(for: resolved) {
            liveTarget = target
        } else {
            liveTarget = nil
        }

        XCTAssertEqual(liveTarget?.frame, captureFrame)
        XCTAssertEqual(liveTarget?.activationPoint, capturePoint)
        XCTAssertNotEqual(liveTarget?.activationPoint, staleObjectPoint)

        let result = await brains.actions.executeIncrement(target)

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.method, .increment)
        XCTAssertEqual(liveObject.incrementCount, 1)
    }

    func testActionsExecuteIncrementUsesMatcherTargetBeforeLiveResolution() async throws {
        let heistId: HeistId = "quantity_stepper"
        let sourceElement = makeElement(
            label: "Quantity",
            value: "0",
            identifier: "quantity_stepper",
            traits: .adjustable
        )
        let sourceScreen = InterfaceObservation.makeForTests(elements: [(sourceElement, heistId)])
        let currentElement = makeElement(
            label: "Quantity",
            value: "1",
            identifier: "quantity_stepper",
            traits: .adjustable
        )
        let liveObject = AdjustableGeometryView(
            frame: CGRect(x: 80, y: 180, width: 180, height: 44),
            activationPoint: CGPoint(x: 170, y: 202)
        )
        brains.vault.installObservationForTesting(.makeForTests(
            elements: [(currentElement, heistId)],
            objects: [heistId: liveObject]
        ))
        let target = try matcherTarget(label: "Quantity", in: sourceScreen)

        let result = await brains.actions.executeIncrement(try target.resolve(in: .empty))

        XCTAssertTrue(result.success, result.message ?? "increment failed")
        XCTAssertEqual(result.method, .increment)
        XCTAssertEqual(liveObject.incrementCount, 1)
    }

    func testActionsExecuteIncrementUsesAccessibilityGeometryWhenObjectFrameIsMissing() async throws {
        let heistId: HeistId = "quantity_stepper"
        let sourceElement = makeElement(
            label: "Quantity",
            value: "0",
            identifier: "quantity_stepper",
            traits: .adjustable
        )
        let sourceScreen = InterfaceObservation.makeForTests(elements: [(sourceElement, heistId)])
        let currentElement = makeElement(
            label: "Quantity",
            value: "1",
            identifier: "quantity_stepper",
            traits: .adjustable
        )
        let liveObject = AdjustableGeometryView(frame: .zero, activationPoint: CGPoint(x: 170, y: 202))
        brains.vault.installObservationForTesting(.makeForTests(
            elements: [(currentElement, heistId)],
            objects: [heistId: liveObject]
        ))
        let target = try matcherTarget(label: "Quantity", in: sourceScreen)

        let result = await brains.actions.executeIncrement(try target.resolve(in: .empty))

        XCTAssertTrue(result.success, result.message ?? "increment failed")
        XCTAssertEqual(result.method, .increment)
        XCTAssertEqual(liveObject.incrementCount, 1)
    }

    func testHeistCommandsMatchSingleCommandMatcherFailures() async throws {
        let rootView = UIView(frame: UIScreen.main.bounds)
        rootView.backgroundColor = .white
        let marker = UILabel(frame: CGRect(x: 20, y: 80, width: 240, height: 44))
        marker.text = "Matcher Failure Fixture"
        marker.accessibilityLabel = "Matcher Failure Fixture"
        marker.isAccessibilityElement = true
        rootView.addSubview(marker)
        let window = try installModalWindow(rootView: rootView)
        defer {
            window.rootViewController?.view.accessibilityViewIsModal = false
            window.isHidden = true
        }
        await brains.tripwire.yieldFrames(2)

        let target = AccessibilityTarget.identifier("missing_target")
        let commands: [(String, HeistActionCommand)] = [
            ("activate", .activate(target)),
            ("custom action", .customAction(name: "Archive", target: target)),
            ("rotor", .rotor(selection: .named("Links"), target: target, direction: .next)),
            ("tap", .oneFingerTap(TapTarget(selection: .element(target)))),
            ("swipe", .swipe(SwipeTarget(selection: .elementDirection(target, .left)))),
            ("type text", .typeText(text: "hello", target: target)),
        ]

        for (label, authoredCommand) in commands {
            let command = try authoredCommand.resolve(in: .empty)
            brains.vault.resetInterfaceForLifecycle()
            let single = await brains.executeRuntimeAction(command)
            brains.vault.resetInterfaceForLifecycle()
            let heist = try await heistStepResult(
                for: .action(ActionStep(command: authoredCommand)),
                label: command.runtimeType.rawValue
            )
            assertSameActionResult(
                label,
                single: single,
                heist: heist
            )
        }

        let authoredWait = WaitStep(predicate: .exists(target), timeout: 0.01)
        brains.vault.resetInterfaceForLifecycle()
        let singleWait = await brains.performWait(step: try resolvedWait(authoredWait))
        brains.vault.resetInterfaceForLifecycle()
        let heistWait = try await heistStepResult(for: .wait(authoredWait), label: "wait")
        XCTAssertEqual(heistWait.outcome.isSuccess, singleWait.outcome.isSuccess)
        XCTAssertEqual(heistWait.method, singleWait.method)
        XCTAssertEqual(heistWait.outcome.failureKind, singleWait.outcome.failureKind)
    }

    func testHeistPlanDispatchesEveryDurableActionCommandThroughRuntime() async throws {
        let target = AccessibilityTarget.identifier("target")
        let point = GesturePointSelection.coordinate(ScreenPoint(x: 10, y: 20))
        let commands: [HeistActionCommand] = [
            .activate(target),
            .increment(target),
            .decrement(target),
            .customAction(name: "Archive", target: target),
            .rotor(selection: .named("Errors"), target: target, direction: .next),
            .typeText(text: "hello", target: target),
            .oneFingerTap(TapTarget(selection: point)),
            .longPress(LongPressTarget(selection: point)),
            .swipe(SwipeTarget(selection: .pointDirection(start: ScreenPoint(x: 20, y: 20), direction: .left))),
            .drag(DragTarget(start: .coordinate(ScreenPoint(x: 20, y: 20)), end: ScreenPoint(x: 80, y: 80))),
            .editAction(EditActionTarget(action: .paste)),
            .setPasteboard(SetPasteboardTarget(text: "clipboard")),
            .takeScreenshot,
            .dismissKeyboard,
        ]
        var dispatchedTypes: [HeistActionCommandType] = []
        let runtime = heistRuntime(observations: []) { command in
            dispatchedTypes.append(command.runtimeType)
            return ActionResult.success(
                payload: command.resultPayload,
                message: command.runtimeType.rawValue,
            )
        }
        let plan = try HeistPlan(body: commands.map { .action(ActionStep(command: $0)) })

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "heist failed")
        let expectedTypes = try commands.map {
            try $0.resolve(in: .empty).runtimeType
        }
        XCTAssertEqual(dispatchedTypes, expectedTypes)
        guard case .heist(let payload) = result.payload,
              let heistResult = payload else {
            return XCTFail("Expected heist execution payload")
        }
        XCTAssertEqual(heistResult.steps.count, commands.count)
        XCTAssertTrue(heistResult.steps.allSatisfy { $0.status == HeistExecutionStepStatus.passed })
    }

    func testFailedActivateHeistActionKeepsActivationTraceInActionEvidence() async throws {
        let activationTrace = ActivationTrace(.activationPointFallback(
            axActivateReturned: false,
            tapActivationPoint: ScreenPoint(x: 195, y: 139),
            tapActivationSucceeded: true
        ), implementsAccessibilityActivation: false)
        let target = AccessibilityTarget.label("Search all items")
        let command = HeistActionCommand.activate(target)
        let runtime = heistRuntime(observations: []) { _ in
            ActionResult.activationFailure(
                failureKind: .actionFailed,
                message: "text entry failed: observed focus=none keyboardVisible=false activeTextInput=false",
                observation: .none,
                activationTrace: activationTrace
            )
        }
        let plan = try HeistPlan(body: [.action(ActionStep(command: command))])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertFalse(result.outcome.isSuccess)
        guard case .heist(let payload) = result.payload,
              let heistResult = payload else {
            return XCTFail("Expected failed heist execution payload")
        }
        let step = try XCTUnwrap(heistResult.steps.first)
        XCTAssertEqual(step.actionEvidence?.dispatchResult?.activationTrace, activationTrace)
    }

    func testViewportDebugCommandsResolveForDirectRuntimeDispatch() throws {
        let target = AccessibilityTarget.identifier("target")
        let commands: [(HeistActionCommand, HeistActionCommandType)] = [
            (.scroll(ScrollTarget(direction: .down)), .scroll),
            (.scrollToVisible(target), .scrollToVisible),
            (.scrollToEdge(ScrollToEdgeTarget(edge: .bottom)), .scrollToEdge),
        ]

        for (command, expectedType) in commands {
            XCTAssertNotNil(command.durableHeistActionFailure)
            XCTAssertEqual(try command.resolve(in: .empty).runtimeType, expectedType)
        }
    }

    func testClearCacheResetsStash() {
        let element = makeElement(label: "Item")
        installScreen(elements: [(element, "test_id")])

        brains.vault.resetInterfaceForLifecycle()

        XCTAssertEqual(brains.vault.interfaceTree, .empty)
    }

    func testWaitTimesOutWhenAccessibilityTreeIsUnavailable() async throws {
        let step = WaitStep(predicate: .exists(.label("never")), timeout: try .milliseconds(1))
        let resolvedStep = try resolvedWait(step)
        let result = await withNoTraversableWindows {
            await brains.performWait(step: resolvedStep)
        }

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .wait)
        XCTAssertEqual(result.outcome.failureKind, .timeout)
    }

    func testActionsExecuteIncrementFailsWhenSemanticTargetHasNoLiveGeometry() async throws {
        let heistId: HeistId = "geometry_missing_slider"
        let element = AccessibilityElement.make(
            label: "Geometry Missing",
            traits: .adjustable,
            shape: .frame(.zero)
        )
        let liveObject = AdjustableGeometryView(
            frame: CGRect(x: 20, y: 20, width: 120, height: 44),
            activationPoint: CGPoint(x: 80, y: 42)
        )
        installScreen(elements: [(element, heistId)], objects: [heistId: liveObject])

        let target = try AccessibilityTarget.label("Geometry Missing").resolve(in: .empty)
        let resolved = brains.vault.resolveTarget(target).resolvedElement
        let liveTarget: TheVault.LiveActionTarget?
        if let resolved,
           case .resolved(let target) = brains.vault.resolveLiveActionTarget(for: resolved) {
            liveTarget = target
        } else {
            liveTarget = nil
        }
        let result = await brains.actions.executeIncrement(target)

        XCTAssertNotNil(resolved)
        XCTAssertNil(liveTarget)
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .increment)
        XCTAssertEqual(liveObject.incrementCount, 0)
        XCTAssertDiagnostic(result.message, contains: [
            "element inflation failed [geometryNotActionable]",
            "method=increment",
            "label=\"Geometry Missing\"",
            "fresh live geometry from element inflation",
        ])
    }

    func testActionsExecuteIncrementReResolvesReplacementObjectForCommittedHeistId() async throws {
        let heistId: HeistId = "refreshed_slider"
        let settledElement = AccessibilityElement.make(
            label: "Refreshed Slider",
            identifier: "refreshed_slider",
            traits: .adjustable,
            frame: CGRect(x: 10, y: 10, width: 120, height: 44),
            respondsToUserInteraction: false
        )
        let refreshedElement = AccessibilityElement.make(
            label: "Refreshed Slider",
            identifier: "refreshed_slider",
            traits: .adjustable,
            frame: CGRect(x: 80, y: 180, width: 180, height: 44),
            respondsToUserInteraction: false
        )
        let replacementObject = AdjustableGeometryView(
            frame: refreshedElement.bhFrame,
            activationPoint: refreshedElement.bhResolvedActivationPoint
        )
        do {
            let deallocatedObject = AdjustableGeometryView(
                frame: settledElement.bhFrame,
                activationPoint: settledElement.bhResolvedActivationPoint
            )
            installScreen(elements: [(settledElement, heistId)], objects: [heistId: deallocatedObject])
        }

        let target = try AccessibilityTarget.identifier("refreshed_slider").resolve(in: .empty)
        guard let committedTarget = brains.vault.resolveTarget(target).resolvedElement else {
            XCTFail("Expected committed semantic target to resolve")
            return
        }
        guard case .objectUnavailable = brains.vault.resolveLiveActionTarget(for: committedTarget) else {
            XCTFail("Expected the settled UIKit evidence to be held weakly")
            return
        }
        brains.vault.nextVisibleRefreshObservationForTesting = .makeForTests(
            elements: [(refreshedElement, heistId)],
            objects: [heistId: replacementObject]
        )

        let result = await brains.actions.executeIncrement(target)

        XCTAssertTrue(result.success, result.message ?? "increment failed")
        XCTAssertEqual(result.method, .increment)
        XCTAssertEqual(committedTarget.heistId, heistId)
        XCTAssertEqual(result.subjectEvidence?.element.identifier, heistId.rawValue)
        XCTAssertEqual(replacementObject.incrementCount, 1)
        XCTAssertEqual(brains.vault.interfaceElement(heistId: heistId)?.element.bhFrame, settledElement.bhFrame)
        guard case .resolved(let liveTarget) = brains.vault.resolveLiveActionTarget(for: committedTarget) else {
            XCTFail("Expected replacement live evidence for committed target")
            return
        }
        XCTAssertTrue(liveTarget.object === replacementObject)
        XCTAssertEqual(liveTarget.frame, refreshedElement.bhFrame)
    }

    func testActionsExecuteActivateRefreshesCommittedHeistIdBeforeSingleActivationAttempt() async throws {
        let heistId: HeistId = "refresh_activate"
        let settledElement = AccessibilityElement.make(
            label: "Refresh Activate",
            identifier: "refresh_activate",
            traits: .button,
            frame: CGRect(x: 40, y: 120, width: 180, height: 44)
        )
        let staleObject = RefusingActivationView(frame: settledElement.bhFrame)
        let replacementObject = ActionActivationOverrideView(frame: settledElement.bhFrame)
        installScreen(elements: [(settledElement, heistId)], objects: [heistId: staleObject])
        brains.vault.nextVisibleRefreshObservationForTesting = .makeForTests(
            elements: [(settledElement, heistId)],
            objects: [heistId: replacementObject]
        )

        let target = try AccessibilityTarget.identifier("refresh_activate").resolve(in: .empty)
        let result = await brains.actions.executeActivate(target)

        XCTAssertTrue(result.success, result.message ?? "activate failed")
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(result.subjectEvidence?.element.identifier, heistId.rawValue)
        XCTAssertEqual(replacementObject.activationCount, 1)
        XCTAssertEqual(staleObject.activationCount, 0)
    }

    func testActionsExecuteActivateKeepsCommittedHeistIdWhenOrdinalOrderChangesDuringRefresh() async throws {
        brains.stopSemanticObservation()
        let selectedId: HeistId = "selected_action"
        let otherId: HeistId = "other_action"
        let element = AccessibilityElement.make(
            label: "Repeated Action",
            traits: .button,
            frame: CGRect(x: 40, y: 120, width: 180, height: 44)
        )
        let selectedObject = ActionActivationOverrideView(frame: element.bhFrame)
        let otherObject = ActionActivationOverrideView(frame: element.bhFrame)
        installScreen(elements: [
            (element, selectedId),
            (element, otherId),
        ])

        let target = try AccessibilityTarget.target(
            .label("Repeated Action"),
            ordinal: 0
        ).resolve(in: .empty)
        let actionTask = Task { @MainActor in
            await brains.actions.executeActivate(target)
        }

        await waitForSettledSemanticWaiter(on: brains.vault)
        let reorderedScreen = InterfaceObservation.makeForTests(
            elements: [
                (element, otherId),
                (element, selectedId),
            ],
            objects: [
                selectedId: selectedObject,
                otherId: otherObject,
            ]
        )
        _ = brains.vault.semanticObservationStream.commitVisibleObservationForTesting(reorderedScreen)
        brains.vault.nextVisibleRefreshObservationForTesting = reorderedScreen

        let result = await actionTask.value

        XCTAssertTrue(result.success, result.message ?? "activate failed")
        XCTAssertEqual(result.resolvedElementId, selectedId)
        XCTAssertEqual(selectedObject.activationCount, 1)
        XCTAssertEqual(otherObject.activationCount, 0)
    }

}

#endif
