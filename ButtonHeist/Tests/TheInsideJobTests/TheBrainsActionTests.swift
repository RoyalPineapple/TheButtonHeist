#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

private final class ActionActivationOverrideView: UIView {
    private(set) var activationCount = 0

    override func accessibilityActivate() -> Bool {
        activationCount += 1
        return true
    }
}

private final class RefusingActivationView: UIView {
    override func accessibilityActivate() -> Bool {
        false
    }
}

private final class CustomActionTargetObject: NSObject {
    private(set) var invocationCount = 0

    @objc func archive(_ action: UIAccessibilityCustomAction) -> Bool {
        invocationCount += 1
        return true
    }
}

private final class ActionGeometryView: UIView {
    private let testActivationPoint: CGPoint

    init(activationPoint: CGPoint) {
        self.testActivationPoint = activationPoint
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var accessibilityActivationPoint: CGPoint {
        get { testActivationPoint }
        set {}
    }
}

private final class AdjustableGeometryView: UIView {
    private let testActivationPoint: CGPoint
    private(set) var incrementCount = 0

    init(frame: CGRect, activationPoint: CGPoint) {
        self.testActivationPoint = activationPoint
        super.init(frame: frame)
        accessibilityFrame = frame
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var accessibilityActivationPoint: CGPoint {
        get { testActivationPoint }
        set {}
    }

    override func accessibilityIncrement() {
        incrementCount += 1
    }
}

@MainActor
final class TheBrainsActionTests: XCTestCase {

    private var brains: TheBrains!

    override func setUp() async throws {
        try await super.setUp()
        brains = TheBrains(tripwire: TheTripwire())
    }

    override func tearDown() async throws {
        brains.stopSemanticObservation()
        brains = nil
        try await super.tearDown()
    }

    // MARK: - Post-Action Observation Capture

    func testPostActionObservationCaptureReturnsEmptySnapshotWhenRegistryEmpty() {
        let before = brains.postActionObservation.captureSemanticState()
        XCTAssertTrue(before.snapshot.isEmpty,
                      "Snapshot should be empty when no elements in registry")
        XCTAssertTrue(before.elements.isEmpty,
                      "Elements should be empty when no hierarchy set")
    }

    func testPostActionObservationCaptureIncludesRegisteredElements() {
        let element = makeElement(label: "Title", traits: .header)
        let heistId = "header_title"
        installScreen(elements: [(element, heistId)])

        let before = brains.postActionObservation.captureSemanticState()
        XCTAssertEqual(before.snapshot.count, 1)
        XCTAssertEqual(before.snapshot.first?.heistId, heistId)
        XCTAssertEqual(before.elements.count, 1)
    }

    func testExecuteIncrementFailsWhenElementIsNotAdjustable() async {
        let heistId = "live_button"
        let liveObject = UIButton(type: .system)
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Live", traits: .button),
            object: liveObject
        )

        let result = await brains.actions.executeIncrement(.predicate(ElementPredicate(label: "Live")))

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .increment)
        XCTAssertDiagnostic(result.message, contains: [
            "adjustable action failed",
            "heistId=\"live_button\"",
            "label=\"Live\"",
            "traits=[button]",
            "actions=[activate]",
            "try target an element with trait adjustable",
        ])
    }

    func testExecuteDecrementFailsWhenElementIsNotAdjustable() async {
        let heistId = "live_button"
        let liveObject = UIButton(type: .system)
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Live", traits: .button),
            object: liveObject
        )

