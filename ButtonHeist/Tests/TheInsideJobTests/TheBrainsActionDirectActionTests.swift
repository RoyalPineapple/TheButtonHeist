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

    func testInteractionCoordinatorDoesNotReuseInvalidatedSettledObservation() async {
        await installScreen(elements: [(makeElement(label: "Title", traits: .header), "header_title")])
        await brains.vault.semanticObservationStream.invalidateCurrentAdmission()
        visibleObservationSource.observation = nil

        let current = await withNoTraversableWindows {
            await brains.interactionCoordinator.admittedVisibleObservation(timeout: 0.001)
        }

        XCTAssertNil(
            current,
            "invalidated settled observation must not be returned when no live tree is readable"
        )
    }

    func testExecuteIncrementFailsWhenElementIsNotAdjustable() async throws {
        let heistId: HeistId = "live_button"
        let liveObject = UIButton(type: .system)
        await registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Live", traits: .button),
            object: liveObject
        )

        let target = try AccessibilityTarget.label("Live").resolve(in: .empty)
        var timing = ActionTiming()
        let result = await brains.actions.executeIncrement(target, timing: &timing)

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
        await registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Live", traits: .button),
            object: liveObject
        )

        let target = try AccessibilityTarget.label("Live").resolve(in: .empty)
        var timing = ActionTiming()
        let result = await brains.actions.executeDecrement(target, timing: &timing)

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
        await registerScreenElement(
            heistId: heistId,
            element: makeElement(
                label: "Options",
                traits: .button,
                customActions: ["Delete", "Archive"]
            ),
            object: liveObject
        )

        var timing = ActionTiming()

        let result = await brains.actions.executeCustomAction(
            name: "Share",
            target: try AccessibilityTarget.label("Options").resolve(in: .empty),
            timing: &timing
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
        await registerScreenElement(
            heistId: heistId,
            element: makeElement(
                label: "Options",
                traits: .button,
                customActions: ["Delete", "Archive"]
            ),
            object: liveObject
        )

        var timing = ActionTiming()

        let result = await brains.actions.executeCustomAction(
            name: "Delete",
            target: try AccessibilityTarget.label("Options").resolve(in: .empty),
            timing: &timing
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
        await registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Options", traits: .button),
            object: liveObject
        )

        var timing = ActionTiming()

        let result = await brains.actions.executeCustomAction(
            name: "Archive",
            target: try AccessibilityTarget.label("Options").resolve(in: .empty),
            timing: &timing
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
        await registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Options", traits: .button, customActions: ["Archive"]),
            object: liveObject
        )

        var timing = ActionTiming()

        let result = await brains.actions.executeCustomAction(
            name: "Archive",
            target: try AccessibilityTarget.label("Options").resolve(in: .empty),
            timing: &timing
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
        var timing = ActionTiming()
        let result = await brains.actions.executeActivate(target, timing: &timing)

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(liveObject.activationCount, 1)
    }

    func testProductionActionDispatchReportsOwnedPhaseTiming() async throws {
        let rootView = UIView(frame: UIScreen.main.bounds)
        rootView.backgroundColor = .white
        let liveObject = ActionActivationOverrideView(
            frame: CGRect(x: 80, y: 180, width: 180, height: 44)
        )
        liveObject.isAccessibilityElement = true
        liveObject.accessibilityLabel = "Timed action"
        liveObject.accessibilityIdentifier = "timed_action"
        liveObject.accessibilityTraits = .button
        rootView.addSubview(liveObject)

        let window = try installModalWindow(rootView: rootView)
        defer {
            window.rootViewController?.view.accessibilityViewIsModal = false
            window.isHidden = true
        }
        await brains.tripwire.yieldFrames(3)

        let command = try HeistActionCommand.activate(.identifier("timed_action"))
            .resolve(in: .empty)
        let result = await brains.executeRuntimeAction(command)
        let timing = try XCTUnwrap(result.timing)

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "activate failed")
        let targetResolution = try XCTUnwrap(timing.targetResolutionMs)
        let actionDispatch = try XCTUnwrap(timing.actionDispatchMs)
        let interaction = try XCTUnwrap(timing.interactionMs)
        let total = try XCTUnwrap(timing.totalMs)
        XCTAssertGreaterThanOrEqual(interaction.milliseconds, targetResolution.milliseconds)
        XCTAssertGreaterThanOrEqual(interaction.milliseconds, actionDispatch.milliseconds)
        for phase in [targetResolution, actionDispatch, interaction] {
            XCTAssertGreaterThanOrEqual(total.milliseconds, phase.milliseconds)
        }
        XCTAssertEqual(liveObject.activationCount, 1)
    }

    func testExecuteActivateDispatchesNoTraitElementWithoutActivationImplementation() async throws {
        let heistId: HeistId = "plain_label"
        let liveObject = UIView()
        await registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Plain label"),
            object: liveObject
        )

        let target = try AccessibilityTarget.label("Plain label").resolve(in: .empty)
        var timing = ActionTiming()
        let result = await brains.actions.executeActivate(target, timing: &timing)

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(result.activationTrace?.axActivateReturned, false)
        XCTAssertEqual(result.activationTrace?.implementsAccessibilityActivation, false)
        XCTAssertTrue(result.activationTrace?.tapActivationDispatched == true)
        XCTAssertEqual(result.activationTrace?.tapActivationSucceeded, true)
        XCTAssertEqual(result.subjectEvidence?.element.semantics.assertable.label, "Plain label")
        XCTAssertEqual(result.subjectEvidence?.element.semantics.assertable.actions, [])
    }

    func testExecuteCommandFailedActivateCarriesPostActionObservationLikeSuccessfulAction() async throws {
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

        let success = await brains.executeSingleStepPlan(
            try HeistPlan(body: [
                .action(ActionStep(command: .activate(.identifier("trace_success")))),
            ]),
            fallbackPayload: .activate
        )
        XCTAssertTrue(success.outcome.isSuccess, success.message ?? "activate failed")
        let successObservation = try XCTUnwrap(success.observationEvidence)
        XCTAssertEqual(successObservation.completeness, .complete)
        XCTAssertNotNil(successObservation.current)

        let failure = await brains.executeSingleStepPlan(
            try HeistPlan(body: [
                .action(ActionStep(command: .activate(.identifier("trace_failure")))),
            ]),
            fallbackPayload: .activate
        )
        XCTAssertFalse(failure.outcome.isSuccess)
        XCTAssertEqual(failure.method, .activate)
        let failureObservation = try XCTUnwrap(failure.observationEvidence)
        XCTAssertEqual(failureObservation.completeness, .complete)
        let current = try XCTUnwrap(failureObservation.current)
        XCTAssertTrue(current.interface.projectedElements.contains {
            $0.semantics.assertable.identifier == "trace_failure"
        })
    }

    func testExecuteActivateBlocksDisabledElementWithActivationOverride() async throws {
        let heistId: HeistId = "disabled_action"
        let liveObject = ActionActivationOverrideView()
        await registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Disabled action", traits: .notEnabled),
            object: liveObject
        )

        let target = try AccessibilityTarget.label("Disabled action").resolve(in: .empty)
        var timing = ActionTiming()
        let result = await brains.actions.executeActivate(target, timing: &timing)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .activate)
        XCTAssertTrue(result.message?.contains("disabled") ?? false)
        XCTAssertEqual(liveObject.activationCount, 0)
    }

    func testExecuteIncrementSucceedsWhenElementObjectIsLive() async throws {
        let heistId: HeistId = "live_slider"
        let liveObject = UISlider()
        await registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Live", traits: .adjustable),
            object: liveObject
        )

        let target = try AccessibilityTarget.label("Live").resolve(in: .empty)
        var timing = ActionTiming()
        let result = await brains.actions.executeIncrement(target, timing: &timing)

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
        await installScreen(elements: [(element, heistId)], objects: [heistId: liveObject])

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

        var timing = ActionTiming()

        let result = await brains.actions.executeIncrement(target, timing: &timing)

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
        await installSyntheticObservation(.makeForTests(
            elements: [(currentElement, heistId)],
            objects: [heistId: liveObject]
        ))
        let target = try matcherTarget(label: "Quantity", in: sourceScreen)

        var timing = ActionTiming()

        let result = await brains.actions.executeIncrement(try target.resolve(in: .empty), timing: &timing)

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
        await installSyntheticObservation(.makeForTests(
            elements: [(currentElement, heistId)],
            objects: [heistId: liveObject]
        ))
        let target = try matcherTarget(label: "Quantity", in: sourceScreen)

        var timing = ActionTiming()

        let result = await brains.actions.executeIncrement(try target.resolve(in: .empty), timing: &timing)

        XCTAssertTrue(result.success, result.message ?? "increment failed")
        XCTAssertEqual(result.method, .increment)
        XCTAssertEqual(liveObject.incrementCount, 1)
    }

    func testHeistCommandsMatchSingleCommandMatcherFailures() async throws {
        let fixtureElements: [(AccessibilityElement, HeistId)] = [
            (makeElement(label: "Matcher Failure Fixture"), "matcher_failure_fixture"),
        ]
        await installScreen(elements: fixtureElements)

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
            await brains.vault.resetInterfaceForLifecycle()
            let single = await brains.executeRuntimeAction(command)
            await brains.vault.resetInterfaceForLifecycle()
            let heist = try await heistStepResult(
                for: .action(ActionStep(command: authoredCommand)),
                label: authoredCommand.wireType.rawValue
            )
            assertSameActionResult(
                label,
                single: single,
                heist: heist
            )
        }

        brains.tripwire.stopPulse()
        defer { brains.tripwire.startPulse() }
        let authoredWait = WaitStep(predicate: .exists(target), timeout: 0.01)
        await brains.vault.resetInterfaceForLifecycle()
        await installScreen(elements: fixtureElements)
        let singleWait = await brains.performWait(step: authoredWait)
        await brains.vault.resetInterfaceForLifecycle()
        await installScreen(elements: fixtureElements)
        let heistWait = try await heistStepResult(
            for: .wait(authoredWait),
            label: "wait"
        )
        XCTAssertEqual(heistWait.outcome.isSuccess, singleWait.outcome.isSuccess)
        XCTAssertEqual(heistWait.method, singleWait.method)
        XCTAssertEqual(heistWait.outcome.failureKind, singleWait.outcome.failureKind)
    }

    func testHeistMachineDispatchesEveryDurableActionCommandThroughTypedRequests() throws {
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
        let plan = try HeistPlan(body: commands.map { .action(ActionStep(command: $0)) })
        var driver = try HeistMachineTestDriver(
            plan: plan,
            script: MachineRunScript(
                events: Array(repeating: [.noChange, .noChange], count: commands.count)
                    .flatMap { $0 }
            )
        )

        let completion = try driver.run()

        let expectedCommands = try commands.map { try $0.resolve(in: .empty) }
        XCTAssertEqual(driver.requests.compactMap(\.dispatchedCommand), expectedCommands)
        XCTAssertEqual(completion.steps.count, commands.count)
        XCTAssertTrue(completion.steps.allSatisfy { $0.status == .passed })
    }

    func testFailedActivateHeistActionKeepsActivationTraceInActionEvidence() throws {
        let activationTrace = ActivationTrace(.activationPointFallback(
            axActivateReturned: false,
            tapActivationPoint: ScreenPoint(x: 195, y: 139),
            tapActivationSucceeded: true
        ), implementsAccessibilityActivation: false)
        let target = AccessibilityTarget.label("Search all items")
        let command = HeistActionCommand.activate(target)
        let plan = try HeistPlan(body: [.action(ActionStep(command: command))])
        var driver = try HeistMachineTestDriver(
            plan: plan,
            script: MachineRunScript(
                events: [.noChange],
                dispatchResults: [
                    .failure(
                        .activate,
                        message: "text entry failed: observed focus=none "
                            + "keyboardVisible=false activeTextInput=false",
                        activationTrace: activationTrace
                    ),
                ]
            )
        )

        let completion = try driver.run()
        let step = try XCTUnwrap(completion.steps.first)

        XCTAssertEqual(step.status, .failed)
        XCTAssertEqual(step.actionEvidence?.result?.activationTrace, activationTrace)
    }

    func testViewportDebugCommandsResolveForDirectRuntimeDispatch() async throws {
        let target = AccessibilityTarget.identifier("target")
        let commands: [(HeistActionCommand, HeistActionCommandType)] = [
            (.scroll(ScrollTarget(direction: .down)), .scroll),
            (.scrollToVisible(target), .scrollToVisible),
            (.scrollToEdge(ScrollToEdgeTarget(edge: .bottom)), .scrollToEdge),
        ]

        for (command, expectedType) in commands {
            XCTAssertNotNil(command.durableHeistActionFailure)
            XCTAssertNoThrow(try command.resolve(in: .empty))
            XCTAssertEqual(command.wireType, expectedType)
        }
    }

    func testClearCacheResetsStash() async {
        let element = makeElement(label: "Item")
        await installScreen(elements: [(element, "test_id")])

        await brains.vault.resetInterfaceForLifecycle()

        XCTAssertEqual(brains.vault.interfaceTree, .empty)
    }

    func testWaitReportsUnavailableAccessibilityTreeAtItsBaselineBoundary() async throws {
        let step = WaitStep(predicate: .exists(.label("never")), timeout: try .milliseconds(1))
        let result = await withNoTraversableWindows {
            await brains.performWait(step: step)
        }

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .wait)
        XCTAssertEqual(result.outcome.failureKind, .accessibilityTreeUnavailable)
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
        await installScreen(elements: [(element, heistId)], objects: [heistId: liveObject])

        let target = try AccessibilityTarget.label("Geometry Missing").resolve(in: .empty)
        let resolved = brains.vault.resolveTarget(target).resolvedElement
        let liveTarget: TheVault.LiveActionTarget?
        if let resolved,
           case .resolved(let target) = brains.vault.resolveLiveActionTarget(for: resolved) {
            liveTarget = target
        } else {
            liveTarget = nil
        }
        var timing = ActionTiming()
        let result = await brains.actions.executeIncrement(target, timing: &timing)

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
            await installScreen(elements: [(settledElement, heistId)], objects: [heistId: deallocatedObject])
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
        visibleObservationSource.observation = .makeForTests(
            elements: [(refreshedElement, heistId)],
            objects: [heistId: replacementObject]
        )

        var timing = ActionTiming()

        let result = await brains.actions.executeIncrement(target, timing: &timing)

        XCTAssertTrue(result.success, result.message ?? "increment failed")
        XCTAssertEqual(result.method, .increment)
        XCTAssertEqual(committedTarget.heistId, heistId)
        XCTAssertEqual(result.subjectEvidence?.element.semantics.assertable.identifier, heistId.rawValue)
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
        await installScreen(elements: [(settledElement, heistId)], objects: [heistId: staleObject])
        visibleObservationSource.observation = .makeForTests(
            elements: [(settledElement, heistId)],
            objects: [heistId: replacementObject]
        )

        let target = try AccessibilityTarget.identifier("refresh_activate").resolve(in: .empty)
        var timing = ActionTiming()
        let result = await brains.actions.executeActivate(target, timing: &timing)

        XCTAssertTrue(result.success, result.message ?? "activate failed")
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(result.subjectEvidence?.element.semantics.assertable.identifier, heistId.rawValue)
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
        await installScreen(elements: [
            (element, selectedId),
            (element, otherId),
        ])

        let target = try AccessibilityTarget.target(
            .label("Repeated Action"),
            ordinal: 0
        ).resolve(in: .empty)
        let actionTask = Task { @MainActor in
            var timing = ActionTiming()
            return await brains.actions.executeActivate(target, timing: &timing)
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
        _ = await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(reorderedScreen)
        visibleObservationSource.observation = reorderedScreen

        let result = await actionTask.value

        XCTAssertTrue(result.success, result.message ?? "activate failed")
        XCTAssertEqual(result.resolvedElementId, selectedId)
        XCTAssertEqual(selectedObject.activationCount, 1)
        XCTAssertEqual(otherObject.activationCount, 0)
    }

}

private extension HeistExecution.MainActorRequest {
    var dispatchedCommand: ResolvedHeistActionCommand? {
        guard case .dispatch(_, let command) = self else { return nil }
        return command
    }
}

#endif
