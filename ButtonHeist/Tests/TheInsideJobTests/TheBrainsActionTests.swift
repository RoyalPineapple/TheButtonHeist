#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@_spi(ButtonHeistInternals) @testable import ThePlans
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

@MainActor
private final class ActionTextInputKeyboardImpl: NSObject {
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
        inputDelegate
    }

    @objc(addInputString:)
    func addInputString(_ text: NSString) {
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
        brains.startSemanticObservation()
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

    func testInteractionObservationBeforeStateDoesNotReuseDirtySettledObservation() async {
        installScreen(elements: [(makeElement(label: "Title", traits: .header), "header_title")])
        brains.stash.markDirtyFromTripwire()

        let current = await withNoTraversableWindows {
            await brains.interactionObservation.prepareBeforeState(timeout: 0.001)
        }

        XCTAssertNil(
            current,
            "dirty settled state must not be returned when no live tree is readable"
        )
    }

    func testPerformInteractionFailsBeforeActionWhenSettledObservationUnavailable() async {
        var interactionRan = false

        let result = await withNoTraversableWindows {
            await brains.performInteraction(method: .activate) {
                interactionRan = true
                return .success(method: .activate)
            }
        }

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(result.errorKind, .actionFailed)
        XCTAssertDiagnostic(result.message, contains: [
            "Could not observe accessibility tree",
            "last parsed: no accessibility tree",
        ])
        XCTAssertFalse(interactionRan, "command action must not run without settled pre-state")
    }

    func testPerformInteractionUsesVisibleEvidenceWhenSettledObservationIsUnavailable() async throws {
        let windowScene = try requireForegroundWindowScene()
        var interactionRan = false

        let result = await withNoTraversableWindows {
            let viewController = UIViewController()
            viewController.view.backgroundColor = .white

            let button = UIButton(type: .system)
            button.setTitle("Visible Evidence Action", for: .normal)
            button.frame = CGRect(x: 40, y: 80, width: 180, height: 44)
            viewController.view.addSubview(button)

            let window = UIWindow(windowScene: windowScene)
            window.windowLevel = .alert + 60
            window.rootViewController = viewController
            window.frame = UIScreen.main.bounds
            window.isHidden = false

            defer {
                window.isHidden = true
            }

            brains.stash.stopPassiveSemanticObservation()

            return await brains.performInteraction(method: .activate) {
                interactionRan = true
                return .success(method: .activate)
            }
        }

        XCTAssertTrue(interactionRan, "readable live trees should not be blocked by settled-observation timeouts")
        XCTAssertTrue(result.success, result.message ?? "action unexpectedly failed")
        XCTAssertEqual(result.method, .activate)
        XCTAssertTrue(
            brains.stash.settledScreen.orderedElements.contains { $0.element.label == "Visible Evidence Action" },
            "the observed full tree should be committed so action resolution sees live evidence"
        )
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
            "label=\"Plain label\"",
            "actions=[]",
            "try retarget an element whose actions include activate",
        ])
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

        let success = await brains.executeCommand(.activate(.predicate(ElementPredicate(identifier: "trace_success"))))
        XCTAssertTrue(success.success, success.message ?? "activate failed")
        XCTAssertNotNil(success.accessibilityTrace?.captures.last)

        let failure = await brains.executeCommand(.activate(.predicate(ElementPredicate(identifier: "trace_failure"))))
        XCTAssertFalse(failure.success)
        XCTAssertEqual(failure.method, .activate)
        let afterCapture = try XCTUnwrap(failure.accessibilityTrace?.captures.last)
        XCTAssertTrue(afterCapture.interface.projectedElements.contains {
            $0.identifier == "trace_failure"
        })
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

    func testHeistCommandsMatchSingleCommandMatcherFailures() async throws {
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
            ("wait", .wait(WaitTarget(predicate: .state(.present(matcher)), timeout: 0.01)), true),
        ]

        for (label, command, normalizingTimeoutDuration) in commands {
            brains.clearCache()
            let single = await brains.executeCommand(command)
            brains.clearCache()
            let heist = try await heistStepResult(for: command)
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
        let plan = try HeistPlan(body: [
            .conditional(try ConditionalStep(cases: [
                PredicateCase(
                    predicate: .state(.present(ElementPredicate(label: "Home"))),
                    body: [.warn(WarnStep(message: "home flow"))]
                ),
                PredicateCase(
                    predicate: .state(.present(ElementPredicate(label: "Login"))),
                    body: [.fail(FailStep(message: "wrong branch"))]
                ),
            ])),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.success)
        XCTAssertEqual(step.kind, .conditional)
        XCTAssertEqual(step.caseSelectionEvidence?.selection.selectedCaseIndex, 0)
        XCTAssertEqual(step.children.map(\.kind), [.warn])
    }

    func testHeistConditionalUnmatchedWithoutElseContinues() async throws {
        let runtime = heistRuntime(observations: [
            observedState(labels: ["Settings"]),
        ])
        let plan = try HeistPlan(body: [
            .conditional(try ConditionalStep(cases: [
                PredicateCase(
                    predicate: .state(.present(ElementPredicate(label: "Home"))),
                    body: [.fail(FailStep(message: "should not run"))]
                ),
            ])),
            .warn(WarnStep(message: "continued")),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)

        XCTAssertTrue(result.success)
        XCTAssertEqual(heist.steps.map(\.kind), [.conditional, .warn])
        XCTAssertEqual(heist.steps.first?.caseSelectionEvidence?.selection.selectedCaseIndex, nil)
    }

    func testHeistWaitForCasesTimeoutWithoutElseFails() async throws {
        let runtime = heistRuntime(observations: [
            observedState(labels: ["Settings"]),
        ])
        let plan = try HeistPlan(body: [
            .waitForCases(try WaitForCasesStep(
                timeout: 0,
                cases: [
                    PredicateCase(
                        predicate: .state(.present(ElementPredicate(label: "Home"))),
                        body: [.warn(WarnStep(message: "home flow"))]
                    ),
                ]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertFalse(result.success)
        XCTAssertEqual(step.kind, .waitForCases)
        XCTAssertEqual(step.caseSelectionEvidence?.selection.timedOut, true)
        XCTAssertEqual(step.caseSelectionEvidence?.selection.elseRan, false)
    }

    func testHeistWaitForCasesTimeoutWithElseRunsElse() async throws {
        let runtime = heistRuntime(observations: [
            observedState(labels: ["Settings"]),
        ])
        let plan = try HeistPlan(body: [
            .waitForCases(try WaitForCasesStep(
                timeout: 0,
                cases: [
                    PredicateCase(
                        predicate: .state(.present(ElementPredicate(label: "Home"))),
                        body: [.fail(FailStep(message: "should not run"))]
                    ),
                ],
                elseBody: [.warn(WarnStep(message: "no known state appeared"))]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.success)
        XCTAssertEqual(step.caseSelectionEvidence?.selection.timedOut, true)
        XCTAssertEqual(step.caseSelectionEvidence?.selection.elseRan, true)
        XCTAssertEqual(step.children.map(\.kind), [.warn])
    }

    func testHeistWaitForCasesPollsUntilCaseMatches() async throws {
        let runtime = heistRuntime(observations: [
            observedState(labels: ["Loading"]),
            observedState(labels: ["Home"]),
        ])
        let plan = try HeistPlan(body: [
            .waitForCases(try WaitForCasesStep(
                timeout: 1,
                cases: [
                    PredicateCase(
                        predicate: .state(.present(ElementPredicate(label: "Home"))),
                        body: [.warn(WarnStep(message: "home flow"))]
                    ),
                ]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.success)
        XCTAssertEqual(step.caseSelectionEvidence?.selection.selectedCaseIndex, 0)
        XCTAssertEqual(step.children.map(\.kind), [.warn])
    }

    func testHeistWaitForCasesContinuesAfterUnavailableObservation() async throws {
        let runtime = heistRuntime(
            observations: [observedState(labels: ["Home"])],
            unavailableObservationCount: 1
        )
        let plan = try HeistPlan(body: [
            .waitForCases(try WaitForCasesStep(
                timeout: 1,
                cases: [
                    PredicateCase(
                        predicate: .state(.present(ElementPredicate(label: "Home"))),
                        body: [.warn(WarnStep(message: "home flow"))]
                    ),
                ]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.success)
        XCTAssertEqual(step.caseSelectionEvidence?.selection.selectedCaseIndex, 0)
        XCTAssertEqual(step.children.map(\.kind), [.warn])
    }

    func testHeistWaitForCasesZeroTimeoutPassesImmediateObservationBudget() async throws {
        var observedTimeouts: [Double?] = []
        let runtime = heistRuntime(
            observations: [observedState(labels: ["Settings"])],
            observedTimeouts: { observedTimeouts.append($0) }
        )
        let plan = try HeistPlan(body: [
            .waitForCases(try WaitForCasesStep(
                timeout: 0,
                cases: [
                    PredicateCase(
                        predicate: .state(.present(ElementPredicate(label: "Home"))),
                        body: [.warn(WarnStep(message: "home flow"))]
                    ),
                ]
            )),
        ])

        _ = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertEqual(observedTimeouts, [0])
    }

    func testHeistWaitTimeoutZeroTurnsObservationCrankOnce() async throws {
        let plan = try HeistPlan(body: [
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
            "last settled: sequence ",
            "last delta:",
        ])
    }

    func testHeistWaitTimeoutZeroSucceedsFromOneObservation() async throws {
        var observedTimeouts: [Double?] = []
        let runtime = heistRuntime(
            observations: [observedState(labels: ["Home"])],
            observedTimeouts: { observedTimeouts.append($0) }
        )
        let plan = try HeistPlan(body: [
            .wait(WaitStep(
                predicate: .state(.present(ElementPredicate(label: "Home"))),
                timeout: 0
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertTrue(result.success)
        XCTAssertEqual(observedTimeouts, [])
    }

    func testPerformWaitTimeoutZeroDoesNotStartObservationWhenRuntimeInactive() async {
        let inactiveBrains = TheBrains(tripwire: TheTripwire())
        inactiveBrains.stash.installScreenForTesting(.makeForTests(elements: [
            (makeElement(label: "Home"), "home"),
        ]))
        XCTAssertFalse(inactiveBrains.stash.semanticObservationStream.isActive)

        let result = await inactiveBrains.performWait(target: WaitTarget(
            predicate: .state(.present(ElementPredicate(label: "Home"))),
            timeout: 0
        ))

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.errorKind, .actionFailed)
        XCTAssertEqual(result.message, TheBrains.runtimeInactiveMessage)
        XCTAssertFalse(inactiveBrains.stash.semanticObservationStream.isActive)
    }

    func testExecuteCommandDoesNotStartObservationWhenRuntimeInactive() async {
        let inactiveBrains = TheBrains(tripwire: TheTripwire())
        XCTAssertNil(inactiveBrains.stash.latestSettledSemanticObservation)
        XCTAssertFalse(inactiveBrains.stash.semanticObservationStream.isActive)

        let result = await inactiveBrains.executeCommand(.wait(WaitTarget(
            predicate: .state(.present(ElementPredicate(label: "Home"))),
            timeout: 0
        )))

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.errorKind, .actionFailed)
        XCTAssertEqual(result.message, TheBrains.runtimeInactiveMessage)
        XCTAssertFalse(inactiveBrains.stash.semanticObservationStream.isActive)
    }

    func testWaitReceiptUsesBeforeAndMatchedSettledObservations() async throws {
        let isolatedBrains = TheBrains(tripwire: TheTripwire())
        defer { isolatedBrains.stopSemanticObservation() }
        let beforeScreen = Screen.makeForTests(elements: [
            (makeElement(label: "Before"), "before"),
        ])
        let matchedScreen = Screen.makeForTests(elements: [
            (makeElement(label: "Before"), "before"),
            (makeElement(label: "Loaded"), "loaded"),
        ])

        let receiptTask = Task { @MainActor in
            await isolatedBrains.interactionObservation.waitForPredicate(WaitStep(
                predicate: .changed(.appeared(ElementPredicate(label: "Loaded"))),
                timeout: 1
            ))
        }

        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)
        _ = isolatedBrains.stash.semanticObservationStream.commitSettledObservation(beforeScreen, scope: .discovery)
        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)

        _ = isolatedBrains.stash.semanticObservationStream.commitSettledObservation(matchedScreen, scope: .discovery)
        let receipt = await receiptTask.value
        let trace = try XCTUnwrap(receipt.actionResult.accessibilityTrace)

        XCTAssertTrue(receipt.actionResult.success)
        XCTAssertEqual(trace.captures.first?.interface.projectedElements.map(\.label), ["Before"])
        XCTAssertEqual(trace.captures.last?.interface.projectedElements.map(\.label), ["Before", "Loaded"])
        guard case .elementsChanged? = trace.endpointDelta else {
            return XCTFail("Expected elementsChanged delta, got \(String(describing: trace.endpointDelta))")
        }
    }

    func testWaitReceiptTimeoutDiagnosticUsesFinalSettledObservation() async throws {
        let isolatedBrains = TheBrains(tripwire: TheTripwire())
        defer { isolatedBrains.stopSemanticObservation() }
        let beforeScreen = Screen.makeForTests(elements: [
            (makeElement(label: "Known"), "known"),
        ])
        let receiptTask = Task { @MainActor in
            await isolatedBrains.interactionObservation.waitForPredicate(WaitStep(
                predicate: .changed(.appeared(ElementPredicate(label: "Missing"))),
                timeout: 0.05
            ))
        }
        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)
        _ = isolatedBrains.stash.semanticObservationStream.commitSettledObservation(beforeScreen, scope: .discovery)

        let receipt = await receiptTask.value

        XCTAssertFalse(receipt.actionResult.success)
        XCTAssertEqual(receipt.actionResult.errorKind, .timeout)
        XCTAssertTrue(receipt.actionResult.message?.contains("last observed: known: 1 elements") == true)
    }

    func testHeistActionExpectationRequiresWaitObservationEvidence() async throws {
        let expectation = WaitStep(
            predicate: .state(.absent(ElementPredicate(label: "Loading"))),
            timeout: 0
        )
        var waitedSteps: [ResolvedWaitStep] = []
        let runtime = heistRuntime(
            observations: [],
            execute: { _ in
                ActionResult(success: true, method: .activate)
            },
            wait: { waitStep, _ in
                waitedSteps.append(waitStep)
                return ActionResult(success: true, method: .wait)
            }
        )
        let plan = try HeistPlan(body: [
            .action(try ActionStep(
                command: .activate(.predicate(ElementPredicate(label: "Submit"))),
                expectation: expectation
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertFalse(result.success)
        XCTAssertEqual(waitedSteps, [try expectation.resolve(in: .empty)])
        XCTAssertEqual(step.expectationActionResult?.method, .wait)
        XCTAssertEqual(step.expectation?.met, false)
        XCTAssertEqual(step.expectation?.actual, "no observed accessibility trace")
    }

    func testHeistRuntimeValidationRejectsInvalidPlanBeforeDispatchOrObservation() async throws {
        let raw = UnvalidatedHeistPlan(body: [
            .action(try ActionStep(command: .activate(.ref("missing")))),
        ])

        XCTAssertThrowsError(try raw.validatedForRuntime()) { error in
            XCTAssertTrue(String(describing: error).contains("$.body[0].action.command.payload.target"))
            XCTAssertTrue(String(describing: error).contains("target_ref must resolve"))
        }
    }

    func testHeistRuntimeValidationRejectsInvalidStringLoopBeforeDispatch() async throws {
        let raw = UnvalidatedHeistPlan(body: [
            .forEachString(try ForEachStringStep(
                values: [""],
                parameter: "item",
                body: [
                    .action(try ActionStep(command: .typeText(
                        text: .ref("item"),
                        target: .target(.predicate(.label("Search")))
                    ))),
                ]
            )),
        ])

        XCTAssertThrowsError(try raw.validatedForRuntime()) { error in
            XCTAssertTrue(String(describing: error).contains("text must be non-empty"))
        }
    }

    func testHeistRuntimeValidationRejectsOversizedForEachBeforeObservation() async throws {
        let raw = UnvalidatedHeistPlan(body: [
            .forEachElement(try ForEachElementStep(
                matching: .label("Delete"),
                limit: HeistPlanRuntimeValidationLimits.standard.maxForEachElementLimit + 1,
                parameter: "target",
                body: [.action(try ActionStep(command: .activate(.ref("target"))))]
            )),
        ])

        XCTAssertThrowsError(try raw.validatedForRuntime()) { error in
            XCTAssertTrue(String(describing: error).contains("max for_each_element limit"))
        }
    }

    func testHeistInvocationExecutesHelperDependenciesInInvokedDefinitionScope() async throws {
        var executedCommands: [ClientMessage] = []
        let runtime = heistRuntime(
            observations: [],
            execute: { command in
                executedCommands.append(command)
                return ActionResult(success: true, method: .activate)
            }
        )
        let plan = try UnvalidatedHeistPlan(definitions: [
            UnvalidatedHeistPlan(
                name: "addToCart",
                parameter: .string(name: "item"),
                definitions: [
                    UnvalidatedHeistPlan(name: "tapAddButton", body: [
                        .action(try ActionStep(command: .activate(.predicate(ElementPredicate(label: "Add to Cart"))))),
                    ]),
                ],
                body: [
                    .action(try ActionStep(command: .activate(.predicate(ElementPredicateTemplate(label: .ref("item")))))),
                    .invoke(HeistInvocationStep(path: ["tapAddButton"])),
                ]
            ),
        ], body: [
            .invoke(HeistInvocationStep(
                path: ["addToCart"],
                argument: .string(.literal("Milk"))
            )),
        ]).validatedForRuntime()

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertTrue(result.success)
        XCTAssertEqual(executedCommands, [
            .activate(.predicate(ElementPredicate(label: "Milk"))),
            .activate(.predicate(ElementPredicate(label: "Add to Cart"))),
        ])
    }

    func testHeistExecutionBindsRootStringArgument() async throws {
        var executedCommands: [ClientMessage] = []
        let runtime = heistRuntime(
            observations: [],
            execute: { command in
                executedCommands.append(command)
                return ActionResult(success: true, method: .typeText)
            }
        )
        let plan = try HeistPlan(
            name: "search",
            parameter: .string(name: "query"),
            body: [
                .action(try ActionStep(command: .typeText(
                    text: .ref("query"),
                    target: .target(.predicate(.label("Search")))
                ))),
            ]
        )

        let result = await brains.executeHeistPlanForTest(
            plan,
            argument: .string(.literal("milk")),
            runtime: runtime
        )

        XCTAssertTrue(result.success)
        XCTAssertEqual(executedCommands, [
            .typeText(TypeTextTarget(
                text: "milk",
                elementTarget: .predicate(ElementPredicate(label: "Search"))
            )),
        ])
    }

    func testHeistExecutionBindsRootElementTargetArgument() async throws {
        var executedCommands: [ClientMessage] = []
        let runtime = heistRuntime(
            observations: [],
            execute: { command in
                executedCommands.append(command)
                return ActionResult(success: true, method: .activate)
            }
        )
        let plan = try HeistPlan(
            name: "tapRow",
            parameter: .elementTarget(name: "row"),
            body: [
                .action(try ActionStep(command: .activate(.ref("row")))),
            ]
        )

        let result = await brains.executeHeistPlanForTest(
            plan,
            argument: .elementTarget(.target(.label("Row 1"))),
            runtime: runtime
        )

        XCTAssertTrue(result.success)
        XCTAssertEqual(executedCommands, [
            .activate(.predicate(ElementPredicate(label: "Row 1"))),
        ])
    }

    func testHeistExecutionRejectsMissingRootArgument() async throws {
        let runtime = heistRuntime(observations: [])
        let plan = try HeistPlan(
            name: "search",
            parameter: .string(name: "query"),
            body: [
                .action(try ActionStep(command: .typeText(
                    text: .ref("query"),
                    target: .target(.predicate(.label("Search")))
                ))),
            ]
        )

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.errorKind, .validationError)
        XCTAssertEqual(result.message, "Could not bind root heist argument: heist argument type none does not match parameter type string")
    }

    func testHeistInvocationAllowsSameLeafDefinitionNamesInDifferentScopes() async throws {
        var executedCommands: [ClientMessage] = []
        let runtime = heistRuntime(
            observations: [],
            execute: { command in
                executedCommands.append(command)
                return ActionResult(success: true, method: .activate)
            }
        )
        let plan = try HeistPlan(definitions: [
            try HeistPlan(
                name: "setup",
                definitions: [
                    try HeistPlan(name: "setup", body: [
                        .action(try ActionStep(command: .activate(.target(.predicate(.label("Nested Setup")))))),
                    ]),
                ],
                body: [
                    .invoke(HeistInvocationStep(path: ["setup"])),
                ]
            ),
        ], body: [
            .invoke(HeistInvocationStep(path: ["setup"])),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertTrue(result.success)
        XCTAssertEqual(executedCommands, [
            .activate(.predicate(ElementPredicate(label: "Nested Setup"))),
        ])
    }

    func testHeistExecutionRuntimeRejectsSelfInvocationOutsideLocalScopeWhenValidationIsBypassed() async throws {
        let runtime = heistRuntime(observations: [])
        let recursiveName = "repeatHeist"
        let plan = UnvalidatedHeistPlan(definitions: [
            UnvalidatedHeistPlan(name: recursiveName, body: [
                .invoke(HeistInvocationStep(path: [recursiveName])),
            ]),
        ], body: []).uncheckedPlanForRuntimeValidation()

        let results = await brains.executeHeistSteps(
            [.invoke(HeistInvocationStep(path: [recursiveName]))],
            runtime: runtime,
            environment: .empty,
            scope: TheBrains.HeistExecutionScope(plan: plan)
        )

        let topLevel = try XCTUnwrap(results.first)
        let recursive = try XCTUnwrap(topLevel.children.first)
        XCTAssertTrue(topLevel.isFailure)
        XCTAssertEqual(recursive.kind, .invoke)
        XCTAssertEqual(recursive.message, "Unknown heist run \(recursiveName)")
    }

    func testHeistActionExpectationTimeoutZeroUsesActionInteractionTrace() async throws {
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
        let runtime = heistRuntime(
            observations: [],
            execute: { _ in
                ActionResult(success: true, method: .activate, accessibilityTrace: trace)
            }
        )
        let plan = try HeistPlan(body: [
            .action(try ActionStep(
                command: .activate(.predicate(ElementPredicate(label: "Controls Demo"))),
                expectation: expectation
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.success)
        XCTAssertEqual(step.expectationActionResult?.method, .wait)
        XCTAssertTrue(step.expectationActionResult?.success == true)
        XCTAssertEqual(step.expectationActionResult?.accessibilityTrace, trace)
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
            wait: { _, _ in
                ActionResult(
                    success: false,
                    method: .wait,
                    message: "timed out after 0.2s — expectation not met",
                    errorKind: .timeout,
                    accessibilityTrace: .projectingForTests(.noChange(.init(elementCount: 1)))
                )
            }
        )
        let plan = try HeistPlan(body: [
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
        let plan = try HeistPlan(body: [
            .conditional(try ConditionalStep(cases: [
                PredicateCase(
                    predicate: .state(.present(ElementPredicate(label: "Home"))),
                    body: [.warn(WarnStep(message: "home"))]
                ),
                PredicateCase(
                    predicate: .state(.absent(ElementPredicate(label: "Login"))),
                    body: [.warn(WarnStep(message: "not login"))]
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
        let plan = try HeistPlan(body: [
            .waitForCases(try WaitForCasesStep(
                timeout: 0,
                cases: [
                    PredicateCase(
                        predicate: .changed(.appeared(ElementPredicate(label: "Toast"))),
                        body: [.warn(WarnStep(message: "toast"))]
                    ),
                ],
                elseBody: [.warn(WarnStep(message: "no toast"))]
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
        let plan = try HeistPlan(body: [
            .waitForCases(try WaitForCasesStep(
                timeout: 0,
                cases: [
                    PredicateCase(
                        predicate: .state(.present(ElementPredicate(label: "Home"))),
                        body: [.warn(WarnStep(message: "home"))]
                    ),
                    PredicateCase(
                        predicate: .changed(.appeared(ElementPredicate(label: "Toast"))),
                        body: [.warn(WarnStep(message: "toast"))]
                    ),
                ],
                elseBody: [.warn(WarnStep(message: "unknown"))]
            )),
        ])

        _ = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertEqual(observedScopes, [.discovery])
    }

    func testWaitForCasesChangedPredicateConsumesStreamEventDelta() async throws {
        let runtime = heistRuntime(observations: [
            observedState(labels: ["Loading"]),
            observedState(labels: ["Loading", "Toast"]),
        ])
        let plan = try HeistPlan(body: [
            .waitForCases(try WaitForCasesStep(
                timeout: 1,
                cases: [
                    PredicateCase(
                        predicate: .changed(.appeared(ElementPredicate(label: "Toast"))),
                        body: [.warn(WarnStep(message: "toast"))]
                    ),
                ]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.success)
        XCTAssertEqual(step.caseSelectionEvidence?.selection.selectedCaseIndex, 0)
        XCTAssertEqual(step.caseSelectionEvidence?.selection.cases.first?.result.met, true)
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
        let plan = try HeistPlan(body: [
            .forEachElement(try ForEachElementStep(
                matching: matching,
                limit: 20,
                parameter: "target",
                body: [.warn(WarnStep(message: "delete one"))]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)
        let forEachResult = try XCTUnwrap(step.forEachElementEvidence)

        XCTAssertTrue(result.success)
        XCTAssertEqual(step.kind, .forEachElement)
        XCTAssertEqual(forEachResult.matchedCount, 0)
        XCTAssertEqual(forEachResult.limit, 20)
        XCTAssertEqual(forEachResult.iterationCount, 0)
        XCTAssertNil(forEachResult.failureReason)
        XCTAssertTrue(step.children.isEmpty)
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
        let plan = try HeistPlan(body: [
            .forEachElement(try ForEachElementStep(
                matching: matching,
                limit: 1,
                parameter: "target",
                body: [.action(try ActionStep(command: .activate(.ref("target"))))]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)
        let forEachResult = try XCTUnwrap(step.forEachElementEvidence)

        XCTAssertFalse(result.success)
        XCTAssertTrue(executedCommands.isEmpty)
        XCTAssertEqual(forEachResult.matchedCount, 2)
        XCTAssertEqual(forEachResult.limit, 1)
        XCTAssertEqual(forEachResult.iterationCount, 0)
        XCTAssertEqual(forEachResult.failureReason, "matched 2 element(s), exceeding for_each_element limit 1")
        XCTAssertTrue(step.children.isEmpty)
    }

    func testHeistForEachCallsBodyWithOrdinalTargetForEachInitialMatchWithoutMutatingPlan() async throws {
        let matching = ElementPredicate(label: "Delete")
        var executedCommands: [ClientMessage] = []
        let initialState = observedState(elements: [
            (makeElement(label: "Delete", identifier: "delete_first"), "delete_first"),
            (makeElement(label: "Delete", identifier: "delete_second"), "delete_second"),
            (makeElement(label: "Delete", identifier: "delete_third"), "delete_third"),
        ])
        let runtime = heistRuntime(
            observations: [initialState, initialState, initialState],
            execute: { command in
                executedCommands.append(command)
                return ActionResult(success: true, method: .activate)
            }
        )
        let plan = try HeistPlan(body: [
            .forEachElement(try ForEachElementStep(
                matching: matching,
                limit: 10,
                parameter: "target",
                body: [.action(try ActionStep(command: .activate(.ref("target"))))]
            )),
        ])
        let originalBody = plan.body

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)
        let forEachResult = try XCTUnwrap(step.forEachElementEvidence)

        XCTAssertTrue(result.success)
        XCTAssertEqual(forEachResult.matchedCount, 3)
        XCTAssertEqual(forEachResult.iterationCount, 3)
        XCTAssertEqual(executedCommands, [
            .activate(.predicate(matching, ordinal: 0)),
            .activate(.predicate(matching, ordinal: 1)),
            .activate(.predicate(matching, ordinal: 2)),
        ])
        XCTAssertEqual(step.children.map(\.kind), [.forEachIteration, .forEachIteration, .forEachIteration])
        XCTAssertEqual(step.children.flatMap(\.children).map(\.kind), [.action, .action, .action])
        XCTAssertEqual(plan.body, originalBody)
    }

    func testHeistForEachPreservesCallerPredicateInsteadOfMinimumMatchers() async throws {
        let matching = ElementPredicate(label: "Delete", traits: [.button])
        var executedCommands: [ClientMessage] = []
        let initialState = observedState(elements: [
            (
                makeElement(label: "Delete", value: "First", identifier: "delete_first", traits: [.button]),
                "delete_first"
            ),
            (
                makeElement(label: "Delete", value: "Second", identifier: "delete_second", traits: [.button]),
                "delete_second"
            ),
        ])
        let runtime = heistRuntime(
            observations: [initialState, initialState],
            execute: { command in
                executedCommands.append(command)
                return ActionResult(success: true, method: .activate)
            }
        )
        let plan = try HeistPlan(body: [
            .forEachElement(try ForEachElementStep(
                matching: matching,
                limit: 10,
                parameter: "target",
                body: [.action(try ActionStep(command: .activate(.ref("target"))))]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let forEachResult = try XCTUnwrap(result.heistExecutionPayload?.steps.first?.forEachElementEvidence)

        XCTAssertTrue(result.success)
        XCTAssertEqual(forEachResult.iterationCount, 2)
        XCTAssertEqual(executedCommands, [
            .activate(.predicate(matching, ordinal: 0)),
            .activate(.predicate(matching, ordinal: 1)),
        ])
    }

    func testHeistForEachResetsOrdinalWhenMatchedCollectionIdentityChanges() async throws {
        let matching = ElementPredicate(label: "Delete")
        var executedCommands: [ClientMessage] = []
        let initialState = observedState(elements: [
            (makeElement(label: "Delete", identifier: "delete_first"), "delete_first"),
            (makeElement(label: "Delete", identifier: "delete_second"), "delete_second"),
        ])
        let afterFirstMutation = observedState(elements: [
            (makeElement(label: "Delete", identifier: "delete_second"), "delete_second"),
        ])
        let runtime = heistRuntime(
            observations: [initialState, afterFirstMutation],
            execute: { command in
                executedCommands.append(command)
                return ActionResult(success: true, method: .activate)
            }
        )
        let plan = try HeistPlan(body: [
            .forEachElement(try ForEachElementStep(
                matching: matching,
                limit: 10,
                parameter: "target",
                body: [.action(try ActionStep(command: .activate(.ref("target"))))]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)
        let forEachResult = try XCTUnwrap(step.forEachElementEvidence)

        XCTAssertTrue(result.success)
        XCTAssertEqual(forEachResult.matchedCount, 2)
        XCTAssertEqual(forEachResult.iterationCount, 2)
        XCTAssertNil(forEachResult.failureReason)
        XCTAssertEqual(executedCommands, [
            .activate(.predicate(matching, ordinal: 0)),
            .activate(.predicate(matching, ordinal: 0)),
        ])
    }

    func testHeistForEachAdditionResetsOrdinalWithoutExtendingInitialIterationBudget() async throws {
        let matching = ElementPredicate(label: "Delete")
        var executedCommands: [ClientMessage] = []
        let initialState = observedState(elements: [
            (makeElement(label: "Delete", identifier: "delete_first"), "delete_first"),
            (makeElement(label: "Delete", identifier: "delete_second"), "delete_second"),
        ])
        let afterAddition = observedState(elements: [
            (makeElement(label: "Delete", identifier: "delete_new"), "delete_new"),
            (makeElement(label: "Delete", identifier: "delete_first"), "delete_first"),
            (makeElement(label: "Delete", identifier: "delete_second"), "delete_second"),
        ])
        let runtime = heistRuntime(
            observations: [initialState, afterAddition],
            execute: { command in
                executedCommands.append(command)
                return ActionResult(success: true, method: .activate)
            }
        )
        let plan = try HeistPlan(body: [
            .forEachElement(try ForEachElementStep(
                matching: matching,
                limit: 10,
                parameter: "target",
                body: [.action(try ActionStep(command: .activate(.ref("target"))))]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let forEachResult = try XCTUnwrap(result.heistExecutionPayload?.steps.first?.forEachElementEvidence)

        XCTAssertTrue(result.success)
        XCTAssertEqual(forEachResult.matchedCount, 2)
        XCTAssertEqual(forEachResult.iterationCount, 2)
        XCTAssertEqual(executedCommands, [
            .activate(.predicate(matching, ordinal: 0)),
            .activate(.predicate(matching, ordinal: 0)),
        ])
    }

    func testHeistForEachDoesNotResetOrdinalForStateOnlyMatchMutation() async throws {
        let matching = ElementPredicate(label: "Delete")
        var executedCommands: [ClientMessage] = []
        let initialState = observedState(elements: [
            (makeElement(label: "Delete", identifier: "delete_first", traits: [.button]), "delete_first"),
            (makeElement(label: "Delete", identifier: "delete_second", traits: [.button]), "delete_second"),
        ])
        let stateOnlyMutation = observedState(elements: [
            (makeElement(label: "Delete", identifier: "delete_first", traits: [.button, .selected]), "delete_first"),
            (makeElement(label: "Delete", identifier: "delete_second", traits: [.button]), "delete_second"),
        ])
        let runtime = heistRuntime(
            observations: [initialState, stateOnlyMutation],
            execute: { command in
                executedCommands.append(command)
                return ActionResult(success: true, method: .activate)
            }
        )
        let plan = try HeistPlan(body: [
            .forEachElement(try ForEachElementStep(
                matching: matching,
                limit: 10,
                parameter: "target",
                body: [.action(try ActionStep(command: .activate(.ref("target"))))]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let forEachResult = try XCTUnwrap(result.heistExecutionPayload?.steps.first?.forEachElementEvidence)

        XCTAssertTrue(result.success)
        XCTAssertEqual(forEachResult.matchedCount, 2)
        XCTAssertEqual(forEachResult.iterationCount, 2)
        XCTAssertEqual(executedCommands, [
            .activate(.predicate(matching, ordinal: 0)),
            .activate(.predicate(matching, ordinal: 1)),
        ])
    }

    func testHeistForEachBodyFailureStopsBeforeFollowingTopLevelSteps() async throws {
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
        let plan = try HeistPlan(body: [
            .forEachElement(try ForEachElementStep(
                matching: matching,
                limit: 10,
                parameter: "target",
                body: [.action(try ActionStep(command: .activate(.ref("target"))))]
            )),
            .warn(WarnStep(message: "should not run")),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let forEachStep = try XCTUnwrap(heist.steps.first)
        let forEachResult = try XCTUnwrap(forEachStep.forEachElementEvidence)
        let failedActionPath = "$.body[0].for_each_element.iterations[0].body[0]"

        XCTAssertFalse(result.success)
        XCTAssertEqual(heist.abortedAtPath, failedActionPath)
        XCTAssertEqual(heist.steps.map(\.kind), [.forEachElement])
        XCTAssertEqual(forEachResult.matchedCount, 2)
        XCTAssertEqual(forEachResult.iterationCount, 1)
        XCTAssertEqual(forEachResult.failureReason, "iteration 0 failed at \(failedActionPath)")
        XCTAssertEqual(forEachStep.abortedAtChildPath, failedActionPath)
        XCTAssertEqual(forEachStep.children.map(\.kind), [.forEachIteration])
        XCTAssertEqual(forEachStep.children.first?.children.map(\.kind), [.action])
    }

    func testHeistForEachExpectationUsesCurrentSemanticTarget() async throws {
        let matching = ElementPredicate(label: "Delete")
        var executedCommands: [ClientMessage] = []
        var waitedSteps: [ResolvedWaitStep] = []
        let initialState = observedState(elements: [
            (makeElement(label: "Delete", identifier: "delete_first"), "delete_first"),
            (makeElement(label: "Delete", identifier: "delete_second"), "delete_second"),
        ])
        let stillPresentState = observedState(elements: [
            (makeElement(label: "Delete", identifier: "delete_second"), "delete_second"),
        ])
        let waitObservedState = observedState(labels: ["Done"])
        let runtime = heistRuntime(
            observations: [initialState, stillPresentState],
            execute: { command in
                executedCommands.append(command)
                return ActionResult(
                    success: true,
                    method: .activate,
                    accessibilityTrace: AccessibilityTrace(capture: stillPresentState.capture)
                )
            },
            wait: { waitStep, _ in
                waitedSteps.append(waitStep)
                return ActionResult(
                    success: true,
                    method: .wait,
                    accessibilityTrace: AccessibilityTrace(capture: waitObservedState.capture)
                )
            }
        )
        let plan = try HeistPlan(body: [
            .forEachElement(try ForEachElementStep(
                matching: matching,
                limit: 10,
                parameter: "target",
                body: [
                    .action(try ActionStep(
                        command: .activate(.ref("target")),
                        expectation: WaitStep(
                            predicate: .state(.absentTarget(.ref("target"))),
                            timeout: 2
                        )
                    )),
                ]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let forEachResult = try XCTUnwrap(heist.steps.first?.forEachElementEvidence)

        XCTAssertTrue(result.success)
        XCTAssertEqual(forEachResult.iterationCount, 2)
        XCTAssertEqual(executedCommands.first, .activate(.predicate(matching, ordinal: 0)))
        XCTAssertEqual(waitedSteps.first?.predicate, .state(.absentTarget(.predicate(matching, ordinal: 0))))
        XCTAssertEqual(executedCommands.last, .activate(.predicate(matching, ordinal: 0)))
        XCTAssertEqual(waitedSteps.last?.predicate, .state(.absentTarget(.predicate(matching, ordinal: 0))))
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
            "element inflation failed [geometryNotActionable]",
            "method=increment",
            "label=\"Geometry Missing\"",
            "fresh live geometry from element inflation",
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

    func testExecuteTypeTextReportsFinalValueFromInteractionAfterState() async throws {
        brains.tripwire.startPulse()
        let rootView = UIView(frame: UIScreen.main.bounds)
        rootView.backgroundColor = .white

        let textField = UITextField(frame: CGRect(x: 48, y: 180, width: 240, height: 44))
        textField.borderStyle = .roundedRect
        textField.isAccessibilityElement = true
        textField.accessibilityLabel = "Message"
        textField.accessibilityIdentifier = "message_field"
        textField.accessibilityValue = ""
        rootView.addSubview(textField)

        let window = try installModalWindow(rootView: rootView)
        defer {
            brains.stopSemanticObservation()
            brains.tripwire.stopPulse()
            window.rootViewController?.view.accessibilityViewIsModal = false
            window.isHidden = true
        }

        let keyboardImpl = ActionTextInputKeyboardImpl(textField: textField) { [stash = brains.stash] in
            stash.markDirtyFromTripwire()
        }
        brains.safecracker.keyboardBridgeProvider = { keyboardImpl.bridge() }
        await brains.tripwire.yieldFrames(3)

        let result = await brains.executeCommand(.typeText(TypeTextTarget(
            text: "hello",
            elementTarget: .predicate(ElementPredicate(identifier: "message_field"))
        )))

        XCTAssertTrue(result.success, result.message ?? "type_text failed")
        XCTAssertEqual(result.method, .typeText)
        XCTAssertEqual(textField.text, "hello")
        guard case .value(let value) = result.payload else {
            XCTFail("Expected final text value payload, got \(String(describing: result.payload))")
            return
        }
        XCTAssertEqual(value, "hello")
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
            "element inflation failed [noRevealPath]",
            "known target \"Below Fold\"",
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

    func testExecuteRotorDoesNotRequireHostActivationPointOnscreen() async {
        let heistId = "offscreen_rotor_host"
        let screenBounds = ScreenMetrics.current.bounds
        let frame = CGRect(x: 32, y: screenBounds.maxY - 8, width: 240, height: 44)
        let activationPoint = CGPoint(x: frame.midX, y: frame.midY)
        let element = AccessibilityElement.make(
            label: "Offscreen Rotor Host",
            identifier: heistId,
            traits: .staticText,
            shape: .frame(AccessibilityRect(frame)),
            activationPoint: activationPoint,
            customRotors: [.init(name: "Live Rotor")]
        )
        let liveObject = UIView()
        liveObject.accessibilityFrame = frame
        liveObject.accessibilityActivationPoint = activationPoint
        liveObject.accessibilityCustomRotors = [
            UIAccessibilityCustomRotor(name: "Live Rotor") { _ in
                UIAccessibilityCustomRotorItemResult(targetElement: liveObject, targetRange: nil)
            },
        ]
        installScreen(elements: [(element, heistId)], objects: [heistId: liveObject])

        let result = await brains.actions.executeRotor(
            RotorTarget(
                elementTarget: .predicate(ElementPredicate(identifier: "offscreen_rotor_host")),
                selection: .named("Live Rotor")
            )
        )

        XCTAssertTrue(result.success, result.message ?? "rotor failed")
        XCTAssertEqual(result.method, .rotor)
        XCTAssertTrue(result.message?.contains("Rotor 'Live Rotor' found Offscreen Rotor Host") ?? false,
                      result.message ?? "missing rotor success message")
    }

    func testExecuteRotorScrollsViewportTowardResultActivationPoint() async {
        let hostHeistId = "rotor_result_host"
        let resultHeistId = "rotor_result_target"
        let screenBounds = ScreenMetrics.current.bounds
        let scrollView = UIScrollView(frame: screenBounds)
        scrollView.contentSize = CGSize(width: screenBounds.width, height: screenBounds.height + 900)

        let hostFrame = CGRect(x: 32, y: 80, width: 240, height: 44)
        let hostElement = AccessibilityElement.make(
            label: "Rotor Host",
            identifier: hostHeistId,
            traits: .staticText,
            shape: .frame(AccessibilityRect(hostFrame)),
            activationPoint: CGPoint(x: hostFrame.midX, y: hostFrame.midY),
            customRotors: [.init(name: "Live Rotor")]
        )
        let resultFrame = CGRect(x: 32, y: screenBounds.maxY + 240, width: 240, height: 44)
        let resultElement = AccessibilityElement.make(
            label: "Rotor Result",
            identifier: resultHeistId,
            traits: .staticText,
            shape: .frame(AccessibilityRect(resultFrame)),
            activationPoint: CGPoint(x: resultFrame.midX, y: resultFrame.midY)
        )

        let resultObject = UIView()
        resultObject.accessibilityFrame = resultFrame
        resultObject.accessibilityActivationPoint = CGPoint(x: resultFrame.midX, y: resultFrame.midY)

        let hostObject = UIView()
        hostObject.accessibilityFrame = hostFrame
        hostObject.accessibilityActivationPoint = CGPoint(x: hostFrame.midX, y: hostFrame.midY)
        hostObject.accessibilityCustomRotors = [
            UIAccessibilityCustomRotor(name: "Live Rotor") { _ in
                UIAccessibilityCustomRotorItemResult(targetElement: resultObject, targetRange: nil)
            },
        ]

        brains.stash.installScreenForTesting(Screen(
            elements: [
                hostHeistId: Screen.ScreenElement(
                    heistId: hostHeistId,
                    contentSpaceOrigin: nil,
                    element: hostElement
                ),
                resultHeistId: Screen.ScreenElement(
                    heistId: resultHeistId,
                    contentSpaceOrigin: nil,
                    element: resultElement
                ),
            ],
            hierarchy: [
                .element(hostElement, traversalIndex: 0),
                .element(resultElement, traversalIndex: 1),
            ],
            containerNames: [:],
            heistIdByElement: [
                hostElement: hostHeistId,
                resultElement: resultHeistId,
            ],
            elementRefs: [
                hostHeistId: .init(object: hostObject, scrollView: scrollView),
                resultHeistId: .init(object: resultObject, scrollView: scrollView),
            ],
            firstResponderHeistId: nil,
            scrollableContainerViews: [:]
        ))

        XCTAssertEqual(scrollView.contentOffset, .zero)

        let result = await brains.actions.executeRotor(
            RotorTarget(
                elementTarget: .predicate(ElementPredicate(identifier: hostHeistId)),
                selection: .named("Live Rotor")
            )
        )

        XCTAssertTrue(result.success, result.message ?? "rotor failed")
        XCTAssertEqual(result.method, .rotor)
        XCTAssertGreaterThan(scrollView.contentOffset.y, 0)
        XCTAssertTrue(result.message?.contains("Rotor 'Live Rotor' found Rotor Result") ?? false,
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

        XCTAssertEqual(brains.stash.settledScreen, .empty)
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
        let screenElement = try XCTUnwrap(screen.orderedElements.first { $0.element.label == label })
        let context = PredicateSelectionContext(
            elements: screen.orderedElements.map {
                PredicateSelectionContext.Element(
                    id: $0.heistId,
                    element: TheStash.WireConversion.convert($0.element)
                )
            },
            screenId: screen.id,
            semanticHash: screen.semanticHash,
            scope: .visible
        )
        return try XCTUnwrap(minimumUniquePredicate(for: screenElement.heistId, in: context)).target
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
        assertSameActionMessage(
            name,
            single: normalizedActionMessage(single.message, normalizingTimeoutDuration: normalizingTimeoutDuration),
            heist: normalizedActionMessage(heist.message, normalizingTimeoutDuration: normalizingTimeoutDuration),
            file: file,
            line: line
        )
    }

    private func assertSameActionMessage(
        _ name: String,
        single: String?,
        heist: String?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if let single,
           let heist,
           single.contains("No match for:"),
           heist.contains("No match for:") {
            XCTAssertEqual(firstLine(single), firstLine(heist), name, file: file, line: line)
            XCTAssertTrue(single.contains("Next:"), name, file: file, line: line)
            XCTAssertTrue(heist.contains("Next:"), name, file: file, line: line)
            return
        }
        XCTAssertEqual(heist, single, name, file: file, line: line)
    }

    private func firstLine(_ message: String) -> Substring {
        message.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
    }

    private func heistStepResult(for command: ClientMessage) async throws -> ActionResult {
        let step: HeistStep
        if case .wait(let target) = command {
            step = .wait(WaitStep(predicate: target.predicate, timeout: target.resolvedTimeout))
        } else {
            do {
                step = .action(try ActionStep(command: command))
            } catch {
                XCTFail("Expected heist primitive command for \(command.wireType.rawValue): \(error)")
                return ActionResultBuilder(method: .heistPlan).failure(errorKind: .validationError)
            }
        }

        let result = await brains.executeHeistPlan(try HeistPlan(body: [step]))
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

    private func waitForSettledSemanticWaiter(
        on stash: TheStash,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<50 where stash.semanticObservationStream.settledWaiterCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(stash.semanticObservationStream.settledWaiterCount, 1, file: file, line: line)
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
        wait: (@MainActor (ResolvedWaitStep, AccessibilityTrace?) async -> ActionResult)? = nil,
        observedScopes: (@MainActor (SemanticObservationScope) -> Void)? = nil,
        observedTimeouts: (@MainActor (Double?) -> Void)? = nil,
        unavailableObservationCount: Int = 0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> TheBrains.HeistExecutionRuntime {
        let observationSource = ScriptedHeistObservationSource(
            observations: observations,
            unavailableObservationCount: unavailableObservationCount,
            observedScopes: observedScopes,
            observedTimeouts: observedTimeouts,
            file: file,
            line: line
        )

        return TheBrains.HeistExecutionRuntime(
            execute: { command in
                if let execute {
                    return await execute(command)
                }
                return ActionResult(success: true, method: .heistPlan, message: command.wireType.rawValue)
            },
            wait: { waitStep, initialTrace in
                if let wait {
                    return self.heistWaitReceipt(for: waitStep, result: await wait(waitStep, initialTrace))
                }
                if let initialTrace {
                    let expectation = PredicateEvaluation.evaluate(waitStep.predicate, in: initialTrace)
                    if expectation.met || waitStep.timeout == 0 {
                        let result = ActionResult(
                            success: expectation.met,
                            method: .wait,
                            message: expectation.actual,
                            errorKind: expectation.met ? nil : .timeout,
                            accessibilityTrace: initialTrace
                        )
                        return HeistWaitReceipt(actionResult: result, expectation: expectation)
                    }
                }
                let state = observationSource.currentState
                let trace = state.map { AccessibilityTrace(capture: $0.capture) }
                let met = PredicateEvaluation.evaluate(
                    waitStep.predicate,
                    currentElements: state?.interface.projectedElements ?? [],
                    delta: trace?.endpointDelta
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
            waitForCases: { cases, timeout in
                let start = CFAbsoluteTimeGetCurrent()
                let scope = cases.observationScope
                var selected = PredicateCaseSelection.unevaluated(cases)
                var changeBaselineSequence: UInt64?
                var lastSummary: String?
                let deadline = start + timeout
                repeat {
                    let observation = observationSource.next(
                        scope: scope,
                        timeout: min(max(0, deadline - CFAbsoluteTimeGetCurrent()), 1.0)
                    )
                    guard let observation else {
                        if timeout == 0 { break }
                        continue
                    }
                    lastSummary = observation.summary
                    if changeBaselineSequence == nil {
                        changeBaselineSequence = observation.event.sequence
                    }
                    selected = PredicateCaseSelection.evaluate(
                        cases,
                        observation: observation,
                        changeBaselineSequence: changeBaselineSequence
                    )
                    if selected.selectedCaseIndex != nil || timeout == 0 { break }
                } while CFAbsoluteTimeGetCurrent() < deadline

                return HeistCaseSelectionResult(
                    cases: selected.cases,
                    selectedCaseIndex: selected.selectedCaseIndex,
                    elapsedMs: Int((CFAbsoluteTimeGetCurrent() - start) * 1000),
                    timeout: timeout,
                    timedOut: selected.selectedCaseIndex == nil,
                    lastObservedSummary: lastSummary
                )
            },
            observeSemanticState: { scope, _, timeout in
                observationSource.next(scope: scope, timeout: timeout)
            }
        )
    }

    private func heistWaitReceipt(
        for step: ResolvedWaitStep,
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
        return message?
            .replacingOccurrences(
                of: #"timed out after [0-9.]+s"#,
                with: "timed out after <duration>s",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"last settled: sequence [0-9]+"#,
                with: "last settled: sequence <sequence>",
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

@MainActor
private final class ScriptedHeistObservationSource {
    private var remainingObservations: [PostActionObservation.BeforeState]
    private var remainingUnavailableObservations: Int
    private var previousObservation: SettledSemanticObservation?
    private var previousCapture: AccessibilityTrace.Capture?
    private var nextObservationSequence: UInt64 = 0
    private let observedScopes: (@MainActor (SemanticObservationScope) -> Void)?
    private let observedTimeouts: (@MainActor (Double?) -> Void)?
    private let file: StaticString
    private let line: UInt

    init(
        observations: [PostActionObservation.BeforeState],
        unavailableObservationCount: Int,
        observedScopes: (@MainActor (SemanticObservationScope) -> Void)?,
        observedTimeouts: (@MainActor (Double?) -> Void)?,
        file: StaticString,
        line: UInt
    ) {
        remainingObservations = observations
        remainingUnavailableObservations = unavailableObservationCount
        self.observedScopes = observedScopes
        self.observedTimeouts = observedTimeouts
        self.file = file
        self.line = line
    }

    var currentState: PostActionObservation.BeforeState? {
        remainingObservations.first
    }

    func next(
        scope: SemanticObservationScope,
        timeout: Double?
    ) -> HeistSemanticObservation? {
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
        nextObservationSequence += 1
        let settledObservation = SettledSemanticObservation(
            sequence: nextObservationSequence,
            scope: scope,
            screen: .empty,
            tripwireSignal: .empty
        )
        let trace = if let previousCapture {
            AccessibilityTrace(captures: [previousCapture, state.capture])
        } else {
            AccessibilityTrace(capture: state.capture)
        }
        let event = SettledSemanticObservationEvent(
            sequence: nextObservationSequence,
            scope: scope,
            observation: settledObservation,
            previous: previousObservation,
            trace: trace,
            delta: trace.endpointDelta
        )
        previousObservation = settledObservation
        previousCapture = trace.captures.last
        return HeistSemanticObservation(
            event: event,
            state: state,
            accessibilityTrace: trace,
            delta: event.delta,
            summary: "known: \(state.interface.projectedElements.count) elements"
        )
    }
}

private extension ActionResult {
    var heistExecutionPayload: HeistExecutionResult? {
        guard case .heistExecution(let result) = payload else { return nil }
        return result
    }
}

#endif