        let result = await brains.actions.executeDecrement(.predicate(ElementPredicate(label: "Live")))

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .decrement)
        XCTAssertDiagnostic(result.message, contains: [
            "adjustable action failed",
            "heistId=\"live_button\"",
            "label=\"Live\"",
            "traits=[button]",
            "actions=[activate]",
            "try target an element with trait adjustable",
        ])
    }

    func testExecuteCustomActionMissingReportsAvailableCustomActions() async {
        let heistId = "options_button"
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
            CustomActionTarget(elementTarget: .predicate(ElementPredicate(label: "Options")), actionName: "Share")
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .customAction)
        XCTAssertDiagnostic(result.message, contains: [
            "custom action failed",
            "requestedAction=\"Share\"",
            "heistId=\"options_button\"",
            "label=\"Options\"",
            "actions=[activate, Delete, Archive]",
            "try use one of custom actions [\"Delete\", \"Archive\"]",
        ])
    }

    func testExecuteCustomActionDeclinedReportsAlternatives() async {
        let heistId = "options_button"
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
            CustomActionTarget(elementTarget: .predicate(ElementPredicate(label: "Options")), actionName: "Delete")
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .customAction)
        XCTAssertDiagnostic(result.message, contains: [
            "custom action failed",
            "requestedAction=\"Delete\" declined by handler",
            "heistId=\"options_button\"",
            "label=\"Options\"",
            "actions=[activate, Delete, Archive]",
            "try use another custom action [\"Archive\"]",
        ])
    }

    func testExecuteCustomActionDispatchesLiveCustomAction() async {
        let heistId = "live_custom_action_host"
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
            CustomActionTarget(elementTarget: .predicate(ElementPredicate(label: "Options")), actionName: "Archive")
        )

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.method, .customAction)
        XCTAssertEqual(customActionTarget.invocationCount, 1)
    }

    func testExecuteActivateSucceedsForNoTraitElementWithActivationOverride() async {
        let heistId = "plain_action"
        let liveObject = ActionActivationOverrideView()
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Plain action"),
            object: liveObject
        )

        let result = await brains.actions.executeActivate(.predicate(ElementPredicate(label: "Plain action")))

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(liveObject.activationCount, 1)
    }

    func testExecuteActivateFailsForNoTraitElementWithoutActivationSignal() async {
        let heistId = "plain_label"
        let liveObject = UIView()
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Plain label"),
            object: liveObject
        )

        let result = await brains.actions.executeActivate(.predicate(ElementPredicate(label: "Plain label")))

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .activate)
        XCTAssertDiagnostic(result.message, contains: [
            "activate failed",
            "heistId=\"plain_label\"",
            "label=\"Plain label\"",
            "actions=[]",
            "try retarget an element whose actions include activate",
        ])
    }

    func testExecuteActivateBlocksDisabledElementWithActivationOverride() async {
        let heistId = "disabled_action"
        let liveObject = ActionActivationOverrideView()
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Disabled action", traits: .notEnabled),
            object: liveObject
        )

        let result = await brains.actions.executeActivate(.predicate(ElementPredicate(label: "Disabled action")))

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .activate)
        XCTAssertTrue(result.message?.contains("disabled") ?? false)
        XCTAssertEqual(liveObject.activationCount, 0)
    }

    func testExecuteIncrementSucceedsWhenElementObjectIsLive() async {
        let heistId = "live_slider"
        let liveObject = UISlider()
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Live", traits: .adjustable),
            object: liveObject
        )

        let result = await brains.actions.executeIncrement(.predicate(ElementPredicate(label: "Live")))

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.method, .increment)
    }

    func testElementActionUsesCurrentAccessibilityCaptureGeometry() async {
        let heistId = "moving_slider"
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

        let resolved = brains.stash.resolveTarget(.predicate(ElementPredicate(label: "Moving"))).resolved
        let liveTarget: TheStash.LiveActionTarget?
        if let resolved,
           case .resolved(let target) = brains.stash.resolveLiveActionTarget(for: resolved) {
            liveTarget = target
        } else {
            liveTarget = nil
        }

        XCTAssertEqual(liveTarget?.frame, captureFrame)
        XCTAssertEqual(liveTarget?.activationPoint, capturePoint)
        XCTAssertNotEqual(liveTarget?.activationPoint, staleObjectPoint)

        let result = await brains.actions.executeIncrement(.predicate(ElementPredicate(label: "Moving")))

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.method, .increment)
        XCTAssertEqual(liveObject.incrementCount, 1)
    }

    func testElementActionUsesMatcherTargetBeforeLiveResolution() async throws {
        let sourceElement = makeElement(
            label: "Quantity",
            value: "0",
            identifier: "quantity_stepper",
            traits: .adjustable
        )
        let sourceScreen = Screen.makeForTests(elements: [(sourceElement, "quantity_0")])
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
        brains.stash.installScreenForTesting(.makeForTests(
            elements: [(currentElement, "quantity_1")],
            objects: ["quantity_1": liveObject]
        ))
        let target = try matcherTarget(label: "Quantity", in: sourceScreen)

        let result = await brains.actions.executeIncrement(target)

        XCTAssertTrue(result.success, result.message ?? "increment failed")
        XCTAssertEqual(result.method, .increment)
        XCTAssertEqual(liveObject.incrementCount, 1)
    }

    func testElementActionSemanticTargetUsesAccessibilityGeometryWhenObjectFrameIsMissing() async throws {
        let sourceElement = makeElement(
            label: "Quantity",
            value: "0",
            identifier: "quantity_stepper",
            traits: .adjustable
        )
        let sourceScreen = Screen.makeForTests(elements: [(sourceElement, "quantity_0")])
        let currentElement = makeElement(
            label: "Quantity",
            value: "1",
            identifier: "quantity_stepper",
            traits: .adjustable
        )
        let liveObject = AdjustableGeometryView(frame: .zero, activationPoint: CGPoint(x: 170, y: 202))
        brains.stash.installScreenForTesting(.makeForTests(
            elements: [(currentElement, "quantity_1")],
            objects: ["quantity_1": liveObject]
        ))
        let target = try matcherTarget(label: "Quantity", in: sourceScreen)

        let result = await brains.actions.executeIncrement(target)

        XCTAssertTrue(result.success, result.message ?? "increment failed")
        XCTAssertEqual(result.method, .increment)
        XCTAssertEqual(liveObject.incrementCount, 1)
    }

    func testHeistCommandsMatchSingleCommandMatcherFailures() async {
        let matcher = ElementPredicate(identifier: "missing_target")
        let target = ElementTarget.predicate(matcher)
        let commands: [(String, ClientMessage, Bool)] = [
            ("activate", .activate(target), false),
            ("custom action", .performCustomAction(CustomActionTarget(
                elementTarget: target,
                actionName: "Archive"
            )), false),
            ("rotor", .rotor(RotorTarget(elementTarget: target, selection: .named("Links"))), false),
            ("tap", .oneFingerTap(TapTarget(selection: .element(target))), false),
            ("swipe", .swipe(SwipeTarget(selection: .elementDirection(target, .left))), false),
            ("type text", .typeText(TypeTextTarget(text: "hello", elementTarget: target)), false),
            ("scroll", .scroll(ScrollTarget(elementTarget: target, direction: .down)), false),
            ("wait", .wait(WaitTarget(predicate: .state(.present(matcher)), timeout: 0.01)), true),
        ]

        for (label, command, normalizingTimeoutDuration) in commands {
            let single = await brains.executeCommand(command)
            let heist = await heistStepResult(for: command)
            assertSameActionResult(
                label,
                single: single,
                heist: heist,
                normalizingTimeoutDuration: normalizingTimeoutDuration
            )
        }
    }

    func testHeistConditionalSelectsFirstMatchingCaseOnce() async throws {
        let runtime = heistRuntime(observations: [
            observedState(labels: ["Home", "Login"]),
        ])
        let plan = HeistPlan(steps: [
            .conditional(try ConditionalStep(cases: [
                PredicateCase(
                    predicate: .state(.present(ElementPredicate(label: "Home"))),
                    steps: [.warn(WarnStep(message: "home flow"))]
                ),
                PredicateCase(
                    predicate: .state(.present(ElementPredicate(label: "Login"))),
                    steps: [.fail(FailStep(message: "wrong branch"))]
                ),
            ])),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.success)
        XCTAssertEqual(step.kind, .conditional)
        XCTAssertEqual(step.caseSelection?.selectedCaseIndex, 0)
        XCTAssertEqual(step.childResults?.map(\.kind), [.warn])
    }

    func testHeistConditionalUnmatchedWithoutElseContinues() async throws {
        let runtime = heistRuntime(observations: [
            observedState(labels: ["Settings"]),
        ])
        let plan = HeistPlan(steps: [
            .conditional(try ConditionalStep(cases: [
                PredicateCase(
                    predicate: .state(.present(ElementPredicate(label: "Home"))),
                    steps: [.fail(FailStep(message: "should not run"))]
                ),
            ])),
            .warn(WarnStep(message: "continued")),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)

        XCTAssertTrue(result.success)
        XCTAssertEqual(heist.steps.map(\.kind), [.conditional, .warn])
        XCTAssertEqual(heist.steps.first?.caseSelection?.selectedCaseIndex, nil)
    }

    func testHeistWaitForCasesTimeoutWithoutElseFails() async throws {
        let runtime = heistRuntime(observations: [
            observedState(labels: ["Settings"]),
        ])
        let plan = HeistPlan(steps: [
            .waitForCases(try WaitForCasesStep(
                timeout: 0,
                cases: [
                    PredicateCase(
                        predicate: .state(.present(ElementPredicate(label: "Home"))),
                        steps: [.warn(WarnStep(message: "home flow"))]
                    ),
                ]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertFalse(result.success)
        XCTAssertEqual(step.kind, .waitForCases)
        XCTAssertEqual(step.caseSelection?.timedOut, true)
        XCTAssertEqual(step.caseSelection?.elseRan, false)
    }

    func testHeistWaitForCasesTimeoutWithElseRunsElse() async throws {
        let runtime = heistRuntime(observations: [
            observedState(labels: ["Settings"]),
        ])
        let plan = HeistPlan(steps: [
            .waitForCases(try WaitForCasesStep(
                timeout: 0,
                cases: [
                    PredicateCase(
                        predicate: .state(.present(ElementPredicate(label: "Home"))),
                        steps: [.fail(FailStep(message: "should not run"))]
                    ),
                ],
                elseSteps: [.warn(WarnStep(message: "no known state appeared"))]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.success)
        XCTAssertEqual(step.caseSelection?.timedOut, true)
        XCTAssertEqual(step.caseSelection?.elseRan, true)
        XCTAssertEqual(step.childResults?.map(\.kind), [.warn])
    }

    func testHeistWaitForCasesPollsUntilCaseMatches() async throws {
        let runtime = heistRuntime(observations: [
            observedState(labels: ["Loading"]),
            observedState(labels: ["Home"]),
        ])
        let plan = HeistPlan(steps: [
            .waitForCases(try WaitForCasesStep(
                timeout: 1,
                cases: [
                    PredicateCase(
                        predicate: .state(.present(ElementPredicate(label: "Home"))),
                        steps: [.warn(WarnStep(message: "home flow"))]
                    ),
                ]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.success)
        XCTAssertEqual(step.caseSelection?.selectedCaseIndex, 0)
        XCTAssertEqual(step.childResults?.map(\.kind), [.warn])
    }

    func testHeistWaitForCasesContinuesAfterUnavailableObservation() async throws {
        let runtime = heistRuntime(
            observations: [observedState(labels: ["Home"])],
            unavailableObservationCount: 1
        )
        let plan = HeistPlan(steps: [
            .waitForCases(try WaitForCasesStep(
                timeout: 1,
                cases: [
                    PredicateCase(
                        predicate: .state(.present(ElementPredicate(label: "Home"))),
                        steps: [.warn(WarnStep(message: "home flow"))]
                    ),
                ]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.success)
        XCTAssertEqual(step.caseSelection?.selectedCaseIndex, 0)
        XCTAssertEqual(step.childResults?.map(\.kind), [.warn])
    }

    func testHeistWaitForCasesZeroTimeoutPassesImmediateObservationBudget() async throws {
        var observedTimeouts: [Double?] = []
        let runtime = heistRuntime(
            observations: [observedState(labels: ["Settings"])],
            observedTimeouts: { observedTimeouts.append($0) }
        )
        let plan = HeistPlan(steps: [
            .waitForCases(try WaitForCasesStep(
                timeout: 0,
                cases: [
                    PredicateCase(
                        predicate: .state(.present(ElementPredicate(label: "Home"))),
                        steps: [.warn(WarnStep(message: "home flow"))]
                    ),
                ]
            )),
        ])

        _ = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertEqual(observedTimeouts, [0])
    }

    func testHeistWaitTimeoutZeroTurnsObservationCrankOnce() async throws {
        let plan = HeistPlan(steps: [
            .wait(WaitStep(
                predicate: .state(.present(ElementPredicate(label: "Never Appears"))),
                timeout: 0
            )),
        ])

        let start = CFAbsoluteTimeGetCurrent()
        let result = await brains.executeHeistPlan(plan)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertFalse(result.success)
        XCTAssertLessThan(elapsed, 3)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)
        XCTAssertDiagnostic(step.actionResult?.message, contains: [
            "no settled semantic observation available",
        ])
    }

    func testHeistWaitTimeoutZeroSucceedsFromOneObservation() async throws {
        var observedTimeouts: [Double?] = []
        let runtime = heistRuntime(
            observations: [observedState(labels: ["Home"])],
            observedTimeouts: { observedTimeouts.append($0) }
        )
        let plan = HeistPlan(steps: [
            .wait(WaitStep(
                predicate: .state(.present(ElementPredicate(label: "Home"))),
                timeout: 0
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertTrue(result.success)
        XCTAssertEqual(observedTimeouts, [])
    }

    func testPerformWaitTimeoutZeroDoesNotReturnCachedSettledStateWithoutFreshObservation() async {
        brains.stash.installScreenForTesting(.makeForTests(elements: [
            (makeElement(label: "Home"), "home"),
        ]))
        XCTAssertNil(brains.stash.passiveSemanticObservationTask)

        let result = await brains.performWait(target: WaitTarget(
            predicate: .state(.present(ElementPredicate(label: "Home"))),
            timeout: 0
        ))

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.errorKind, .timeout)
        XCTAssertTrue(result.message?.contains("no settled semantic observation available") == true)
        XCTAssertNotNil(
            brains.stash.passiveSemanticObservationTask,
            "wait should enter the Stash observation gateway before evaluating"
        )
    }

    func testPerformWaitTimeoutZeroStartsObservationWhenNoSettledStateExists() async {
        XCTAssertNil(brains.stash.latestSettledSemanticObservation)
        XCTAssertNil(brains.stash.passiveSemanticObservationTask)

        let result = await brains.performWait(target: WaitTarget(
            predicate: .state(.present(ElementPredicate(label: "Home"))),
            timeout: 0
        ))

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.errorKind, .timeout)
        XCTAssertTrue(result.message?.contains("no settled semantic observation available") == true)
        XCTAssertNotNil(
            brains.stash.passiveSemanticObservationTask,
            "wait should enter the Stash observation gateway before evaluating"
        )
    }

    func testHeistActionExpectationRequiresWaitObservationEvidence() async throws {
        let expectation = WaitStep(
            predicate: .state(.absent(ElementPredicate(label: "Loading"))),
            timeout: 0
        )
        var waitedSteps: [WaitStep] = []
        let runtime = heistRuntime(
            observations: [],
            execute: { _ in
                ActionResult(success: true, method: .activate)
            },
            wait: { waitStep in
                waitedSteps.append(waitStep)
                return ActionResult(success: true, method: .wait)
            }
        )
        let plan = HeistPlan(steps: [
            .action(try ActionStep(
                command: .activate(.predicate(ElementPredicate(label: "Submit"))),
                expectation: expectation
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertFalse(result.success)
        XCTAssertEqual(waitedSteps, [expectation])
        XCTAssertEqual(step.expectationActionResult?.method, .wait)
        XCTAssertEqual(step.expectation?.met, false)
        XCTAssertEqual(step.expectation?.actual, "no observed accessibility trace")
    }

    func testHeistActionExpectationTimeoutZeroUsesDeliveredActionTrace() async throws {
        let expectation = WaitStep(predicate: .changed(.screen()), timeout: 0)
        let beforeState = observedState(labels: ["Controls Demo"])
        let afterState = observedState(labels: ["Buttons & Actions"])
        let beforeCapture = AccessibilityTrace.Capture(
            sequence: 1,
            interface: beforeState.interface,
            context: AccessibilityTrace.Context(screenId: "controls_demo")
        )
        let afterCapture = AccessibilityTrace.Capture(
            sequence: 2,
            interface: afterState.interface,
            parentHash: beforeCapture.hash,
            context: AccessibilityTrace.Context(screenId: "buttons_actions")
        )
        let trace = AccessibilityTrace(captures: [beforeCapture, afterCapture])
        var waitedSteps: [WaitStep] = []
        let runtime = heistRuntime(
            observations: [],
            execute: { _ in
                ActionResult(success: true, method: .activate, accessibilityTrace: trace)
            },
            wait: { waitStep in
                waitedSteps.append(waitStep)
                return ActionResult(success: false, method: .wait, errorKind: .timeout)
            }
        )
        let plan = HeistPlan(steps: [
            .action(try ActionStep(
                command: .activate(.predicate(ElementPredicate(label: "Controls Demo"))),
                expectation: expectation
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.success)
        XCTAssertTrue(waitedSteps.isEmpty)
        XCTAssertEqual(step.expectationActionResult?.method, .wait)
        XCTAssertTrue(step.expectationActionResult?.success == true)
        XCTAssertEqual(step.expectation?.met, true)
        XCTAssertEqual(step.expectation?.actual, "screenChanged")
    }

    func testHeistActionExpectationUsesWaitFailureDiagnostic() async throws {
        let expectation = WaitStep(
            predicate: .changed(.disappeared(ElementPredicate(label: "Loading"))),
            timeout: 0.2
        )
        let runtime = heistRuntime(
            observations: [],
            execute: { _ in
                ActionResult(success: true, method: .activate)
            },
            wait: { _ in
                ActionResult(
                    success: false,
                    method: .wait,
                    message: "timed out after 0.2s — expectation not met",
                    errorKind: .timeout,
                    accessibilityTrace: .projectingForTests(.noChange(.init(elementCount: 1)))
                )
            }
        )
        let plan = HeistPlan(steps: [
            .action(try ActionStep(
                command: .activate(.predicate(ElementPredicate(label: "Submit"))),
                expectation: expectation
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertFalse(result.success)
        XCTAssertEqual(step.expectationActionResult?.errorKind, .timeout)
        XCTAssertEqual(step.expectation?.met, false)
        XCTAssertEqual(step.expectation?.actual, "timed out after 0.2s — expectation not met")
    }

    func testHeistSemanticObservationScopeUsesVisibleForStateCases() async throws {
        var observedScopes: [SemanticObservationScope] = []
        let runtime = heistRuntime(
            observations: [observedState(labels: ["Home"])],
            observedScopes: { observedScopes.append($0) }
        )
        let plan = HeistPlan(steps: [
            .conditional(try ConditionalStep(cases: [
                PredicateCase(
                    predicate: .state(.present(ElementPredicate(label: "Home"))),
                    steps: [.warn(WarnStep(message: "home"))]
                ),
                PredicateCase(
                    predicate: .state(.absent(ElementPredicate(label: "Login"))),
                    steps: [.warn(WarnStep(message: "not login"))]
                ),
            ])),
        ])

        _ = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertEqual(observedScopes, [.visible])
    }

    func testHeistSemanticObservationScopeUsesDiscoveryForAppearanceCases() async throws {
        var observedScopes: [SemanticObservationScope] = []
        let runtime = heistRuntime(
            observations: [observedState(labels: ["Loading"])],
            observedScopes: { observedScopes.append($0) }
        )
        let plan = HeistPlan(steps: [
            .waitForCases(try WaitForCasesStep(
                timeout: 0,
                cases: [
                    PredicateCase(
                        predicate: .changed(.appeared(ElementPredicate(label: "Toast"))),
                        steps: [.warn(WarnStep(message: "toast"))]
                    ),
                ],
                elseSteps: [.warn(WarnStep(message: "no toast"))]
            )),
        ])

        _ = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertEqual(observedScopes, [.discovery])
    }

    func testHeistSemanticObservationScopeDiscoveryWinsOverVisible() async throws {
        var observedScopes: [SemanticObservationScope] = []
        let runtime = heistRuntime(
            observations: [observedState(labels: ["Loading"])],
            observedScopes: { observedScopes.append($0) }
        )
        let plan = HeistPlan(steps: [
            .waitForCases(try WaitForCasesStep(
                timeout: 0,
                cases: [
                    PredicateCase(
                        predicate: .state(.present(ElementPredicate(label: "Home"))),
                        steps: [.warn(WarnStep(message: "home"))]
                    ),
                    PredicateCase(
                        predicate: .changed(.appeared(ElementPredicate(label: "Toast"))),
                        steps: [.warn(WarnStep(message: "toast"))]
                    ),
                ],
                elseSteps: [.warn(WarnStep(message: "unknown"))]
            )),
        ])

        _ = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertEqual(observedScopes, [.discovery])
    }

    func testHeistForEachWithZeroMatchesSucceedsWithoutIterations() async throws {
        let matching = ElementPredicate(label: "Delete")
        var observedScopes: [SemanticObservationScope] = []
        let runtime = heistRuntime(
            observations: [
                observedState(labels: ["Keep"]),
            ],
            observedScopes: { observedScopes.append($0) }
        )
        let plan = HeistPlan(steps: [
            .forEach(try ForEachStep(
                matching: matching,
                limit: 20,
                steps: [.warn(WarnStep(message: "delete one"))]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)
        let forEachResult = try XCTUnwrap(step.forEachResult)

        XCTAssertTrue(result.success)
        XCTAssertEqual(step.kind, .forEach)
        XCTAssertEqual(forEachResult.matchedCount, 0)
        XCTAssertEqual(forEachResult.limit, 20)
        XCTAssertEqual(forEachResult.iterationCount, 0)
        XCTAssertNil(forEachResult.failureReason)
        XCTAssertNil(step.childResults)
        XCTAssertEqual(observedScopes, [.discovery])
    }

    func testHeistForEachFailsBeforeMutationWhenMatchCountExceedsLimit() async throws {
        let matching = ElementPredicate(label: "Delete")
        var executedCommands: [ClientMessage] = []
        let runtime = heistRuntime(
            observations: [
                observedState(elements: [
                    (makeElement(label: "Delete", identifier: "delete_first"), "delete_first"),
                    (makeElement(label: "Delete", identifier: "delete_second"), "delete_second"),
                ]),
            ],
            execute: { command in
                executedCommands.append(command)
                return ActionResult(success: true, method: .activate)
            }
        )
        let plan = HeistPlan(steps: [
            .forEach(try ForEachStep(
                matching: matching,
                limit: 1,
                steps: [.action(try ActionStep(command: .activate(.predicate(matching, ordinal: 0))))]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)
        let forEachResult = try XCTUnwrap(step.forEachResult)

        XCTAssertFalse(result.success)
        XCTAssertTrue(executedCommands.isEmpty)
        XCTAssertEqual(forEachResult.matchedCount, 2)
        XCTAssertEqual(forEachResult.limit, 1)
        XCTAssertEqual(forEachResult.iterationCount, 0)
        XCTAssertEqual(forEachResult.failureReason, "matched 2 element(s), exceeding for_each limit 1")
        XCTAssertNil(step.childResults)
    }

    func testHeistForEachReexecutesOrdinalZeroForEachInitialMatch() async throws {
        let matching = ElementPredicate(label: "Delete")
        var executedCommands: [ClientMessage] = []
        let initialState = observedState(elements: [
            (makeElement(label: "Delete", identifier: "delete_first"), "delete_first"),
            (makeElement(label: "Delete", identifier: "delete_second"), "delete_second"),
            (makeElement(label: "Delete", identifier: "delete_third"), "delete_third"),
        ])
        let runtime = heistRuntime(
            observations: [initialState],
            execute: { command in
                executedCommands.append(command)
                return ActionResult(success: true, method: .activate)
            }
        )
        let plan = HeistPlan(steps: [
            .forEach(try ForEachStep(
                matching: matching,
                limit: 10,
                steps: [.action(try ActionStep(command: .activate(.predicate(matching, ordinal: 0))))]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)
        let forEachResult = try XCTUnwrap(step.forEachResult)

        XCTAssertTrue(result.success)
        XCTAssertEqual(forEachResult.matchedCount, 3)
        XCTAssertEqual(forEachResult.iterationCount, 3)
        XCTAssertEqual(executedCommands, [
            .activate(.predicate(matching, ordinal: 0)),
            .activate(.predicate(matching, ordinal: 0)),
            .activate(.predicate(matching, ordinal: 0)),
        ])
        XCTAssertEqual(step.childResults?.map(\.kind), [.action, .action, .action])
    }

    func testHeistForEachBodyFailureStopsHeistAndSkipsFollowingTopLevelSteps() async throws {
        let matching = ElementPredicate(label: "Delete")
        let initialState = observedState(elements: [
            (makeElement(label: "Delete", identifier: "delete_first"), "delete_first"),
            (makeElement(label: "Delete", identifier: "delete_second"), "delete_second"),
        ])
        let runtime = heistRuntime(
            observations: [initialState],
            execute: { _ in
                ActionResult(
                    success: false,
                    method: .activate,
                    message: "activate failed",
                    errorKind: .actionFailed
                )
            }
        )
        let plan = HeistPlan(steps: [
            .forEach(try ForEachStep(
                matching: matching,
                limit: 10,
                steps: [.action(try ActionStep(command: .activate(.predicate(matching, ordinal: 0))))]
            )),
            .warn(WarnStep(message: "should be skipped")),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let forEachStep = try XCTUnwrap(heist.steps.first)
        let forEachResult = try XCTUnwrap(forEachStep.forEachResult)

        XCTAssertFalse(result.success)
        XCTAssertEqual(heist.failedIndex, 0)
        XCTAssertEqual(heist.steps.map(\.kind), [.forEach, .skipped])
        XCTAssertEqual(forEachResult.matchedCount, 2)
        XCTAssertEqual(forEachResult.iterationCount, 1)
        XCTAssertEqual(forEachResult.failureReason, "iteration 0 failed")
        XCTAssertEqual(forEachStep.childResults?.map(\.kind), [.action])
    }

    func testHeistForEachExpectationUsesCurrentSemanticTarget() async throws {
        let matching = ElementPredicate(label: "Delete")
        var executedCommands: [ClientMessage] = []
        var waitedSteps: [WaitStep] = []
        let initialState = observedState(elements: [
            (makeElement(label: "Delete", identifier: "delete_first"), "delete_first"),
            (makeElement(label: "Delete", identifier: "delete_second"), "delete_second"),
        ])
        let stillPresentState = observedState(elements: [
            (makeElement(label: "Delete", identifier: "delete_second"), "delete_second"),
        ])
        let waitObservedState = observedState(labels: ["Done"])
        let runtime = heistRuntime(
            observations: [initialState],
            execute: { command in
                executedCommands.append(command)
                return ActionResult(
                    success: true,
                    method: .activate,
                    accessibilityTrace: AccessibilityTrace(capture: stillPresentState.capture)
                )
            },
            wait: { waitStep in
                waitedSteps.append(waitStep)
                return ActionResult(
                    success: true,
                    method: .wait,
                    accessibilityTrace: AccessibilityTrace(capture: waitObservedState.capture)
                )
            }
        )
        let plan = HeistPlan(steps: [
            .forEach(try ForEachStep(
                matching: matching,
                limit: 10,
                steps: [
                    .action(try ActionStep(
                        command: .activate(.predicate(matching, ordinal: 0)),
                        expectation: WaitStep(
                            predicate: .state(.absentTarget(.predicate(matching, ordinal: 0))),
                            timeout: 2
                        )
                    )),
                ]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let forEachResult = try XCTUnwrap(heist.steps.first?.forEachResult)

        XCTAssertTrue(result.success)
        XCTAssertEqual(forEachResult.iterationCount, 2)
        XCTAssertEqual(executedCommands.first, .activate(.predicate(matching, ordinal: 0)))
        XCTAssertEqual(waitedSteps.first?.predicate, .state(.absentTarget(.predicate(matching, ordinal: 0))))
    }

    func testElementActionFailsWhenSemanticTargetHasNoLiveGeometry() async {
        let heistId = "geometry_missing_slider"
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

        let resolved = brains.stash.resolveTarget(.predicate(ElementPredicate(label: "Geometry Missing"))).resolved
        let liveTarget: TheStash.LiveActionTarget?
        if let resolved,
           case .resolved(let target) = brains.stash.resolveLiveActionTarget(for: resolved) {
            liveTarget = target
        } else {
            liveTarget = nil
        }
        let result = await brains.actions.executeIncrement(.predicate(ElementPredicate(label: "Geometry Missing")))

        XCTAssertNotNil(resolved)
        XCTAssertNil(liveTarget)
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .increment)
        XCTAssertEqual(liveObject.incrementCount, 0)
        XCTAssertDiagnostic(result.message, contains: [
            "semantic actionability failed [geometryNotActionable]",
            "method=increment",
            "heistId=\"geometry_missing_slider\"",
            "label=\"Geometry Missing\"",
            "fresh live geometry from semantic actionability",
        ])
    }

    func testElementActionUsesFreshLiveTargetForStaleSemanticCapture() async throws {
        let rootView = UIView(frame: UIScreen.main.bounds)
        rootView.backgroundColor = .white
        let liveObject = AdjustableGeometryView(
            frame: CGRect(x: 80, y: 180, width: 180, height: 44),
            activationPoint: CGPoint(x: 170, y: 202)
        )
        liveObject.isAccessibilityElement = true
        liveObject.accessibilityLabel = "Refreshed Slider"
        liveObject.accessibilityIdentifier = "refreshed_slider"
        liveObject.accessibilityTraits = .adjustable
        rootView.addSubview(liveObject)

        let window = try installModalWindow(rootView: rootView)
        defer {
            window.rootViewController?.view.accessibilityViewIsModal = false
            window.isHidden = true
        }
        await brains.tripwire.yieldFrames(3)

        let staleElement = AccessibilityElement.make(
            label: "Refreshed Slider",
            identifier: "refreshed_slider",
            traits: .adjustable,
            frame: CGRect(x: 10, y: 10, width: 120, height: 44),
            respondsToUserInteraction: false
        )
        brains.stash.installScreenForTesting(.makeForTests(
            elements: [(staleElement, "stale_refreshed_slider")],
            objects: ["stale_refreshed_slider": nil]
        ))
        guard let staleResolved = brains.stash.resolveTarget(
            .predicate(ElementPredicate(identifier: "refreshed_slider"))
        ).resolved else {
            XCTFail("Expected stale semantic target to resolve")
            return
        }
        guard case .objectUnavailable = brains.stash.resolveLiveActionTarget(for: staleResolved) else {
            XCTFail("Expected stale semantic target to have no live action target")
            return
        }

        let result = await brains.actions.executeIncrement(
            .predicate(ElementPredicate(identifier: "refreshed_slider"))
        )

        XCTAssertTrue(result.success, result.message ?? "increment failed")
        XCTAssertEqual(result.method, .increment)
        XCTAssertEqual(liveObject.incrementCount, 1)
    }

    func testExecuteActivateUsesRefreshedTargetForSecondActivationAttempt() async throws {
        let rootView = UIView(frame: UIScreen.main.bounds)
        rootView.backgroundColor = .white
        let liveObject = ActionActivationOverrideView(
            frame: CGRect(x: 80, y: 180, width: 180, height: 44)
        )
        liveObject.isAccessibilityElement = true
        liveObject.accessibilityLabel = "Refresh Activate"
        liveObject.accessibilityIdentifier = "refresh_activate"
        liveObject.accessibilityTraits = .button
        rootView.addSubview(liveObject)

        let window = try installModalWindow(rootView: rootView)
        defer {
            window.rootViewController?.view.accessibilityViewIsModal = false
            window.isHidden = true
        }
        await brains.tripwire.yieldFrames(3)

        registerScreenElement(
            heistId: "stale_refresh_activate",
            element: makeElement(
                label: "Refresh Activate",
                identifier: "refresh_activate",
                traits: .button
            ),
            object: RefusingActivationView()
        )

        let result = await brains.actions.executeActivate(
            .predicate(ElementPredicate(identifier: "refresh_activate"))
        )

        XCTAssertTrue(result.success, result.message ?? "activate failed")
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(liveObject.activationCount, 1)
    }

    func testExecuteTypeTextWithoutActiveInputReportsFocusState() async {
        _ = brains.safecracker.resignFirstResponder()

        let result = await brains.actions.executeTypeText(TypeTextTarget(text: "hello"))

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .typeText)
        XCTAssertDiagnostic(result.message, contains: [
            "text entry failed",
            "focus=none",
            "keyboardVisible=false",
            "activeTextInput=false",
            "try provide elementTarget for a text field",
        ])
    }

    func testExecuteTypeTextReportsKeyboardInjectionFailure() async {
        let keyboardImpl = KeyboardInjectionKeyboardImpl()
        brains.safecracker.keyboardBridgeProvider = { keyboardImpl.bridge(missingSelector: "addInputString:") }

        let result = await brains.actions.executeTypeText(TypeTextTarget(text: "hello"))

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .typeText)
        XCTAssertDiagnostic(result.message, contains: [
            "UIKeyboardImplTextInjection failed",
            "missing selector addInputString:",
            "while typing \"h\"",
        ])
        XCTAssertTrue(keyboardImpl.inputStrings.isEmpty)
    }

    func testExecuteTypeTextRejectsEmptyTextBeforeFocusCheck() async {
        let result = await brains.actions.executeTypeText(TypeTextTarget(text: ""))

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .typeText)
        XCTAssertEqual(result.message, "type_text requires non-empty text")
    }

    func testExecuteEditActionWithoutResponderReportsFocusState() async {
        _ = brains.safecracker.resignFirstResponder()

        let result = await brains.actions.executeEditAction(EditActionTarget(action: .copy))

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .editAction)
        XCTAssertDiagnostic(result.message, contains: [
            "edit action failed",
            "action=\"copy\"",
            "focus=none",
            "keyboardVisible=false",
            "activeTextInput=false",
            "try focus editable text before copy",
        ])
    }

    func testExecuteDeleteEditActionWithoutResponderReportsFocusState() async {
        _ = brains.safecracker.resignFirstResponder()

        let result = await brains.actions.executeEditAction(EditActionTarget(action: .delete))

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .editAction)
        XCTAssertDiagnostic(result.message, contains: [
            "edit action failed",
            "action=\"delete\"",
            "focus=none",
            "keyboardVisible=false",
            "activeTextInput=false",
            "try focus editable text before delete",
        ])
    }

    func testExecuteResignFirstResponderWithoutResponderReportsFocusState() async {
        _ = brains.safecracker.resignFirstResponder()

        let result = await brains.actions.executeResignFirstResponder()

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .resignFirstResponder)
        XCTAssertDiagnostic(result.message, contains: [
            "resign first responder failed",
            "focus=none",
            "keyboardVisible=false",
            "activeTextInput=false",
            "try focus a text input before dismissing the keyboard",
        ])
    }

    func testExecuteTapOutsideWindowReportsGestureDispatchState() async {
        let result = await brains.actions.executeTap(
            TapTarget(selection: .coordinate(ScreenPoint(x: -10_000, y: -10_000)))
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .syntheticTap)
        XCTAssertDiagnostic(result.message, contains: [
            "syntheticTap failed",
            "point must be inside screen bounds",
            "observed (-10000, -10000)",
        ])
    }

    func testElementTargetedPointActionFailsWhenElementRemainsKnownOnly() async {
        let stalePoint = CGPoint(x: 333, y: 777)
        let element = AccessibilityElement.make(
            label: "Below Fold",
            traits: .button,
            shape: .frame(AccessibilityRect(CGRect(x: 300, y: 750, width: 66, height: 54))),
            activationPoint: stalePoint
        )
        installScreen(offViewport: [.init(element, heistId: "below_fold_button")])

        var dispatchedPoint: CGPoint?
        let result = await brains.actions.performPointAction(
            selection: .element(.predicate(ElementPredicate(label: "Below Fold"))),
            method: .syntheticTap
        ) { point in
            dispatchedPoint = point
            return true
        }

        XCTAssertFalse(result.success)
        XCTAssertNil(dispatchedPoint, "Known-only targets must not dispatch their stored activation point")
        XCTAssertDiagnostic(result.message, contains: [
            "semantic actionability failed [noRevealPath]",
            "known target \"Below Fold\"",
            "heistId: below_fold_button",
            "no content-space position",
        ])
    }

    func testElementTargetedPointActionUsesAccessibilityCaptureActivationPoint() async {
        let capturePoint = CGPoint(x: 10, y: 20)
        let objectPoint = CGPoint(x: 123, y: 456)
        let heistId = "live_button"
        let element = AccessibilityElement.make(
            label: "Live",
            traits: .button,
            shape: .frame(AccessibilityRect(CGRect(x: 0, y: 0, width: 40, height: 40))),
            activationPoint: capturePoint,
            usesDefaultActivationPoint: false
        )
        let liveObject = ActionGeometryView(activationPoint: objectPoint)
        liveObject.accessibilityFrame = CGRect(x: 100, y: 430, width: 46, height: 52)
        installScreen(elements: [(element, heistId)], objects: [heistId: liveObject])

        var dispatchedPoint: CGPoint?
        let result = await brains.actions.performPointAction(
            selection: .element(.predicate(ElementPredicate(label: "Live"))),
            method: .syntheticTap
        ) { point in
            dispatchedPoint = point
            return true
        }

        XCTAssertTrue(result.success)
        XCTAssertEqual(dispatchedPoint, capturePoint)
        XCTAssertNotEqual(dispatchedPoint, objectPoint)
    }

    func testRawCoordinatePointActionDispatchesUnchanged() async {
        let rawPoint = CGPoint(x: 222, y: 333)

        var dispatchedPoint: CGPoint?
        let result = await brains.actions.performPointAction(
            selection: .coordinate(ScreenPoint(x: Double(rawPoint.x), y: Double(rawPoint.y))),
            method: .syntheticTap
        ) { point in
            dispatchedPoint = point
            return true
        }

        XCTAssertTrue(result.success)
        XCTAssertEqual(dispatchedPoint, rawPoint)
    }

    func testExecuteDragReadsTypedEndpointFromDragTarget() async throws {
        let result = await brains.actions.executeDrag(
            DragTarget(
                start: .coordinate(ScreenPoint(x: 10, y: 10)),
                end: ScreenPoint(x: .infinity, y: 20),
                duration: try GestureDuration(seconds: 0.01)
            )
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .syntheticDrag)
        XCTAssertEqual(result.failureKind, .inputValidation)
        XCTAssertEqual(result.message, "syntheticDrag failed: endPoint must contain finite coordinates")
    }

    func testExecuteRotorWithoutCustomRotorsReportsNextStep() async {
        let heistId = "plain_rotor_host"
        let liveObject = UIView()
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Plain rotor host", traits: .button),
            object: liveObject
        )

        let result = await brains.actions.executeRotor(
            RotorTarget(elementTarget: .predicate(ElementPredicate(label: "Plain rotor host")), selection: .named("Errors"))
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .rotor)
        XCTAssertDiagnostic(result.message, contains: [
            "rotor failed",
            "attempted rotor=\"Errors\" direction=next",
            "heistId=\"plain_rotor_host\"",
            "availableRotors=[]",
            "observed customRotors=[]",
            "try target an element exposing custom rotors",
        ])
    }

    func testExecuteRotorDispatchesLiveRotorAction() async {
        let heistId = "live_rotor_host"
        let liveObject = UIView()
        liveObject.accessibilityCustomRotors = [
            UIAccessibilityCustomRotor(name: "Live Rotor") { _ in
                UIAccessibilityCustomRotorItemResult(targetElement: liveObject, targetRange: nil)
            },
        ]
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Rotor host", traits: .button),
            object: liveObject
        )

        let result = await brains.actions.executeRotor(
            RotorTarget(elementTarget: .predicate(ElementPredicate(label: "Rotor host")), selection: .named("Live Rotor"))
        )

        XCTAssertTrue(result.success, result.message ?? "rotor failed")
        XCTAssertEqual(result.method, .rotor)
        XCTAssertTrue(result.message?.contains("Rotor 'Live Rotor' found Rotor host") ?? false,
                      result.message ?? "missing rotor success message")
    }

    func testExecuteRotorUsesOnscreenAccessibilityGeometryAtViewportEdge() async {
        let heistId = "edge_rotor_host"
        let frame = CGRect(x: 20, y: -20, width: 180, height: 44)
        let element = AccessibilityElement.make(
            label: "Edge Rotor Host",
            identifier: heistId,
            traits: .staticText,
            shape: .frame(AccessibilityRect(frame)),
            activationPoint: CGPoint(x: frame.midX, y: 2),
            customRotors: [.init(name: "Live Rotor")]
        )
        let liveObject = UIView()
        liveObject.accessibilityFrame = frame
        liveObject.accessibilityCustomRotors = [
            UIAccessibilityCustomRotor(name: "Live Rotor") { _ in
                UIAccessibilityCustomRotorItemResult(targetElement: liveObject, targetRange: nil)
            },
        ]
        installScreen(elements: [(element, heistId)], objects: [heistId: liveObject])

        let result = await brains.actions.executeRotor(
            RotorTarget(elementTarget: .predicate(ElementPredicate(identifier: "edge_rotor_host")), selection: .named("Live Rotor"))
        )

        XCTAssertTrue(result.success, result.message ?? "rotor failed")
        XCTAssertEqual(result.method, .rotor)
        XCTAssertTrue(result.message?.contains("Rotor 'Live Rotor' found Edge Rotor Host") ?? false,
                      result.message ?? "missing rotor success message")
    }

    func testExecuteRotorNotFoundReportsAvailableRotorsAndNextStep() async {
        let heistId = "rotor_host"
        let liveObject = UIView()
        liveObject.accessibilityCustomRotors = [
            UIAccessibilityCustomRotor(name: "Warnings") { _ in nil },
        ]
        registerScreenElement(
            heistId: heistId,
            element: makeElement(
                label: "Rotor host",
                traits: .button,
                customRotors: [.init(name: "Warnings")]
            ),
            object: liveObject
        )

        let result = await brains.actions.executeRotor(
            RotorTarget(elementTarget: .predicate(ElementPredicate(label: "Rotor host")), selection: .named("Errors"))
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .rotor)
        XCTAssertDiagnostic(result.message, contains: [
            "rotor failed",
            "attempted rotor=\"Errors\" direction=next",
            "requestedRotor=\"Errors\"",
            "availableRotors=[\"Warnings\"]",
            "try use one of available rotors [\"Warnings\"]",
        ])
    }

    func testExecuteRotorDiagnosticsMergeLiveRotors() async {
        let heistId = "rotor_host"
        let liveObject = UIView()
        liveObject.accessibilityCustomRotors = [
            UIAccessibilityCustomRotor(name: "Warnings") { _ in nil },
        ]
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Rotor host", traits: .button),
            object: liveObject
        )

        let result = await brains.actions.executeRotor(
            RotorTarget(elementTarget: .predicate(ElementPredicate(label: "Rotor host")), selection: .named("Errors"))
        )

        XCTAssertFalse(result.success)
        XCTAssertDiagnostic(result.message, contains: [
            "availableRotors=[\"Warnings\"]",
            "try use one of available rotors [\"Warnings\"]",
        ])
    }

    func testExecuteRotorDiagnosticsUseSystemRotorDisplayName() async {
        let heistId = "rotor_host"
        let liveObject = UIView()
        liveObject.accessibilityCustomRotors = [
            UIAccessibilityCustomRotor(systemType: .link) { _ in nil },
        ]
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Rotor host", traits: .button),
            object: liveObject
        )

        let result = await brains.actions.executeRotor(
            RotorTarget(elementTarget: .predicate(ElementPredicate(label: "Rotor host")), selection: .named("Errors"))
        )

        XCTAssertFalse(result.success)
        XCTAssertDiagnostic(result.message, contains: [
            "availableRotors=[\"Links\"]",
            "try use one of available rotors [\"Links\"]",
        ])
    }

    // MARK: - clearCache

    func testClearCacheResetsStash() {
        let element = makeElement(label: "Item")
        installScreen(elements: [(element, "test_id")])

        brains.clearCache()

        XCTAssertEqual(brains.stash.currentScreen, .empty)
    }

    // MARK: - Accessibility Tree Availability

    func testExecuteCommandWaitForFailsWhenAccessibilityTreeUnavailable() async {
        let target = WaitTarget(
            predicate: .state(.present(ElementPredicate(label: "never"))),
            timeout: 0
        )
        let result = await withNoTraversableWindows {
            await brains.executeCommand(.wait(target))
        }

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .wait)
        XCTAssertEqual(result.errorKind, .timeout)
        XCTAssertTrue(result.message?.contains("no settled semantic observation available") == true)
    }

    // MARK: - Helpers

    private func registerScreenElement(
        heistId: HeistId,
        element: AccessibilityElement,
        object: NSObject?
    ) {
        if let object {
            object.accessibilityFrame = element.shape.frame
        }
        installScreen(elements: [(element, heistId)], objects: [heistId: object])
    }

    private func installScreen(
        elements: [(AccessibilityElement, String)],
        objects: [HeistId: NSObject?] = [:]
    ) {
        brains.stash.installScreenForTesting(.makeForTests(
            elements: elements.map { ($0.0, $0.1) },
            objects: objects
        ))
    }

    private func installScreen(
        offViewport: [Screen.OffViewportEntry]
    ) {
        brains.stash.installScreenForTesting(.makeForTests(
            offViewport: offViewport
        ))
    }

    private func installModalWindow(rootView: UIView) throws -> UIWindow {
        let windowScene = try requireForegroundWindowScene()
        let viewController = UIViewController()
        viewController.view = rootView
        viewController.view.frame = UIScreen.main.bounds
        viewController.view.accessibilityViewIsModal = true

        let window = UIWindow(windowScene: windowScene)
        window.windowLevel = .alert + 45
        window.rootViewController = viewController
        window.frame = UIScreen.main.bounds
        window.isHidden = false
        window.layoutIfNeeded()
        return window
    }

    private func requireForegroundWindowScene() throws -> UIWindowScene {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else {
            throw XCTSkip("No foreground-active UIWindowScene available in test host")
        }
        return scene
    }

    private func makeElement(
        label: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        traits: UIAccessibilityTraits = .none,
        customActions: [String] = [],
        customRotors: [AccessibilityElement.CustomRotor] = []
    ) -> AccessibilityElement {
        let frame = CGRect(x: 20, y: 20, width: 120, height: 44)
        return .make(
            label: label,
            value: value,
            identifier: identifier,
            traits: traits,
            shape: .frame(AccessibilityRect(frame)),
            activationPoint: CGPoint(x: frame.midX, y: frame.midY),
            customActions: customActions.map(AccessibilityElement.CustomAction.init(name:)),
            customRotors: customRotors,
            respondsToUserInteraction: false
        )
    }

    private func matcherTarget(
        label: String,
        in screen: Screen
    ) throws -> ElementTarget {
        let capture = AccessibilityTrace.Capture(
            sequence: 1,
            interface: TheStash.WireConversion.toInterface(from: screen)
        )
        let element = try XCTUnwrap(capture.interface.projectedElements.first { $0.label == label })
        let minimumMatcher = try XCTUnwrap(MinimumMatcher.build(element: element, in: capture))
        return .predicate(minimumMatcher.predicate, ordinal: minimumMatcher.ordinal)
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

    private func assertSameInteraction(
        _ name: String,
        single singleResult: TheSafecracker.InteractionResult,
        heist heistResult: TheSafecracker.InteractionResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(heistResult.success, singleResult.success, name, file: file, line: line)
        XCTAssertEqual(heistResult.method, singleResult.method, name, file: file, line: line)
        XCTAssertEqual(heistResult.message, singleResult.message, name, file: file, line: line)
        XCTAssertEqual(heistResult.failureKind, singleResult.failureKind, name, file: file, line: line)
    }

    private func assertSameActionResult(
        _ name: String,
        single: ActionResult,
        heist: ActionResult,
        normalizingTimeoutDuration: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(heist.success, single.success, name, file: file, line: line)
        XCTAssertEqual(heist.method, single.method, name, file: file, line: line)
        XCTAssertEqual(heist.errorKind, single.errorKind, name, file: file, line: line)
        XCTAssertEqual(
            normalizedActionMessage(heist.message, normalizingTimeoutDuration: normalizingTimeoutDuration),
            normalizedActionMessage(single.message, normalizingTimeoutDuration: normalizingTimeoutDuration),
            name,
            file: file,
            line: line
        )
    }

    private func heistStepResult(for command: ClientMessage) async -> ActionResult {
        let step: HeistStep
        if case .wait(let target) = command {
            step = .wait(WaitStep(predicate: target.predicate, timeout: target.resolvedTimeout))
        } else {
            do {
                step = .action(try ActionStep(command: command))
            } catch {
                XCTFail("Expected heist executable command for \(command.wireType.rawValue): \(error)")
                return ActionResultBuilder(method: .heistPlan).failure(errorKind: .validationError)
            }
        }

        let result = await brains.executeHeistPlan(HeistPlan(steps: [step]))
        guard case .heistExecution(let heist) = result.payload,
              let stepResult = heist.steps.first,
              let actionResult = stepResult.actionResult else {
            XCTFail("Expected heist execution step result for \(command.wireType.rawValue)")
            return result
        }
        return actionResult
    }

    private func observedState(labels: [String]) -> PostActionObservation.BeforeState {
        observedState(elements: labels.enumerated().map { index, label in
            (makeElement(label: label), "element_\(index)")
        })
    }

    private func observedState(
        elements: [(AccessibilityElement, String)]
    ) -> PostActionObservation.BeforeState {
        brains.stash.installScreenForTesting(.makeForTests(elements: elements))
        return brains.postActionObservation.captureSemanticState()
    }

    private func heistRuntime(
        observations: [PostActionObservation.BeforeState],
        execute: (@MainActor (ClientMessage) async -> ActionResult)? = nil,
        wait: (@MainActor (WaitStep) async -> ActionResult)? = nil,
        observedScopes: (@MainActor (SemanticObservationScope) -> Void)? = nil,
        observedTimeouts: (@MainActor (Double?) -> Void)? = nil,
        unavailableObservationCount: Int = 0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> TheBrains.HeistExecutionRuntime {
        var remainingObservations = observations
        var remainingUnavailableObservations = unavailableObservationCount
        return TheBrains.HeistExecutionRuntime(
            execute: { command in
                if let execute {
                    return await execute(command)
                }
                return ActionResult(success: true, method: .heistPlan, message: command.wireType.rawValue)
            },
            wait: { waitStep in
                if let wait {
                    return self.heistWaitReceipt(for: waitStep, result: await wait(waitStep))
                }
                let state = remainingObservations.first
                let trace = state.map { AccessibilityTrace(capture: $0.capture) }
                let met = waitStep.predicate.evaluate(
                    currentElements: state?.interface.projectedElements ?? [],
                    delta: trace?.endpointDeltaProjection
                )
                let result = ActionResult(
                    success: met.met,
                    method: .wait,
                    message: met.actual,
                    errorKind: met.met ? nil : .timeout,
                    accessibilityTrace: trace
                )
                return HeistWaitReceipt(actionResult: result, expectation: met)
            },
            observeSemanticState: { scope, _, timeout in
                observedScopes?(scope)
                observedTimeouts?(timeout)
                if remainingUnavailableObservations > 0 {
                    remainingUnavailableObservations -= 1
                    return nil
                }
                guard !remainingObservations.isEmpty else {
                    XCTFail("Expected scripted heist case observation", file: file, line: line)
                    return nil
                }
                let state = remainingObservations.removeFirst()
                let trace = AccessibilityTrace(capture: state.capture)
                return HeistSemanticObservation(
                    baseline: state,
                    state: state,
                    accessibilityTrace: trace,
                    delta: nil,
                    summary: "known: \(state.interface.projectedElements.count) elements"
                )
            },
            recordDeliveredObservationAfterStep: {}
        )
    }

    private func heistWaitReceipt(
        for step: WaitStep,
        result: ActionResult
    ) -> HeistWaitReceipt {
        let expectation: ExpectationResult
        if result.success {
            expectation = step.predicate.validate(against: result)
        } else {
            expectation = ExpectationResult(
                met: false,
                predicate: step.predicate,
                actual: result.message ?? "failed"
            )
        }
        return HeistWaitReceipt(actionResult: result, expectation: expectation)
    }

    private func normalizedActionMessage(
        _ message: String?,
        normalizingTimeoutDuration: Bool
    ) -> String? {
        guard normalizingTimeoutDuration else { return message }
        return message?.replacingOccurrences(
            of: #"timed out after [0-9.]+s"#,
            with: "timed out after <duration>s",
            options: .regularExpression
        )
    }

    private func withNoTraversableWindows<T>(
        _ operation: () async -> T
    ) async -> T {
        let windows = brains.tripwire.getTraversableWindows().map(\.window)
        let originalHiddenStates = windows.map(\.isHidden)
        for window in windows {
            window.isHidden = true
        }
        defer {
            for (window, originalIsHidden) in zip(windows, originalHiddenStates) {
                window.isHidden = originalIsHidden
            }
        }
        return await operation()
    }
}

private extension ActionResult {
    var heistExecutionPayload: HeistExecutionResult? {
        guard case .heistExecution(let result) = payload else { return nil }
        return result
    }
}

#endif
