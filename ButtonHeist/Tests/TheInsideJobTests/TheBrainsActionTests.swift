#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@_spi(ButtonHeistInternals) @testable import ThePlans
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

private final class ActionActivationOverrideView: UIView {
    private(set) var activationCount = 0

    override func accessibilityActivate() -> Bool {
        activationCount += 1
        return true
    }
}

private final class RefusingActivationView: UIView {
    private(set) var activationCount = 0

    override func accessibilityActivate() -> Bool {
        activationCount += 1
        return false
    }
}

@MainActor
private final class ActionTextInputKeyboardImpl: NSObject {
    @MainActor
    private final class TextInputDelegate: NSObject, UIKeyInput {
        private weak var textField: UITextField?
        private let onInput: @MainActor () -> Void

        init(textField: UITextField, onInput: @escaping @MainActor () -> Void) {
            self.textField = textField
            self.onInput = onInput
        }

        var hasText: Bool { textField?.text?.isEmpty == false }

        func insertText(_ text: String) {
            updateText((textField?.text ?? "") + text)
        }

        func deleteBackward() {
            var value = textField?.text ?? ""
            guard !value.isEmpty else { return }
            value.removeLast()
            updateText(value)
        }

        private func updateText(_ text: String) {
            textField?.text = text
            textField?.accessibilityValue = text
            onInput()
        }
    }

    private let inputDelegate: TextInputDelegate
    private weak var textField: UITextField?
    private let onInput: @MainActor () -> Void

    init(textField: UITextField, onInput: @escaping @MainActor () -> Void) {
        self.textField = textField
        self.onInput = onInput
        inputDelegate = TextInputDelegate(textField: textField, onInput: onInput)
    }

    @objc(delegate)
    func delegate() -> AnyObject? {
        inputDelegate
    }

    @objc(addInputString:)
    func addInputString(_ text: NSString) {
        inputDelegate.insertText(text as String)
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

    @objc func decline(_ action: UIAccessibilityCustomAction) -> Bool {
        invocationCount += 1
        return false
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
        let heistId: HeistId = "header_title"
        installScreen(elements: [(element, heistId)])

        let before = brains.postActionObservation.captureSemanticState()
        XCTAssertEqual(before.snapshot.count, 1)
        XCTAssertEqual(before.snapshot.first?.heistId, heistId)
        XCTAssertEqual(before.elements.count, 1)
    }

    func testInteractionObservationBeforeStateDoesNotReuseInvalidatedSettledObservation() async {
        installScreen(elements: [(makeElement(label: "Title", traits: .header), "header_title")])
        brains.stash.invalidateSettledObservationFromTripwire()

        let current = await withNoTraversableWindows {
            await brains.interactionObservation.prepareBeforeState(timeout: 0.001)
        }

        XCTAssertNil(
            current,
            "invalidated settled observation must not be returned when no live tree is readable"
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
        XCTAssertEqual(result.errorKind, .accessibilityTreeUnavailable)
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
            brains.stash.settledSemanticScreen.orderedElements.contains { $0.element.label == "Visible Evidence Action" },
            "the observed full tree should be committed so action resolution sees live evidence"
        )
    }

    func testExecuteIncrementFailsWhenElementIsNotAdjustable() async {
        let heistId: HeistId = "live_button"
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
        let heistId: HeistId = "live_button"
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
            CustomActionTarget(elementTarget: .predicate(ElementPredicate(label: "Options")), actionName: "Archive")
        )

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.method, .customAction)
        XCTAssertEqual(customActionTarget.invocationCount, 1)
    }

    func testExecuteCustomActionSelectorDeclineReportsFailure() async {
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
            CustomActionTarget(elementTarget: .predicate(ElementPredicate(label: "Options")), actionName: "Archive")
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

        let result = await brains.actions.executeActivate(.predicate(ElementPredicate(identifier: "plain_action")))

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(liveObject.activationCount, 1)
    }

    func testExecuteActivateFailsForNoTraitElementWithoutActivationSignal() async {
        let heistId: HeistId = "plain_label"
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

        let success = await brains.executeRuntimeAction(.activate(.predicate(ElementPredicate(identifier: "trace_success"))))
        XCTAssertTrue(success.success, success.message ?? "activate failed")
        XCTAssertNotNil(success.accessibilityTrace?.captures.last)

        let failure = await brains.executeRuntimeAction(.activate(.predicate(ElementPredicate(identifier: "trace_failure"))))
        XCTAssertFalse(failure.success)
        XCTAssertEqual(failure.method, .activate)
        let afterCapture = try XCTUnwrap(failure.accessibilityTrace?.captures.last)
        XCTAssertTrue(afterCapture.interface.projectedElements.contains {
            $0.identifier == "trace_failure"
        })
    }

    func testExecuteActivateBlocksDisabledElementWithActivationOverride() async {
        let heistId: HeistId = "disabled_action"
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
        let heistId: HeistId = "live_slider"
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
        let sourceScreen = Screen.makeForTests(elements: [(sourceElement, HeistId(rawValue: "quantity_0"))])
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
            elements: [(currentElement, HeistId(rawValue: "quantity_1"))],
            objects: [HeistId(rawValue: "quantity_1"): liveObject]
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
        let sourceScreen = Screen.makeForTests(elements: [(sourceElement, HeistId(rawValue: "quantity_0"))])
        let currentElement = makeElement(
            label: "Quantity",
            value: "1",
            identifier: "quantity_stepper",
            traits: .adjustable
        )
        let liveObject = AdjustableGeometryView(frame: .zero, activationPoint: CGPoint(x: 170, y: 202))
        brains.stash.installScreenForTesting(.makeForTests(
            elements: [(currentElement, HeistId(rawValue: "quantity_1"))],
            objects: [HeistId(rawValue: "quantity_1"): liveObject]
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
        let customAction = CustomActionTarget(elementTarget: target, actionName: "Archive")
        let rotor = RotorTarget(elementTarget: target, selection: .named("Links"))
        let tap = TapTarget(selection: .element(target))
        let swipe = SwipeTarget(selection: .elementDirection(target, .left))
        let typeText = TypeTextTarget(text: "hello", elementTarget: target)
        let wait = WaitTarget(predicate: .state(.exists(matcher)), timeout: 0.01)
        let commands: [(String, RuntimeActionMessage, HeistStep, Bool)] = [
            ("activate", .activate(target), .action(try ActionStep(command: .activate(.target(target)))), false),
            ("custom action", .performCustomAction(customAction), .action(try ActionStep(
                command: .customAction(name: customAction.actionName, target: .target(customAction.elementTarget))
            )), false),
            ("rotor", .rotor(rotor), .action(try ActionStep(
                command: .rotor(selection: rotor.selection, target: .target(rotor.elementTarget), direction: rotor.direction)
            )), false),
            ("tap", .oneFingerTap(tap), .action(try ActionStep(command: .mechanicalTap(tap))), false),
            ("swipe", .swipe(swipe), .action(try ActionStep(command: .mechanicalSwipe(swipe))), false),
            ("type text", .typeText(typeText), .action(try ActionStep(command: .typeText(
                text: .literal(typeText.text),
                target: typeText.elementTarget.map(ElementTargetExpr.target),
                replacingExisting: typeText.replacingExisting
            ))), false),
            ("wait", .wait(wait), .wait(WaitStep(predicate: wait.predicate, timeout: wait.resolvedTimeout)), true),
        ]

        for (label, command, heistStep, normalizingTimeoutDuration) in commands {
            brains.clearCache()
            let single = await brains.executeRuntimeAction(command)
            brains.clearCache()
            let heist = try await heistStepResult(for: heistStep, runtimeType: command.runtimeType)
            assertSameActionResult(
                label,
                single: single,
                heist: heist,
                normalizingTimeoutDuration: normalizingTimeoutDuration
            )
        }
    }

    func testHeistPlanDispatchesEveryDurableActionCommandThroughRuntime() async throws {
        let target = ElementTarget.predicate(ElementPredicate(identifier: "target"))
        let point = GesturePointSelection.coordinate(ScreenPoint(x: 10, y: 20))
        let commands: [HeistActionCommand] = [
            .activate(.target(target)),
            .increment(.target(target)),
            .decrement(.target(target)),
            .customAction(name: "Archive", target: .target(target)),
            .rotor(selection: .named("Errors"), target: .target(target), direction: .next),
            .typeText(text: .literal("hello"), target: .target(target)),
            .mechanicalTap(TapTarget(selection: point)),
            .mechanicalLongPress(LongPressTarget(selection: point)),
            .mechanicalSwipe(SwipeTarget(selection: .point(start: .coordinate(ScreenPoint(x: 20, y: 20)), destination: .direction(.left)))),
            .mechanicalDrag(DragTarget(start: .coordinate(ScreenPoint(x: 20, y: 20)), end: ScreenPoint(x: 80, y: 80))),
            .editAction(EditActionTarget(action: .paste)),
            .setPasteboard(SetPasteboardTarget(text: "clipboard")),
            .takeScreenshot,
            .dismissKeyboard,
        ]
        var dispatchedTypes: [RuntimeActionType] = []
        let runtime = heistRuntime(observations: []) { command in
            dispatchedTypes.append(command.runtimeType)
            return ActionResult(success: true, method: .heistPlan, message: command.runtimeType.rawValue)
        }
        let plan = try HeistPlan(body: commands.map { .action(try ActionStep(command: $0)) })

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertTrue(result.success, result.message ?? "heist failed")
        XCTAssertEqual(dispatchedTypes, commands.map(\.runtimeActionType))
        guard case .heistExecution(let heist) = result.payload else {
            return XCTFail("Expected heist execution payload")
        }
        XCTAssertEqual(heist.steps.count, commands.count)
        XCTAssertTrue(heist.steps.allSatisfy { $0.status == HeistExecutionStepStatus.passed })
    }

    func testViewportDebugCommandsResolveForDirectRuntimeDispatch() throws {
        let target = ElementTarget.predicate(ElementPredicate(identifier: "target"))
        let commands: [(HeistActionCommand, RuntimeActionType)] = [
            (.viewportScroll(ScrollTarget(direction: .down)), .scroll),
            (.viewportScrollToVisible(.target(target)), .scrollToVisible),
            (.viewportScrollToEdge(ScrollToEdgeTarget(edge: .bottom)), .scrollToEdge),
        ]

        for (command, expectedType) in commands {
            XCTAssertNotNil(command.durableHeistActionFailure)
            XCTAssertEqual(try command.resolveForRuntimeDispatch(in: .empty).runtimeType, expectedType)
        }
    }

    func testHeistActionAndWaitStepsUseSeparateRuntimeTransitions() async throws {
        let observedReady = observedState(labels: ["Ready"])
        let target = ElementTarget.predicate(ElementPredicate(identifier: "target"))
        var dispatchedTypes: [RuntimeActionType] = []
        var waitRequests: [TheBrains.HeistRuntimeWaitRequest] = []
        let runtime = heistRuntime(
            observations: [],
            execute: { command in
                dispatchedTypes.append(command.runtimeType)
                return ActionResult(success: true, method: .activate, message: command.runtimeType.rawValue)
            },
            wait: { request in
                waitRequests.append(request)
                return ActionResult(
                    success: true,
                    method: .wait,
                    accessibilityTrace: AccessibilityTrace(capture: observedReady.capture)
                )
            }
        )
        let plan = try HeistPlan(body: [
            .action(try ActionStep(command: .activate(.target(target)))),
            .wait(WaitStep(
                predicate: .state(.exists(ElementPredicate(label: "Ready"))),
                timeout: 0
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist: HeistExecutionResult = try XCTUnwrap(result.heistExecutionPayload)
        let actionStep = try XCTUnwrap(heist.steps.first)
        let waitStep = try XCTUnwrap(heist.steps.dropFirst().first)

        XCTAssertTrue(result.success, result.message ?? "heist failed")
        XCTAssertEqual(dispatchedTypes, [.activate])
        XCTAssertEqual(waitRequests.count, 1)
        if case .standalone(let request)? = waitRequests.first {
            XCTAssertEqual(request.predicate, .state(.exists(ElementPredicate(label: "Ready"))))
        } else {
            XCTFail("Expected standalone wait request")
        }
        XCTAssertEqual(heist.steps.map(\.kind), [HeistExecutionStepKind.action, .wait])
        XCTAssertNotNil(actionStep.actionEvidence)
        XCTAssertNil(actionStep.waitEvidence)
        XCTAssertNil(waitStep.actionEvidence)
        let waitEvidence = try XCTUnwrap(waitStep.waitEvidence)
        XCTAssertTrue(waitEvidence.expectation.met)
    }

    func testHeistActivateRecordsWeakAffordanceWarningOnSuccessfulActionEvidence() async throws {
        let target = ElementTarget.predicate(ElementPredicate(label: "Checkout"))
        let subject = makeTestHeistElement(
            label: "Checkout",
            traits: [.staticText],
            actions: [.activate]
        )
        let runtime = heistRuntime(
            observations: [],
            execute: { _ in
                ActionResult(
                    success: true,
                    method: .activate,
                    subjectEvidence: ActionSubjectEvidence(
                        source: .resolvedSemanticTarget,
                        target: target,
                        element: subject
                    )
                )
            }
        )
        let plan = try HeistPlan(body: [
            .action(try ActionStep(command: .activate(.target(target)))),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertTrue(result.success, result.message ?? "heist failed")
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let warning = try XCTUnwrap(heist.steps.first?.actionEvidence?.warning)
        XCTAssertEqual(warning.code, HeistActionWarning.activationWeakAffordanceEvidenceCode)
        XCTAssertEqual(
            warning.message,
            "activate succeeded, but the target does not advertise a primary activation affordance"
        )
        XCTAssertEqual(warning.evidence, #"label="Checkout" traits=[staticText] actions=[activate]"#)
        XCTAssertEqual(heist.warnings, [])
        XCTAssertEqual(heist.evidenceRollup.warnings.all, [
            .action(path: "$.body[0]", warning: warning),
        ])
    }

    func testHeistFailureRecordsScreenshotAsActionEvidence() async throws {
        let target = ElementTarget.predicate(ElementPredicate(identifier: "target"))
        let screenshot = ScreenPayload(
            pngData: "png",
            width: 10,
            height: 20,
            timestamp: Date(timeIntervalSince1970: 0),
            interface: Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
        )
        var dispatchedTypes: [RuntimeActionType] = []
        let runtime = heistRuntime(observations: []) { command in
            dispatchedTypes.append(command.runtimeType)
            if case .takeScreenshot = command {
                return ActionResult.success(payload: .screenshot(screenshot))
            }
            return ActionResult(
                success: false,
                method: .activate,
                message: "activate failed",
                errorKind: .actionFailed
            )
        }
        let plan = try HeistPlan(body: [
            .action(try ActionStep(command: .activate(.target(target)))),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertFalse(result.success)
        XCTAssertEqual(dispatchedTypes, [.activate, .takeScreenshot])
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        XCTAssertEqual(heist.abortedAtPath, "$.body[0]")
        XCTAssertEqual(heist.executedTopLevelStepCount, 1)
        XCTAssertEqual(heist.outputReceiptNodes.count, 2)
        XCTAssertEqual(heist.steps.map(\.path), ["$.body[0]", "$.body[0].failure.actions[0]"])
        let screenshotStep = try XCTUnwrap(heist.steps.last)
        XCTAssertEqual(screenshotStep.kind, .action)
        XCTAssertEqual(screenshotStep.status, .passed)
        XCTAssertEqual(screenshotStep.actionEvidence?.command, .takeScreenshot)
        guard case .screenshot(let payload) = screenshotStep.actionEvidence?.actionResult?.payload else {
            return XCTFail("Expected screenshot action payload")
        }
        XCTAssertEqual(payload, screenshot)
    }

    func testHeistFailurePhaseSkipsRemainingStepsWithoutDispatchingActions() async throws {
        let target = ElementTarget.predicate(ElementPredicate(identifier: "target"))
        var dispatchedTypes: [RuntimeActionType] = []
        let runtime = heistRuntime(observations: []) { command in
            dispatchedTypes.append(command.runtimeType)
            if case .takeScreenshot = command {
                return ActionResult(success: true, method: .takeScreenshot)
            }
            return ActionResult(
                success: false,
                method: .activate,
                message: "activate failed",
                errorKind: .actionFailed
            )
        }
        let plan = try HeistPlan(body: [
            .action(try ActionStep(command: .activate(.target(target)))),
            .action(try ActionStep(command: .setPasteboard(SetPasteboardTarget(text: "not dispatched")))),
            .heist(try HeistPlan(body: [
                .action(try ActionStep(command: .dismissKeyboard)),
            ])),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertFalse(result.success)
        XCTAssertEqual(dispatchedTypes, [.activate, .takeScreenshot])
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        XCTAssertEqual(heist.abortedAtPath, "$.body[0]")
        XCTAssertEqual(heist.steps.map(\.path), [
            "$.body[0]",
            "$.body[1]",
            "$.body[2]",
            "$.body[0].failure.actions[0]",
        ])
        XCTAssertEqual(heist.steps.map(\.status), [.failed, .skipped, .skipped, .passed])
        let skippedInlineHeist = try XCTUnwrap(heist.steps.dropFirst(2).first)
        XCTAssertEqual(skippedInlineHeist.children.map(\.status), [.skipped])
    }

    func testHeistConditionalSelectsFirstMatchingCaseOnce() async throws {
        let runtime = heistRuntime(observations: [
            observedState(labels: ["Home", "Login"]),
        ])
        let plan = try HeistPlan(body: [
            .conditional(try ConditionalStep(cases: [
                PredicateCase(
                    predicate: .exists(.label("Home")),
                    body: [.warn(WarnStep(message: "home flow"))]
                ),
                PredicateCase(
                    predicate: .exists(.label("Login")),
                    body: [.fail(FailStep(message: "wrong branch"))]
                ),
            ])),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.success)
        XCTAssertEqual(step.kind, .conditional)
        XCTAssertEqual(step.caseSelectionEvidence?.selection.outcome, HeistCaseSelectionOutcome.matchedCase(index: 0))
        XCTAssertEqual(step.children.map(\.kind), [.warn])
    }

    func testHeistConditionalUnmatchedWithoutElseContinues() async throws {
        let runtime = heistRuntime(observations: [
            observedState(labels: ["Settings"]),
        ])
        let plan = try HeistPlan(body: [
            .conditional(try ConditionalStep(cases: [
                PredicateCase(
                    predicate: .exists(.label("Home")),
                    body: [.fail(FailStep(message: "should not run"))]
                ),
            ])),
            .warn(WarnStep(message: "continued")),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)

        XCTAssertTrue(result.success)
        XCTAssertEqual(heist.steps.map(\.kind), [.conditional, .warn])
        XCTAssertEqual(
            heist.steps.first?.caseSelectionEvidence?.selection.outcome,
            HeistCaseSelectionOutcome.elseBranch(reason: .noMatch)
        )
    }

    func testHeistWaitForTimeoutWithoutElseFails() async throws {
        let runtime = heistRuntime(observations: [
            observedState(labels: ["Settings"]),
        ])
        let plan = try HeistPlan(body: [
            .wait(WaitStep(
                predicate: .state(.exists(ElementPredicate(label: "Home"))),
                timeout: 0
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertFalse(result.success)
        XCTAssertEqual(step.kind, .wait)
        XCTAssertEqual(step.waitEvidence?.expectation.met, false)
        XCTAssertEqual(step.children.map(\.kind), [])
    }

    func testHeistWaitForTimeoutWithElseRunsElse() async throws {
        let runtime = heistRuntime(observations: [
            observedState(labels: ["Settings"]),
        ])
        let plan = try HeistPlan(body: [
            .wait(WaitStep(
                predicate: .state(.exists(ElementPredicate(label: "Home"))),
                timeout: 0,
                elseBody: [.warn(WarnStep(message: "no known state appeared"))]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.success)
        XCTAssertEqual(step.kind, .wait)
        XCTAssertEqual(step.waitEvidence?.expectation.met, false)
        XCTAssertEqual(step.children.map(\.kind), [.warn])
    }

    func testHeistRepeatUntilRepeatsBodyUntilPredicateMet() async throws {
        var incrementCount = 0
        let runtime = heistRuntime(
            observations: [
                observedState(elements: [(makeElement(value: "0", identifier: "quantity"), "quantity")]),
                observedState(elements: [(makeElement(value: "1", identifier: "quantity"), "quantity")]),
                observedState(elements: [(makeElement(value: "2", identifier: "quantity"), "quantity")]),
            ],
            execute: { command in
                if case .increment = command {
                    incrementCount += 1
                }
                return ActionResult(success: true, method: .increment, message: command.runtimeType.rawValue)
            }
        )
        let plan = try HeistPlan(body: [
            .repeatUntil(try RepeatUntilStep(
                predicate: .exists(.element(identifier: "quantity", value: "2")),
                timeout: 1,
                body: [
                    .action(try ActionStep(command: .increment(.predicate(.identifier("quantity"))))),
                ]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.success, result.message ?? "repeat_until failed")
        XCTAssertEqual(incrementCount, 2)
        XCTAssertEqual(step.kind, .repeatUntil)
        XCTAssertEqual(step.status, .passed)
        XCTAssertEqual(step.repeatUntilEvidence?.iterationCount, 2)
        XCTAssertEqual(step.repeatUntilEvidence?.expectation.met, true)
        XCTAssertNil(step.repeatUntilEvidence?.failureReason)
        XCTAssertNil(step.failure)
        XCTAssertEqual(step.children.map(\.kind), [.repeatUntilIteration, .repeatUntilIteration])
    }

    func testHeistRepeatUntilWaitsForOneSettledTickAfterBodyBeforeStopCheck() async throws {
        var incrementCount = 0
        var observedTimeouts: [Double?] = []
        let runtime = heistRuntime(
            observations: [
                observedState(elements: [(makeElement(value: "0", identifier: "quantity"), "quantity")]),
                observedState(elements: [(makeElement(value: "100", identifier: "quantity"), "quantity")]),
            ],
            execute: { command in
                if case .increment = command {
                    incrementCount += 1
                }
                return ActionResult(success: true, method: .increment, message: command.runtimeType.rawValue)
            },
            observedTimeouts: { observedTimeouts.append($0) }
        )
        let plan = try HeistPlan(body: [
            .repeatUntil(try RepeatUntilStep(
                predicate: .exists(.element(identifier: "quantity", value: "100")),
                timeout: 5,
                body: [
                    .action(try ActionStep(command: .increment(.predicate(.identifier("quantity"))))),
                ]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.success, result.message ?? "repeat_until failed")
        XCTAssertEqual(incrementCount, 1)
        XCTAssertEqual(step.repeatUntilEvidence?.iterationCount, 1)
        XCTAssertEqual(step.repeatUntilEvidence?.expectation.met, true)
        XCTAssertEqual(observedTimeouts.count, 1)
        let observedTimeout = try XCTUnwrap(observedTimeouts.first.flatMap { $0 })
        XCTAssertEqual(observedTimeout, defaultActionExpectationTimeout, accuracy: 0.1)
    }

    func testHeistRepeatUntilSucceedsWhenBodyActionFailsAfterPredicateMet() async throws {
        var activationCount = 0
        let runtime = heistRuntime(
            observations: [
                observedState(elements: [(makeElement(value: "0", identifier: "quantity"), "quantity")]),
                observedState(elements: [(makeElement(value: "1", identifier: "quantity"), "quantity")]),
                observedState(elements: [(makeElement(value: "2", identifier: "quantity"), "quantity")]),
            ],
            execute: { command in
                if case .activate = command {
                    activationCount += 1
                    if activationCount == 2 {
                        return ActionResult(
                            success: false,
                            method: .activate,
                            message: "Element is disabled (has 'notEnabled' trait)",
                            errorKind: .actionFailed
                        )
                    }
                }
                return ActionResult(success: true, method: .activate, message: command.runtimeType.rawValue)
            }
        )
        let plan = try HeistPlan(body: [
            .repeatUntil(try RepeatUntilStep(
                predicate: .exists(.element(identifier: "quantity", value: "2")),
                timeout: 1,
                body: [
                    .action(try ActionStep(command: .activate(.predicate(.identifier("quantity"))))),
                ]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)
        let secondIteration = try XCTUnwrap(step.children.last)

        XCTAssertTrue(result.success, result.message ?? "repeat_until failed")
        XCTAssertNil(heist.abortedAtPath)
        XCTAssertEqual(activationCount, 2)
        XCTAssertEqual(step.repeatUntilEvidence?.iterationCount, 2)
        XCTAssertEqual(step.repeatUntilEvidence?.expectation.met, true)
        XCTAssertEqual(step.children.map(\.kind), [.repeatUntilIteration, .repeatUntilIteration])
        XCTAssertEqual(secondIteration.status, .passed)
        XCTAssertNil(secondIteration.abortedAtChildPath)
        XCTAssertTrue(secondIteration.children.isEmpty)
    }

    func testHeistRepeatUntilBodyActionFailureStillFailsWhenPredicateUnmet() async throws {
        var activationCount = 0
        let runtime = heistRuntime(
            observations: [
                observedState(elements: [(makeElement(value: "0", identifier: "quantity"), "quantity")]),
                observedState(elements: [(makeElement(value: "1", identifier: "quantity"), "quantity")]),
                observedState(elements: [(makeElement(value: "1", identifier: "quantity"), "quantity")]),
            ],
            execute: { command in
                if case .activate = command {
                    activationCount += 1
                    if activationCount == 2 {
                        return ActionResult(
                            success: false,
                            method: .activate,
                            message: "Element is disabled (has 'notEnabled' trait)",
                            errorKind: .actionFailed
                        )
                    }
                }
                return ActionResult(success: true, method: .activate, message: command.runtimeType.rawValue)
            }
        )
        let plan = try HeistPlan(body: [
            .repeatUntil(try RepeatUntilStep(
                predicate: .exists(.element(identifier: "quantity", value: "2")),
                timeout: 1,
                body: [
                    .action(try ActionStep(command: .activate(.predicate(.identifier("quantity"))))),
                ]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)
        let failedIteration = try XCTUnwrap(step.children.last)
        let failedRetry = try XCTUnwrap(failedIteration.children.first)
        let failedRetryPath = "$.body[0].repeat_until.iterations[1].body[0]"

        XCTAssertFalse(result.success)
        XCTAssertEqual(activationCount, 2)
        XCTAssertEqual(heist.abortedAtPath, failedRetryPath)
        XCTAssertEqual(step.status, .failed)
        XCTAssertEqual(step.repeatUntilEvidence?.iterationCount, 2)
        XCTAssertEqual(step.repeatUntilEvidence?.expectation.met, false)
        XCTAssertEqual(
            step.repeatUntilEvidence?.failureReason,
            "iteration 1 failed at \(failedRetryPath)"
        )
        XCTAssertEqual(step.failure?.observed, "iteration 1 failed at \(failedRetryPath)")
        XCTAssertEqual(failedIteration.status, .failed)
        XCTAssertEqual(
            failedIteration.repeatUntilEvidence?.failureReason,
            "child failed at \(failedRetryPath)"
        )
        XCTAssertEqual(failedRetry.status, .failed)
        XCTAssertEqual(failedRetry.actionEvidence?.actionResult?.errorKind, .actionFailed)
    }

    func testHeistRepeatUntilTimeoutWithElseRunsElseBodyWithoutBodyWhenTimeoutIsZero() async throws {
        var incrementCount = 0
        let runtime = heistRuntime(
            observations: [
                observedState(elements: [(makeElement(value: "0", identifier: "quantity"), "quantity")]),
            ],
            execute: { command in
                if case .increment = command {
                    incrementCount += 1
                }
                return ActionResult(success: true, method: .increment, message: command.runtimeType.rawValue)
            }
        )
        let plan = try HeistPlan(body: [
            .repeatUntil(try RepeatUntilStep(
                predicate: .exists(.element(identifier: "quantity", value: "2")),
                timeout: 0,
                body: [
                    .action(try ActionStep(command: .increment(.predicate(.identifier("quantity"))))),
                ],
                elseBody: [
                    .warn(WarnStep(message: "quantity did not reach 2")),
                ]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.success, result.message ?? "repeat_until else failed")
        XCTAssertEqual(incrementCount, 0)
        XCTAssertEqual(step.kind, .repeatUntil)
        XCTAssertEqual(step.repeatUntilEvidence?.iterationCount, 0)
        XCTAssertEqual(step.repeatUntilEvidence?.expectation.met, false)
        XCTAssertEqual(step.children.map(\.kind), [.warn])
    }

    func testHeistIfSelectsMatchingCaseImmediately() async throws {
        let runtime = heistRuntime(observations: [
            observedState(labels: ["Home"]),
        ])
        let plan = try HeistPlan(body: [
            .conditional(try ConditionalStep(cases: [
                PredicateCase(
                    predicate: .exists(.label("Home")),
                    body: [.warn(WarnStep(message: "home flow"))]
                ),
                PredicateCase(
                    predicate: .exists(.label("Settings")),
                    body: [.fail(FailStep(message: "should not run"))]
                ),
            ])),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.success)
        XCTAssertEqual(step.kind, .conditional)
        XCTAssertEqual(step.caseSelectionEvidence?.selection.outcome, HeistCaseSelectionOutcome.matchedCase(index: 0))
        XCTAssertEqual(step.children.map(\.kind), [.warn])
    }

    func testPredicateObservationStreamSeparatesStateAndChangeEvidence() async throws {
        let readyPredicate = ElementPredicate(label: "Ready")
        let source = ScriptedHeistObservationSource(
            observations: [
                observedState(labels: ["Loading"]),
                observedState(labels: ["Loading", "Ready"]),
            ],
            unavailableObservationCount: 0,
            observedScopes: nil,
            observedTimeouts: nil,
            file: #filePath,
            line: #line
        )
        var stream = PredicateObservationStreamState()

        let baselineObservation = try XCTUnwrap(source.next(scope: .visible, timeout: 0))
        let seeded = stream.reducing(
            baselineObservation,
            predicate: .change(.appeared(readyPredicate)),
            baselineSeed: .previousObservationIfAvailable
        )
        stream = seeded.state

        XCTAssertFalse(seeded.reduction.expectation.met)
        XCTAssertEqual(
            seeded.reduction.expectation.actual,
            "change predicate requires future settled observation after baseline"
        )

        let changedObservation = try XCTUnwrap(source.next(scope: .visible, timeout: 0))
        let changed = stream.reducing(
            changedObservation,
            predicate: .change(.appeared(readyPredicate))
        )
        let stateExpectation = PredicateEvaluation.evaluate(
            .exists(readyPredicate),
            in: changed.reduction.evidence
        )

        XCTAssertTrue(stateExpectation.met)
        XCTAssertTrue(changed.reduction.expectation.met)
        XCTAssertEqual(changed.reduction.changeBaseline?.sequence, baselineObservation.event.sequence)
        XCTAssertTrue(changed.reduction.sawObservationAfterBaseline)
    }

    func testHeistIfNoOpsWhenImmediateObservationIsUnavailable() async throws {
        let runtime = heistRuntime(
            observations: [observedState(labels: ["Home"])],
            unavailableObservationCount: 1
        )
        let plan = try HeistPlan(body: [
            .conditional(try ConditionalStep(
                cases: [
                    PredicateCase(
                        predicate: .exists(.label("Home")),
                        body: [.warn(WarnStep(message: "home flow"))]
                    ),
                ]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.success)
        XCTAssertEqual(
            step.caseSelectionEvidence?.selection.outcome,
            HeistCaseSelectionOutcome.elseBranch(reason: .noMatch)
        )
        XCTAssertEqual(step.children.map(\.kind), [])
    }

    func testHeistIfPassesImmediateObservationBudget() async throws {
        var observedTimeouts: [Double?] = []
        let runtime = heistRuntime(
            observations: [observedState(labels: ["Settings"])],
            observedTimeouts: { observedTimeouts.append($0) }
        )
        let plan = try HeistPlan(body: [
            .conditional(try ConditionalStep(
                cases: [
                    PredicateCase(
                        predicate: .exists(.label("Home")),
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
                predicate: .state(.exists(ElementPredicate(label: "Never Appears"))),
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
        XCTAssertDiagnostic(step.reportActionResult?.message, contains: [
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
                predicate: .state(.exists(ElementPredicate(label: "Home"))),
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
            (makeElement(label: "Home"), HeistId(rawValue: "home")),
        ]))
        XCTAssertFalse(inactiveBrains.stash.semanticObservationStream.isActive)

        let result = await inactiveBrains.performWait(target: WaitTarget(
            predicate: .state(.exists(ElementPredicate(label: "Home"))),
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

        let result = await inactiveBrains.executeRuntimeAction(.wait(WaitTarget(
            predicate: .state(.exists(ElementPredicate(label: "Home"))),
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
                predicate: .exists(ElementPredicate(label: "Loaded")),
                timeout: 1
            ))
        }

        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)
        _ = isolatedBrains.stash.semanticObservationStream.commitSettledDiscoveryObservation(beforeScreen)
        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)

        _ = isolatedBrains.stash.semanticObservationStream.commitSettledDiscoveryObservation(matchedScreen)
        let receipt = await receiptTask.value
        let trace = try XCTUnwrap(receipt.actionResult.accessibilityTrace)

        XCTAssertTrue(receipt.actionResult.success)
        XCTAssertEqual(trace.captures.first?.interface.projectedElements.map(\.label), ["Before"])
        XCTAssertEqual(trace.captures.last?.interface.projectedElements.map(\.label), ["Before", "Loaded"])
        guard case .elementsChanged? = trace.endpointDelta else {
            return XCTFail("Expected elementsChanged delta, got \(String(describing: trace.endpointDelta))")
        }
    }

    func testActionExpectationWithMatchingInitialTracePollsForSettledMatch() async throws {
        let isolatedBrains = TheBrains(tripwire: TheTripwire())
        defer { isolatedBrains.stopSemanticObservation() }
        let beforeScreen = Screen.makeForTests(elements: [
            (makeElement(label: "Menu"), "menu"),
        ])
        let firstSettledScreen = Screen.makeForTests(elements: [
            (makeElement(label: "Menu"), "menu"),
            (makeElement(label: "Grid"), "grid"),
        ])
        let catchUpScreen = Screen.makeForTests(elements: [
            (makeElement(label: "Menu"), "menu"),
            (makeElement(label: "Grid"), "grid"),
            (makeElement(label: "Ready"), "ready"),
        ])
        let traceMatchedScreen = catchUpScreen
        let beforeEvent = isolatedBrains.stash.semanticObservationStream.commitSettledDiscoveryObservation(beforeScreen)
        _ = isolatedBrains.stash.semanticObservationStream.commitSettledDiscoveryObservation(firstSettledScreen)
        let before = isolatedBrains.postActionObservation.captureSemanticState(
            from: beforeScreen,
            tripwireSignal: .empty,
            settledObservationSequence: beforeEvent.sequence
        )
        let traceMatched = isolatedBrains.postActionObservation.captureSemanticState(
            from: traceMatchedScreen,
            tripwireSignal: .empty,
            settledObservationSequence: nil
        )
        let initialTrace = AccessibilityTrace(captures: [before.capture, traceMatched.capture])

        let receiptTask = Task { @MainActor in
            await isolatedBrains.interactionObservation.waitForPredicate(
                WaitStep(predicate: .exists(ElementPredicate(label: "Ready")), timeout: 1),
                initialTrace: initialTrace
            )
        }

        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)
        _ = isolatedBrains.stash.semanticObservationStream.commitSettledDiscoveryObservation(firstSettledScreen)
        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)
        _ = isolatedBrains.stash.semanticObservationStream.commitSettledDiscoveryObservation(catchUpScreen)
        let receipt = await receiptTask.value

        XCTAssertTrue(receipt.actionResult.success)
        XCTAssertEqual(receipt.actionResult.accessibilityTrace?.captures.last?.interface.projectedElements.map(\.label), [
            "Menu",
            "Grid",
            "Ready",
        ])
    }

    func testActionExpectationWithMatchingInitialTraceFailsWithoutSettledPollMatch() async throws {
        let isolatedBrains = TheBrains(tripwire: TheTripwire())
        defer { isolatedBrains.stopSemanticObservation() }
        let beforeScreen = Screen.makeForTests(elements: [
            (makeElement(label: "Menu"), "menu"),
        ])
        let firstSettledScreen = Screen.makeForTests(elements: [
            (makeElement(label: "Menu"), "menu"),
            (makeElement(label: "Grid"), "grid"),
        ])
        let traceMatchedScreen = Screen.makeForTests(elements: [
            (makeElement(label: "Menu"), "menu"),
            (makeElement(label: "Grid"), "grid"),
            (makeElement(label: "Ready"), "ready"),
        ])
        let beforeEvent = isolatedBrains.stash.semanticObservationStream.commitSettledDiscoveryObservation(beforeScreen)
        _ = isolatedBrains.stash.semanticObservationStream.commitSettledDiscoveryObservation(firstSettledScreen)
        let before = isolatedBrains.postActionObservation.captureSemanticState(
            from: beforeScreen,
            tripwireSignal: .empty,
            settledObservationSequence: beforeEvent.sequence
        )
        let traceMatched = isolatedBrains.postActionObservation.captureSemanticState(
            from: traceMatchedScreen,
            tripwireSignal: .empty,
            settledObservationSequence: nil
        )
        let initialTrace = AccessibilityTrace(captures: [before.capture, traceMatched.capture])

        let receiptTask = Task { @MainActor in
            await isolatedBrains.interactionObservation.waitForPredicate(
                WaitStep(predicate: .exists(ElementPredicate(label: "Ready")), timeout: 0.05),
                initialTrace: initialTrace
            )
        }

        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)
        _ = isolatedBrains.stash.semanticObservationStream.commitSettledDiscoveryObservation(firstSettledScreen)
        let receipt = await receiptTask.value

        XCTAssertFalse(receipt.actionResult.success)
        XCTAssertEqual(receipt.actionResult.errorKind, .timeout)
        XCTAssertEqual(receipt.expectation.actual, "no element matches predicate(label=\"Ready\")")
    }

    func testChangedActionExpectationUsesPreActionBaselineForSettledActionResult() async throws {
        let isolatedBrains = TheBrains(tripwire: TheTripwire())
        defer { isolatedBrains.stopSemanticObservation() }
        let beforeScreen = Screen.makeForTests(elements: [
            (makeElement(label: "Menu", traits: .header), "menu_header"),
        ])
        let afterScreen = Screen.makeForTests(elements: [
            (makeElement(label: "Controls Demo", traits: .header), "controls_demo_header"),
        ])
        let beforeEvent = isolatedBrains.stash.semanticObservationStream.commitSettledVisibleObservation(beforeScreen)
        let afterEvent = isolatedBrains.stash.semanticObservationStream.commitSettledVisibleObservation(afterScreen)
        let before = isolatedBrains.postActionObservation.captureSemanticState(
            from: beforeScreen,
            tripwireSignal: .empty,
            settledObservationSequence: beforeEvent.sequence
        )
        let after = isolatedBrains.postActionObservation.captureSemanticState(
            from: afterScreen,
            tripwireSignal: .empty,
            settledObservationSequence: afterEvent.sequence
        )
        let detachedBeforeCapture = AccessibilityTrace.Capture(
            sequence: before.capture.sequence,
            interface: before.capture.interface,
            parentHash: before.capture.parentHash,
            context: AccessibilityTrace.Context(
                keyboardVisible: !(before.capture.context.keyboardVisible ?? false),
                screenId: before.capture.context.screenId,
                windowStack: before.capture.context.windowStack
            ),
            transition: before.capture.transition
        )
        let initialTrace = AccessibilityTrace(captures: [detachedBeforeCapture, after.capture])

        XCTAssertNotEqual(initialTrace.captures.first?.hash, afterEvent.trace.captures.first?.hash)

        let receipt = await isolatedBrains.interactionObservation.waitForPredicate(
            WaitStep(
                predicate: .change(.screen(.exists(ElementPredicate(label: "Controls Demo", traits: [.header])))),
                timeout: 1
            ),
            initialTrace: initialTrace
        )

        XCTAssertTrue(receipt.actionResult.success)
        guard case .screenChanged? = receipt.actionResult.accessibilityTrace?.endpointDelta else {
            return XCTFail("Expected screenChanged delta, got \(String(describing: receipt.actionResult.accessibilityTrace?.endpointDelta))")
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
                predicate: .exists(ElementPredicate(label: "Missing")),
                timeout: 0.05
            ))
        }
        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)
        _ = isolatedBrains.stash.semanticObservationStream.commitSettledDiscoveryObservation(beforeScreen)

        let receipt = await receiptTask.value

        XCTAssertFalse(receipt.actionResult.success)
        XCTAssertEqual(receipt.actionResult.errorKind, .timeout)
        XCTAssertTrue(receipt.actionResult.message?.contains("known: 1 elements") == true)
        XCTAssertTrue(receipt.actionResult.message?.contains("last result:") == true)
    }

    func testHeistActionExpectationRequiresWaitObservationEvidence() async throws {
        let expectation = WaitStep(
            predicate: .state(.missing(ElementPredicate(label: "Loading"))),
            timeout: 0
        )
        var waitRequests: [TheBrains.HeistRuntimeWaitRequest] = []
        let runtime = heistRuntime(
            observations: [],
            execute: { _ in
                ActionResult(success: true, method: .activate)
            },
            wait: { request in
                waitRequests.append(request)
                return ActionResult(success: true, method: .wait)
            }
        )
        let plan = try HeistPlan(body: [
            .action(try ActionStep(
                command: .activate(.predicate(ElementPredicateTemplate(label: .exact(.literal("Submit"))))),
                expectation: expectation
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertFalse(result.success)
        XCTAssertEqual(waitRequests.count, 1)
        if case .actionEndpoint(let request, trace: nil)? = waitRequests.first {
            XCTAssertEqual(request, try expectation.resolve(in: .empty))
        } else {
            XCTFail("Expected action endpoint wait request")
        }
        XCTAssertEqual(step.actionEvidence?.expectationActionResult?.method, .wait)
        XCTAssertEqual(step.reportExpectation?.met, false)
        XCTAssertEqual(step.reportExpectation?.actual, "no observed accessibility trace")
    }

    func testActionExpectationSettlesWithDiscoveryScope() async throws {
        let observedReady = observedState(labels: ["Long List"])
        let target = ElementTarget.predicate(ElementPredicate(identifier: "target"))
        var observedScopes: [SemanticObservationScope] = []
        let runtime = heistRuntime(
            observations: [observedReady],
            execute: { _ in
                ActionResult(success: true, method: .activate)
            },
            observedScopes: { scope in
                observedScopes.append(scope)
            }
        )
        let plan = try HeistPlan(body: [
            .action(try ActionStep(
                command: .activate(.target(target)),
                expectation: WaitStep(
                    predicate: .exists(ElementPredicate(label: "Long List")),
                    timeout: 0.01
                )
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertTrue(result.success, result.message ?? "heist failed")
        XCTAssertEqual(observedScopes, [.discovery])
    }

    func testHeistRuntimeSafetyRejectsInvalidPlanBeforeDispatchOrObservation() async throws {
        let raw = HeistPlanAdmissionCandidate(body: [
            .action(try ActionStep(command: .activate(.ref("missing")))),
        ])

        XCTAssertThrowsError(try raw.validatedForRuntimeSafety()) { error in
            XCTAssertTrue(String(describing: error).contains("$.body[0].action.command.payload.target"))
            XCTAssertTrue(String(describing: error).contains("target_ref must resolve"))
        }
    }

    func testHeistRuntimeSafetyRejectsInvalidStringLoopBeforeDispatch() async throws {
        let raw = HeistPlanAdmissionCandidate(body: [
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

        XCTAssertThrowsError(try raw.validatedForRuntimeSafety()) { error in
            XCTAssertTrue(String(describing: error).contains("text must be non-empty"))
        }
    }

    func testHeistRuntimeSafetyRejectsOversizedForEachBeforeObservation() async throws {
        let raw = HeistPlanAdmissionCandidate(body: [
            .forEachElement(try ForEachElementStep(
                matching: .label("Delete"),
                limit: HeistPlanRuntimeSafetyLimits.standard.maxForEachElementLimit + 1,
                parameter: "target",
                body: [.action(try ActionStep(command: .activate(.ref("target"))))]
            )),
        ])

        XCTAssertThrowsError(try raw.validatedForRuntimeSafety()) { error in
            XCTAssertTrue(String(describing: error).contains("max for_each_element limit"))
        }
    }

    func testHeistInvocationExecutesHelperDependenciesInInvokedDefinitionScope() async throws {
        var executedCommands: [RuntimeActionMessage] = []
        let runtime = heistRuntime(
            observations: [],
            execute: { command in
                executedCommands.append(command)
                return ActionResult(success: true, method: .activate)
            }
        )
        let plan = try HeistPlanAdmissionCandidate(definitions: [
            HeistPlanAdmissionCandidate(
                name: "addToCart",
                parameter: .string(name: "item"),
                definitions: [
                    HeistPlanAdmissionCandidate(name: "tapAddButton", body: [
                        .action(try ActionStep(
                            command: .activate(.predicate(ElementPredicateTemplate(label: .exact(.literal("Add to Cart")))))
                        )),
                    ]),
                ],
                body: [
                    .action(try ActionStep(command: .activate(.predicate(ElementPredicateTemplate(label: .exact(.ref("item"))))))),
                    .invoke(HeistInvocationStep(path: ["tapAddButton"])),
                ]
            ),
        ], body: [
            .invoke(HeistInvocationStep(
                path: ["addToCart"],
                argument: .string(.literal("Milk"))
            )),
        ]).validatedForRuntimeSafety()

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertTrue(result.success)
        XCTAssertEqual(executedCommands, [
            .activate(.predicate(ElementPredicate(label: "Milk"))),
            .activate(.predicate(ElementPredicate(label: "Add to Cart"))),
        ])
    }

    func testHeistInvocationExpectationReturnsEvidenceOnInvokeNode() async throws {
        var executedCommands: [RuntimeActionMessage] = []
        let expectation = WaitStep(
            predicate: .change(.elements(.appearedElement(.label("subtotal")))),
            timeout: defaultActionExpectationTimeout
        )
        let runtime = heistRuntime(
            observations: [
                observedState(labels: ["Search"]),
                observedState(labels: ["Search", "subtotal"]),
            ],
            execute: { command in
                executedCommands.append(command)
                return ActionResult(success: true, method: .activate)
            }
        )
        let plan = try HeistPlan(
            definitions: [
                try HeistPlan(
                    name: "Cart",
                    definitions: [
                        try HeistPlan(
                            name: "addItem",
                            parameter: .string(name: "item"),
                            body: [
                                .action(try ActionStep(command: .activate(.predicate(.label(.ref("item")))))),
                            ]
                        ),
                    ],
                    body: []
                ),
            ],
            body: [
                .invoke(HeistInvocationStep(
                    path: ["Cart", "addItem"],
                    argument: .string(.literal("Milk")),
                    expectation: expectation
                )),
            ]
        )

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.success)
        XCTAssertEqual(executedCommands, [
            .activate(.predicate(ElementPredicate(label: "Milk"))),
        ])
        XCTAssertEqual(heist.expectationsChecked, 1)
        XCTAssertEqual(heist.expectationsMet, 1)
        XCTAssertEqual(step.kind, .invoke)
        XCTAssertEqual(step.invocationEvidence?.expectationActionResult?.method, .wait)
        XCTAssertEqual(step.invocationEvidence?.expectationActionResult?.success, true)
        XCTAssertEqual(step.invocationEvidence?.expectation?.met, true)
        XCTAssertEqual(step.reportExpectation?.met, true)
    }

    func testHeistInvocationSnapshotExpectationEvaluatesFinalNestedState() async throws {
        let runtime = heistRuntime(
            observations: [
                observedState(labels: ["Checkout"]),
                observedState(labels: ["Payment Complete"]),
            ],
            execute: { _ in
                ActionResult(success: true, method: .activate)
            }
        )
        let plan = try HeistPlan(
            definitions: [
                try HeistPlan(name: "Checkout", definitions: [
                    try HeistPlan(name: "pay", body: [
                        .action(try ActionStep(command: .activate(.predicate(.label("Pay"))))),
                    ]),
                ], body: []),
            ],
            body: [
                .invoke(HeistInvocationStep(
                    path: ["Checkout", "pay"],
                    expectation: WaitStep(
                        predicate: .exists(.label("Payment Complete")),
                        timeout: defaultActionExpectationTimeout
                    )
                )),
            ]
        )

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.success)
        XCTAssertEqual(step.kind, .invoke)
        XCTAssertEqual(step.invocationEvidence?.expectation?.met, true)
        XCTAssertEqual(step.invocationEvidence?.expectationActionResult?.success, true)
        XCTAssertEqual(step.children.count, 1)
    }

    func testHeistInvocationTransitionExpectationEvaluatesAcrossNestedCall() async throws {
        let runtime = heistRuntime(
            observations: [
                observedState(elements: [
                    (makeElement(label: "subtotal", value: "1 item", identifier: "subtotal"), "subtotal"),
                ]),
                observedState(elements: [
                    (makeElement(label: "subtotal", value: "2 items", identifier: "subtotal"), "subtotal"),
                ]),
            ],
            execute: { _ in
                ActionResult(success: true, method: .activate)
            }
        )
        let plan = try HeistPlan(
            definitions: [
                try HeistPlan(name: "Cart", definitions: [
                    try HeistPlan(
                        name: "addItem",
                        parameter: .string(name: "item"),
                        body: [
                            .action(try ActionStep(command: .activate(.predicate(.label(.ref("item")))))),
                        ]
                    ),
                ], body: []),
            ],
            body: [
                .invoke(HeistInvocationStep(
                    path: ["Cart", "addItem"],
                    argument: .string(.literal("Eggs")),
                    expectation: WaitStep(
                        predicate: .change(.elements(.updatedElement(ElementUpdatePredicateExpr(
                            element: .label("subtotal"),
                            change: .value(after: .contains("2 items"))
                        )))),
                        timeout: defaultActionExpectationTimeout
                    )
                )),
            ]
        )

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.success)
        XCTAssertEqual(step.kind, .invoke)
        XCTAssertEqual(step.invocationEvidence?.expectation?.met, true)
        XCTAssertEqual(step.invocationEvidence?.expectationActionResult?.success, true)
    }

    func testHeistInvocationScreenChangeExpectationEvaluatesAcrossNestedCall() async throws {
        let runtime = heistRuntime(
            observations: [
                observedState(labels: ["Checkout"], screenId: "checkout"),
                observedState(labels: ["Receipt"], screenId: "receipt"),
            ],
            execute: { _ in
                ActionResult(success: true, method: .activate)
            }
        )
        let plan = try HeistPlan(
            definitions: [
                try HeistPlan(name: "Checkout", definitions: [
                    try HeistPlan(name: "pay", body: [
                        .action(try ActionStep(command: .activate(.predicate(.label("Pay"))))),
                    ]),
                ], body: []),
            ],
            body: [
                .invoke(HeistInvocationStep(
                    path: ["Checkout", "pay"],
                    expectation: WaitStep(
                        predicate: .change(.screen(.exists(.label("Receipt")))),
                        timeout: defaultActionExpectationTimeout
                    )
                )),
            ]
        )

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.success)
        XCTAssertEqual(step.kind, .invoke)
        XCTAssertEqual(step.invocationEvidence?.expectation?.met, true)
        XCTAssertEqual(step.invocationEvidence?.expectationActionResult?.success, true)
    }

    func testHeistInvocationAttachedExpectationFailureStaysOnInvokeNode() async throws {
        let runtime = heistRuntime(
            observations: [
                observedState(elements: [
                    (makeElement(label: "subtotal", value: "1 item", identifier: "subtotal"), "subtotal"),
                ]),
                observedState(elements: [
                    (makeElement(label: "subtotal", value: "1 item", identifier: "subtotal"), "subtotal"),
                ]),
            ],
            execute: { _ in
                ActionResult(success: true, method: .activate)
            }
        )
        let plan = try HeistPlan(
            definitions: [
                try HeistPlan(name: "Cart", definitions: [
                    try HeistPlan(
                        name: "addItem",
                        parameter: .string(name: "item"),
                        body: [
                            .action(try ActionStep(command: .activate(.predicate(.label(.ref("item")))))),
                        ]
                    ),
                ], body: []),
            ],
            body: [
                .invoke(HeistInvocationStep(
                    path: ["Cart", "addItem"],
                    argument: .string(.literal("Eggs")),
                    expectation: WaitStep(
                        predicate: .change(.elements(.updatedElement(ElementUpdatePredicateExpr(
                            element: .label("subtotal"),
                            change: .value(after: .contains("2 items"))
                        )))),
                        timeout: defaultActionExpectationTimeout
                    )
                )),
            ]
        )

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertFalse(result.success)
        XCTAssertEqual(heist.abortedAtPath, "$.body[0]")
        XCTAssertEqual(step.kind, .invoke)
        XCTAssertEqual(step.status, .failed)
        XCTAssertNil(step.abortedAtChildPath)
        XCTAssertEqual(step.failure?.category, .expectation)
        XCTAssertEqual(step.invocationEvidence?.expectation?.met, false)
        XCTAssertEqual(step.invocationEvidence?.expectationActionResult?.success, false)
        XCTAssertTrue(step.children.allSatisfy { $0.status == .passed })
    }

    func testHeistInvocationExecutesQualifiedExportedNamespaceDependency() async throws {
        var executedCommands: [RuntimeActionMessage] = []
        let runtime = heistRuntime(
            observations: [],
            execute: { command in
                executedCommands.append(command)
                return ActionResult(success: true, method: .activate)
            }
        )
        let plan = try HeistPlanAdmissionCandidate(definitions: [
            HeistPlanAdmissionCandidate(name: "lib", definitions: [
                HeistPlanAdmissionCandidate(name: "payOpen", body: [
                    .action(try ActionStep(command: .activate(.predicate(.label("Pay"))))),
                ]),
                HeistPlanAdmissionCandidate(name: "checkout", body: [
                    .invoke(HeistInvocationStep(path: ["lib", "payOpen"])),
                ]),
            ], body: []),
        ], body: [
            .invoke(HeistInvocationStep(path: ["lib", "checkout"])),
        ]).validatedForRuntimeSafety()

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertTrue(result.success)
        XCTAssertEqual(executedCommands, [
            .activate(.predicate(ElementPredicate(label: "Pay"))),
        ])
    }

    func testHeistExecutionBindsRootStringArgument() async throws {
        var executedCommands: [RuntimeActionMessage] = []
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
        var executedCommands: [RuntimeActionMessage] = []
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
        var executedCommands: [RuntimeActionMessage] = []
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
        let plan = HeistPlan(runtimeValidatedVersion: HeistPlan.currentVersion, definitions: [
            HeistPlan(runtimeValidatedVersion: HeistPlan.currentVersion, name: recursiveName, body: [
                .invoke(HeistInvocationStep(path: [recursiveName])),
            ]),
        ], body: [])

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
        XCTAssertEqual(recursive.failure?.observed, "unknown heist run \(recursiveName)")
    }

    func testHeistActionExpectationTimeoutZeroUsesActionInteractionTrace() async throws {
        let expectation = WaitStep(predicate: .change(.screen()), timeout: 0)
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
                command: .activate(.predicate(ElementPredicateTemplate(label: .exact(.literal("Controls Demo"))))),
                expectation: expectation
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.success)
        XCTAssertEqual(step.actionEvidence?.expectationActionResult?.method, .wait)
        XCTAssertTrue(step.actionEvidence?.expectationActionResult?.success == true)
        XCTAssertEqual(step.actionEvidence?.expectationActionResult?.accessibilityTrace, trace)
        XCTAssertEqual(step.reportExpectation?.met, true)
        XCTAssertEqual(step.reportExpectation?.actual, "screenChanged")
    }

    func testHeistActionExpectationUsesWaitFailureDiagnostic() async throws {
        let expectation = WaitStep(
            predicate: .missing(ElementPredicate(label: "Loading")),
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
        let plan = try HeistPlan(body: [
            .action(try ActionStep(
                command: .activate(.predicate(ElementPredicateTemplate(label: .exact(.literal("Submit"))))),
                expectation: expectation
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertFalse(result.success)
        XCTAssertEqual(step.actionEvidence?.expectationActionResult?.errorKind, .timeout)
        XCTAssertEqual(step.reportExpectation?.met, false)
        XCTAssertEqual(step.reportExpectation?.actual, "timed out after 0.2s — expectation not met")
    }

    func testHeistSemanticObservationScopeUsesVisibleForPredicateSugarCases() async throws {
        var observedScopes: [SemanticObservationScope] = []
        let runtime = heistRuntime(
            observations: [observedState(labels: ["Home"])],
            observedScopes: { observedScopes.append($0) }
        )
        let plan = try HeistPlan(body: [
            .conditional(try ConditionalStep(cases: [
                PredicateCase(
                    predicate: .exists(.label("Home")),
                    body: [.warn(WarnStep(message: "home"))]
                ),
                PredicateCase(
                    predicate: .missing(.label("Login")),
                    body: [.warn(WarnStep(message: "not login"))]
                ),
            ])),
        ])

        _ = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertEqual(observedScopes, [.visible])
    }

    func testHeistSemanticObservationScopeUsesVisibleForStateCases() async throws {
        var observedScopes: [SemanticObservationScope] = []
        let runtime = heistRuntime(
            observations: [observedState(labels: ["Loading"])],
            observedScopes: { observedScopes.append($0) }
        )
        let plan = try HeistPlan(body: [
            .conditional(try ConditionalStep(
                cases: [
                    PredicateCase(
                        predicate: .exists(.label("Toast")),
                        body: [.warn(WarnStep(message: "toast"))]
                    ),
                ],
                elseBody: [.warn(WarnStep(message: "no toast"))]
            )),
        ])

        _ = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertEqual(observedScopes, [.visible])
    }

    func testHeistSemanticObservationScopeKeepsStateCasesVisible() async throws {
        var observedScopes: [SemanticObservationScope] = []
        let runtime = heistRuntime(
            observations: [observedState(labels: ["Loading"])],
            observedScopes: { observedScopes.append($0) }
        )
        let plan = try HeistPlan(body: [
            .conditional(try ConditionalStep(
                cases: [
                    PredicateCase(
                        predicate: .exists(.label("Home")),
                        body: [.warn(WarnStep(message: "home"))]
                    ),
                    PredicateCase(
                        predicate: .exists(.label("Toast")),
                        body: [.warn(WarnStep(message: "toast"))]
                    ),
                ],
                elseBody: [.warn(WarnStep(message: "unknown"))]
            )),
        ])

        _ = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertEqual(observedScopes, [.visible])
    }

    func testHeistKeepsActiveObservationDemandThroughStateDependentStep() async throws {
        var demandDuringAction = false
        var demandDuringObservation = false
        let runtime = heistRuntime(
            observations: [observedState(labels: ["Ready"])],
            execute: { _ in
                demandDuringAction = self.brains.stash.semanticObservationStream.hasActiveObservationDemand
                return ActionResult(success: true, method: .activate)
            },
            observedScopes: { _ in
                demandDuringObservation = self.brains.stash.semanticObservationStream.hasActiveObservationDemand
            }
        )
        let plan = try HeistPlan(body: [
            .action(try ActionStep(command: .activate(.predicate(ElementPredicateTemplate(label: .exact(.literal("Submit"))))))),
            .conditional(try ConditionalStep(cases: [
                PredicateCase(
                    predicate: .exists(.label("Ready")),
                    body: [.warn(WarnStep(message: "ready"))]
                ),
            ])),
        ])

        _ = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertTrue(demandDuringAction)
        XCTAssertTrue(demandDuringObservation)
        XCTAssertFalse(brains.stash.semanticObservationStream.hasActiveObservationDemand)
    }

    func testHeistKeepsActiveObservationDemandAcrossConsecutiveBareActions() async throws {
        var demandDuringActions: [Bool] = []
        let runtime = heistRuntime(
            observations: [],
            execute: { _ in
                demandDuringActions.append(self.brains.stash.semanticObservationStream.hasActiveObservationDemand)
                return ActionResult(success: true, method: .activate)
            }
        )
        let plan = try HeistPlan(body: [
            .action(try ActionStep(command: .activate(.predicate(ElementPredicateTemplate(label: .exact(.literal("1"))))))),
            .action(try ActionStep(command: .activate(.predicate(ElementPredicateTemplate(label: .exact(.literal("2"))))))),
            .action(try ActionStep(command: .activate(.predicate(ElementPredicateTemplate(label: .exact(.literal("3"))))))),
        ])

        _ = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertEqual(demandDuringActions, [true, true, true])
        XCTAssertFalse(brains.stash.semanticObservationStream.hasActiveObservationDemand)
    }

    func testIfStatePredicateDoesNotWaitForFutureObservation() async throws {
        let runtime = heistRuntime(observations: [
            observedState(labels: ["Loading"]),
            observedState(labels: ["Loading", "Toast"]),
        ])
        let plan = try HeistPlan(body: [
            .conditional(try ConditionalStep(
                cases: [
                    PredicateCase(
                        predicate: .exists(.label("Toast")),
                        body: [.warn(WarnStep(message: "toast"))]
                    ),
                ]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.success)
        XCTAssertEqual(
            step.caseSelectionEvidence?.selection.outcome,
            HeistCaseSelectionOutcome.elseBranch(reason: .noMatch)
        )
        XCTAssertEqual(step.caseSelectionEvidence?.selection.cases.first?.result.met, false)
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
        XCTAssertEqual(step.status, .passed)
        XCTAssertEqual(forEachResult.matchedCount, 0)
        XCTAssertEqual(forEachResult.limit, 20)
        XCTAssertEqual(forEachResult.iterationCount, 0)
        XCTAssertNil(forEachResult.failureReason)
        XCTAssertNil(step.failure)
        XCTAssertTrue(step.children.isEmpty)
        XCTAssertEqual(observedScopes, [.discovery])
    }

    func testHeistForEachStringChildFailureProducesExplicitLoopFailureOutcome() async throws {
        let runtime = heistRuntime(observations: [])
        let plan = try HeistPlan(body: [
            .forEachString(try ForEachStringStep(
                values: ["milk", "eggs"],
                parameter: "item",
                body: [.fail(FailStep(message: "stop loop"))]
            )),
            .warn(WarnStep(message: "should not run")),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let forEachStep = try XCTUnwrap(heist.steps.first)
        let forEachResult = try XCTUnwrap(forEachStep.forEachStringEvidence)
        let failedChildPath = "$.body[0].for_each_string.iterations[0].body[0]"

        XCTAssertFalse(result.success)
        XCTAssertEqual(heist.abortedAtPath, failedChildPath)
        XCTAssertEqual(heist.steps.map(\.kind), [.forEachString, .warn])
        XCTAssertEqual(heist.steps.map(\.status), [.failed, .skipped])
        XCTAssertEqual(forEachStep.status, .failed)
        XCTAssertEqual(forEachResult.count, 2)
        XCTAssertEqual(forEachResult.iterationCount, 1)
        XCTAssertEqual(
            forEachResult.failureReason,
            "iteration 0 failed for value \"milk\" at \(failedChildPath)"
        )
        XCTAssertEqual(
            forEachStep.failure?.observed,
            "iteration 0 failed for value \"milk\" at \(failedChildPath)"
        )
        XCTAssertEqual(forEachStep.abortedAtChildPath, failedChildPath)
        XCTAssertEqual(
            forEachStep.children.first?.forEachStringEvidence?.failureReason,
            "child failed at \(failedChildPath)"
        )
    }

    func testHeistForEachFailsBeforeMutationWhenMatchCountExceedsLimit() async throws {
        let matching = ElementPredicate(label: "Delete")
        var executedCommands: [RuntimeActionMessage] = []
        let runtime = heistRuntime(
            observations: [
                observedState(elements: [
                    (makeElement(label: "Delete", identifier: "delete_first"), "delete_first"),
                    (makeElement(label: "Delete", identifier: "delete_second"), "delete_second"),
                ]),
            ],
            execute: { command in
                executedCommands.append(command)
                if case .takeScreenshot = command {
                    return ActionResult(success: true, method: .takeScreenshot)
                }
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
        XCTAssertEqual(executedCommands, [.takeScreenshot])
        XCTAssertEqual(forEachResult.matchedCount, 2)
        XCTAssertEqual(forEachResult.limit, 1)
        XCTAssertEqual(forEachResult.iterationCount, 0)
        XCTAssertEqual(forEachResult.failureReason, "matched 2 element(s), exceeding for_each_element limit 1")
        XCTAssertTrue(step.children.isEmpty)
        XCTAssertEqual(heist.steps.map(\.path), ["$.body[0]", "$.body[0].failure.actions[0]"])
        XCTAssertEqual(heist.failureScreenshotStep?.actionEvidence?.command, .takeScreenshot)
    }

    func testHeistForEachCallsBodyWithOrdinalTargetForEachInitialMatchWithoutMutatingPlan() async throws {
        let matching = ElementPredicate(label: "Delete")
        var executedCommands: [RuntimeActionMessage] = []
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
        var executedCommands: [RuntimeActionMessage] = []
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
        var executedCommands: [RuntimeActionMessage] = []
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
        var executedCommands: [RuntimeActionMessage] = []
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
        var executedCommands: [RuntimeActionMessage] = []
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
        XCTAssertEqual(heist.steps.map(\.kind), [.forEachElement, .warn])
        XCTAssertEqual(heist.steps.map(\.status), [.failed, .skipped])
        XCTAssertEqual(forEachStep.status, .failed)
        XCTAssertEqual(forEachResult.matchedCount, 2)
        XCTAssertEqual(forEachResult.iterationCount, 1)
        XCTAssertEqual(forEachResult.failureReason, "iteration 0 failed at \(failedActionPath)")
        XCTAssertEqual(forEachStep.failure?.observed, "iteration 0 failed at \(failedActionPath)")
        XCTAssertEqual(forEachStep.abortedAtChildPath, failedActionPath)
        XCTAssertEqual(forEachStep.children.map(\.kind), [.forEachIteration])
        XCTAssertEqual(forEachStep.children.first?.children.map(\.kind), [.action])
        XCTAssertEqual(
            forEachStep.children.first?.forEachElementEvidence?.failureReason,
            "child failed at \(failedActionPath)"
        )
    }

    func testHeistForEachExpectationUsesCurrentSemanticTarget() async throws {
        let matching = ElementPredicate(label: "Delete")
        var executedCommands: [RuntimeActionMessage] = []
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
            wait: { request in
                waitedSteps.append(request.step)
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
                            predicate: .state(.missingTarget(.ref("target"))),
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
        XCTAssertEqual(waitedSteps.first?.predicate, .state(.missingTarget(.predicate(matching, ordinal: 0))))
        XCTAssertEqual(executedCommands.last, .activate(.predicate(matching, ordinal: 0)))
        XCTAssertEqual(waitedSteps.last?.predicate, .state(.missingTarget(.predicate(matching, ordinal: 0))))
    }

    func testElementActionFailsWhenSemanticTargetHasNoLiveGeometry() async {
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
            elements: [(staleElement, HeistId(rawValue: "stale_refreshed_slider"))],
            objects: [HeistId(rawValue: "stale_refreshed_slider"): nil]
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

    func testExecuteActivateRefreshesBeforeSingleActivationAttempt() async throws {
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

        let staleObject = RefusingActivationView()
        registerScreenElement(
            heistId: "stale_refresh_activate",
            element: makeElement(
                label: "Refresh Activate",
                identifier: "refresh_activate",
                traits: .button
            ),
            object: staleObject
        )

        let result = await brains.actions.executeActivate(
            .predicate(ElementPredicate(identifier: "refresh_activate"))
        )

        XCTAssertTrue(result.success, result.message ?? "activate failed")
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(liveObject.activationCount, 1)
        XCTAssertEqual(staleObject.activationCount, 0)
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
            stash.invalidateSettledObservationFromTripwire()
        }
        brains.safecracker.keyboardBridgeProvider = { keyboardImpl.bridge() }
        await brains.tripwire.yieldFrames(3)

        let result = await brains.executeRuntimeAction(.typeText(TypeTextTarget(
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

    func testExecuteTypeTextReplacingExistingReportsReplacementValueFromInteractionAfterState() async throws {
        brains.tripwire.startPulse()
        let rootView = UIView(frame: UIScreen.main.bounds)
        rootView.backgroundColor = .white

        let textField = UITextField(frame: CGRect(x: 48, y: 180, width: 240, height: 44))
        textField.borderStyle = .roundedRect
        textField.text = "a"
        textField.isAccessibilityElement = true
        textField.accessibilityLabel = "Message"
        textField.accessibilityIdentifier = "message_field"
        textField.accessibilityValue = "a"
        rootView.addSubview(textField)

        let window = try installModalWindow(rootView: rootView)
        defer {
            brains.stopSemanticObservation()
            brains.tripwire.stopPulse()
            window.rootViewController?.view.accessibilityViewIsModal = false
            window.isHidden = true
        }

        let keyboardImpl = ActionTextInputKeyboardImpl(textField: textField) { [stash = brains.stash] in
            stash.invalidateSettledObservationFromTripwire()
        }
        brains.safecracker.keyboardBridgeProvider = { keyboardImpl.bridge() }
        await brains.tripwire.yieldFrames(3)

        let result = await brains.executeRuntimeAction(.typeText(TypeTextTarget(
            text: "b",
            elementTarget: .predicate(ElementPredicate(identifier: "message_field")),
            replacingExisting: true
        )))

        XCTAssertTrue(result.success, result.message ?? "type_text replacement failed")
        XCTAssertEqual(result.method, .typeText)
        XCTAssertEqual(textField.text, "b")
        guard case .value(let value) = result.payload else {
            XCTFail("Expected final text value payload, got \(String(describing: result.payload))")
            return
        }
        XCTAssertEqual(value, "b")
    }

    func testExecuteTypeTextReplacingExistingWithEmptyTextClearsField() async throws {
        brains.tripwire.startPulse()
        let rootView = UIView(frame: UIScreen.main.bounds)
        rootView.backgroundColor = .white

        let textField = UITextField(frame: CGRect(x: 48, y: 180, width: 240, height: 44))
        textField.borderStyle = .roundedRect
        textField.text = "abc"
        textField.isAccessibilityElement = true
        textField.accessibilityLabel = "Message"
        textField.accessibilityIdentifier = "message_field"
        textField.accessibilityValue = "abc"
        rootView.addSubview(textField)

        let window = try installModalWindow(rootView: rootView)
        defer {
            brains.stopSemanticObservation()
            brains.tripwire.stopPulse()
            window.rootViewController?.view.accessibilityViewIsModal = false
            window.isHidden = true
        }

        let keyboardImpl = ActionTextInputKeyboardImpl(textField: textField) { [stash = brains.stash] in
            stash.invalidateSettledObservationFromTripwire()
        }
        brains.safecracker.keyboardBridgeProvider = { keyboardImpl.bridge() }
        await brains.tripwire.yieldFrames(3)

        let result = await brains.executeRuntimeAction(.typeText(TypeTextTarget(
            text: "",
            elementTarget: .predicate(ElementPredicate(identifier: "message_field")),
            replacingExisting: true
        )))

        XCTAssertTrue(result.success, result.message ?? "type_text clear failed")
        XCTAssertEqual(result.method, .typeText)
        XCTAssertEqual(textField.text, "")
        guard case .value(let value) = result.payload else {
            XCTFail("Expected final text value payload, got \(String(describing: result.payload))")
            return
        }
        XCTAssertEqual(value, "")
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
            "no scroll membership",
        ])
    }

    func testElementTargetedPointActionUsesAccessibilityCaptureActivationPoint() async {
        let capturePoint = CGPoint(x: 10, y: 20)
        let objectPoint = CGPoint(x: 123, y: 456)
        let heistId: HeistId = "live_button"
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

    func testElementUnitPointActionUsesElementFrameOverride() async {
        let frame = CGRect(x: 100, y: 200, width: 80, height: 40)
        let activationPoint = CGPoint(x: 140, y: 220)
        let element = AccessibilityElement.make(
            label: "Live",
            traits: .button,
            shape: .frame(AccessibilityRect(frame)),
            activationPoint: activationPoint
        )
        let liveObject = ActionGeometryView(activationPoint: activationPoint)
        liveObject.accessibilityFrame = frame
        installScreen(elements: [(element, "live_button")], objects: ["live_button": liveObject])

        var dispatchedPoint: CGPoint?
        let result = await brains.actions.performPointAction(
            selection: .elementUnitPoint(
                .predicate(ElementPredicate(label: "Live")),
                UnitPoint(x: 0.25, y: 0.75)
            ),
            method: .syntheticTap
        ) { point in
            dispatchedPoint = point
            return true
        }

        XCTAssertTrue(result.success)
        XCTAssertEqual(dispatchedPoint, CGPoint(x: 120, y: 230))
        XCTAssertNotEqual(dispatchedPoint, activationPoint)
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
                duration: GestureDuration(seconds: 0.01)
            )
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .syntheticDrag)
        XCTAssertEqual(result.failureKind, .inputValidation)
        XCTAssertEqual(result.message, "syntheticDrag failed: endPoint must contain finite coordinates")
    }

    func testExecuteRotorWithoutCustomRotorsReportsNextStep() async {
        let heistId: HeistId = "plain_rotor_host"
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
        XCTAssertEqual(result.method.rawValue, ActionMethod.rotor.rawValue)
        XCTAssertDiagnostic(result.message, contains: [
            "rotor failed",
            "attempted rotor=\"Errors\" direction=next",
            "availableRotors=[]",
            "observed customRotors=[]",
            "try target an element exposing custom rotors",
        ])
    }

    func testExecuteRotorDispatchesLiveRotorAction() async {
        let heistId: HeistId = "live_rotor_host"
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
        XCTAssertEqual(result.method.rawValue, ActionMethod.rotor.rawValue)
        XCTAssertTrue(result.message?.contains("Rotor 'Live Rotor' found Rotor host") ?? false,
                      result.message ?? "missing rotor success message")
    }

    func testExecuteRotorUsesOnscreenAccessibilityGeometryAtViewportEdge() async {
        let heistId: HeistId = "edge_rotor_host"
        let frame = CGRect(x: 20, y: -20, width: 180, height: 44)
        let element = AccessibilityElement.make(
            label: "Edge Rotor Host",
            identifier: heistId.rawValue,
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
        XCTAssertEqual(result.method.rawValue, ActionMethod.rotor.rawValue)
        XCTAssertTrue(result.message?.contains("Rotor 'Live Rotor' found Edge Rotor Host") ?? false,
                      result.message ?? "missing rotor success message")
    }

    func testExecuteRotorDoesNotRequireHostActivationPointOnscreen() async {
        let heistId: HeistId = "offscreen_rotor_host"
        let screenBounds = ScreenMetrics.current.bounds
        let frame = CGRect(x: 32, y: screenBounds.maxY - 8, width: 240, height: 44)
        let activationPoint = CGPoint(x: frame.midX, y: frame.midY)
        let element = AccessibilityElement.make(
            label: "Offscreen Rotor Host",
            identifier: heistId.rawValue,
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
        XCTAssertEqual(result.method.rawValue, ActionMethod.rotor.rawValue)
        XCTAssertTrue(result.message?.contains("Rotor 'Live Rotor' found Offscreen Rotor Host") ?? false,
                      result.message ?? "missing rotor success message")
    }

    func testExecuteRotorScrollsViewportTowardResultActivationPoint() async {
        let hostHeistId: HeistId = "rotor_result_host"
        let resultHeistId: HeistId = "rotor_result_target"
        let screenBounds = ScreenMetrics.current.bounds
        let scrollView = UIScrollView(frame: screenBounds)
        scrollView.contentSize = CGSize(width: screenBounds.width, height: screenBounds.height + 900)

        let hostFrame = CGRect(x: 32, y: 80, width: 240, height: 44)
        let hostElement = AccessibilityElement.make(
            label: "Rotor Host",
            identifier: hostHeistId.rawValue,
            traits: .staticText,
            shape: .frame(AccessibilityRect(hostFrame)),
            activationPoint: CGPoint(x: hostFrame.midX, y: hostFrame.midY),
            customRotors: [.init(name: "Live Rotor")]
        )
        let resultFrame = CGRect(x: 32, y: screenBounds.maxY + 240, width: 240, height: 44)
        let resultElement = AccessibilityElement.make(
            label: "Rotor Result",
            identifier: resultHeistId.rawValue,
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
                    scrollMembership: nil,
                    element: hostElement
                ),
                resultHeistId: Screen.ScreenElement(
                    heistId: resultHeistId,
                    scrollMembership: nil,
                    element: resultElement
                ),
            ],
            hierarchy: [
                .element(hostElement, traversalIndex: 0),
                .element(resultElement, traversalIndex: 1),
            ],
            heistIdsByPath: [
                TreePath([0]): hostHeistId,
                TreePath([1]): resultHeistId,
            ],
            elementRefs: [
                hostHeistId: .init(object: hostObject, scrollView: scrollView),
                resultHeistId: .init(object: resultObject, scrollView: scrollView),
            ],
            firstResponderHeistId: nil,
        ))

        XCTAssertEqual(scrollView.contentOffset, .zero)

        let result = await brains.actions.executeRotor(
            RotorTarget(
                elementTarget: .predicate(ElementPredicate(identifier: .exact(hostHeistId.rawValue))),
                selection: .named("Live Rotor")
            )
        )

        XCTAssertTrue(result.success, result.message ?? "rotor failed")
        XCTAssertEqual(result.method.rawValue, ActionMethod.rotor.rawValue)
        XCTAssertGreaterThan(scrollView.contentOffset.y, 0)
        XCTAssertTrue(result.message?.contains("Rotor 'Live Rotor' found Rotor Result") ?? false,
                      result.message ?? "missing rotor success message")
    }

    func testExecuteRotorNotFoundReportsAvailableRotorsAndNextStep() async {
        let heistId: HeistId = "rotor_host"
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
        XCTAssertEqual(result.method.rawValue, ActionMethod.rotor.rawValue)
        XCTAssertDiagnostic(result.message, contains: [
            "rotor failed",
            "attempted rotor=\"Errors\" direction=next",
            "requestedRotor=\"Errors\"",
            "availableRotors=[\"Warnings\"]",
            "try use one of available rotors [\"Warnings\"]",
        ])
    }

    func testExecuteRotorDiagnosticsMergeLiveRotors() async {
        let heistId: HeistId = "rotor_host"
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
        let heistId: HeistId = "rotor_host"
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

        XCTAssertEqual(brains.stash.settledSemanticScreen, .empty)
    }

    // MARK: - Accessibility Tree Availability

    func testExecuteCommandWaitForFailsWhenAccessibilityTreeUnavailable() async {
        let target = WaitTarget(
            predicate: .state(.exists(ElementPredicate(label: "never"))),
            timeout: 0
        )
        let result = await withNoTraversableWindows {
            await brains.executeRuntimeAction(.wait(target))
        }

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .wait)
        XCTAssertEqual(result.errorKind, .timeout)
        XCTAssertDiagnostic(result.message, contains: [
            "timed out after",
            "waiting for element to appear",
            "known: 0 elements",
            "last result: element not found",
        ])
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
        elements: [(AccessibilityElement, HeistId)],
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
                    id: $0.heistId.predicateSelectionElementId,
                    element: TheStash.WireConversion.convert($0.element)
                )
            },
            screenId: screen.id,
            semanticHash: screen.semanticHash,
            scope: .visible
        )
        return try XCTUnwrap(minimumUniquePredicate(for: screenElement.heistId.predicateSelectionElementId, in: context)).target
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
        if isPreDispatchMatcherFailure(single),
           isPreDispatchMatcherFailure(heist) {
            XCTAssertTrue(
                [.actionFailed, .elementNotFound].contains(single.errorKind),
                name,
                file: file,
                line: line
            )
            XCTAssertTrue(
                [.actionFailed, .elementNotFound].contains(heist.errorKind),
                name,
                file: file,
                line: line
            )
            return
        }
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

    private func isPreDispatchMatcherFailure(_ result: ActionResult) -> Bool {
        guard result.success == false,
              let message = result.message
        else { return false }
        return message.contains("No match for:")
            || message.contains("Could not observe accessibility tree")
    }

    private func firstLine(_ message: String) -> Substring {
        message.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
    }

    private func heistStepResult(for step: HeistStep, runtimeType: RuntimeActionType) async throws -> ActionResult {
        let result = await brains.executeHeistPlan(try HeistPlan(body: [step]))
        guard case .heistExecution(let heist) = result.payload,
              let stepResult = heist.steps.first,
              let actionResult = stepResult.reportActionResult else {
            XCTFail("Expected heist execution step result for \(runtimeType.rawValue)")
            return result
        }
        return actionResult
    }

    private func observedState(
        labels: [String],
        screenId: String? = nil
    ) -> PostActionObservation.BeforeState {
        observedState(elements: labels.enumerated().map { index, label in
            (makeElement(label: label), HeistId(rawValue: "element_\(index)"))
        }, screenId: screenId)
    }

    private func waitForSettledSemanticWaiter(
        on stash: TheStash,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = CFAbsoluteTimeGetCurrent() + 1
        while stash.semanticObservationStream.settledWaiterCount == 0,
              CFAbsoluteTimeGetCurrent() < deadline {
            await Task.yield()
            guard await Task.cancellableSleep(for: .milliseconds(5)) else { break }
        }
        XCTAssertEqual(stash.semanticObservationStream.settledWaiterCount, 1, file: file, line: line)
    }

    private func observedState(
        elements: [(AccessibilityElement, HeistId)],
        screenId: String? = nil
    ) -> PostActionObservation.BeforeState {
        brains.stash.installScreenForTesting(.makeForTests(elements: elements))
        let state = brains.postActionObservation.captureSemanticState()
        guard let screenId else { return state }

        let context = AccessibilityTrace.Context(
            firstResponder: state.capture.context.firstResponder,
            keyboardVisible: state.capture.context.keyboardVisible,
            screenId: screenId,
            windowStack: state.capture.context.windowStack
        )
        let capture = AccessibilityTrace.Capture(
            sequence: state.capture.sequence,
            interface: state.capture.interface,
            parentHash: state.capture.parentHash,
            context: context,
            transition: state.capture.transition
        )
        return PostActionObservation.BeforeState(
            screen: state.screen,
            snapshot: state.snapshot,
            elements: state.elements,
            hierarchy: state.hierarchy,
            interface: state.interface,
            interfaceHash: AccessibilityTrace.Capture.hash(interface: state.interface, context: context),
            semanticHash: state.semanticHash,
            capture: capture,
            tripwireSignal: state.tripwireSignal,
            screenSnapshot: state.screenSnapshot,
            screenId: screenId,
            settledObservationSequence: state.settledObservationSequence
        )
    }

    private func heistRuntime(
        observations: [PostActionObservation.BeforeState],
        execute: (@MainActor (RuntimeActionMessage) async -> ActionResult)? = nil,
        wait: (@MainActor (TheBrains.HeistRuntimeWaitRequest) async -> ActionResult)? = nil,
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
                return ActionResult(success: true, method: .heistPlan, message: command.runtimeType.rawValue)
            },
            wait: { request in
                let waitStep = request.step
                let initialTrace = request.initialTrace
                let afterSequence = request.afterSequence
                let observationScope = SemanticObservationScope.discovery
                if let wait {
                    return self.heistWaitReceipt(for: waitStep, result: await wait(request))
                }
                if let initialTrace, afterSequence == nil {
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
                if waitStep.timeout == 0,
                   afterSequence == nil,
                   let observation = observationSource.immediate(scope: observationScope) {
                    let expectation = PredicateEvaluation.evaluate(waitStep.predicate, in: observation)
                    let result = ActionResult(
                        success: expectation.met,
                        method: .wait,
                        message: expectation.actual,
                        errorKind: expectation.met ? nil : .timeout,
                        accessibilityTrace: observation.accessibilityTrace
                    )
                    return HeistWaitReceipt(
                        actionResult: result,
                        expectation: expectation,
                        observedSequence: observation.event.sequence,
                        observationSummary: observation.summary
                    )
                }
                guard let observation = observationSource.next(
                    scope: observationScope,
                    timeout: waitStep.timeout
                ) else {
                    let expectation = ExpectationResult(
                        met: false,
                        predicate: waitStep.predicate,
                        actual: "no settled semantic observation available"
                    )
                    let result = ActionResult(
                        success: false,
                        method: .wait,
                        message: expectation.actual,
                        errorKind: .timeout
                    )
                    return HeistWaitReceipt(actionResult: result, expectation: expectation)
                }
                let trace = observation.accessibilityTrace
                let met = PredicateEvaluation.evaluate(waitStep.predicate, in: observation)
                let result = ActionResult(
                    success: met.met,
                    method: .wait,
                    message: met.actual,
                    errorKind: met.met ? nil : .timeout,
                    accessibilityTrace: trace
                )
                return HeistWaitReceipt(
                    actionResult: result,
                    expectation: met,
                    observedSequence: observation.event.sequence,
                    observationSummary: observation.summary
                )
            },
            selectPredicateCase: { cases, timeout in
                await PredicateCaseSelection.waitFor(
                    cases,
                    timeout: timeout,
                    observeSemanticState: { scope, _, timeout in
                        observationSource.next(scope: scope, timeout: timeout)
                    }
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
            .replacingOccurrences(
                of: #"known: [0-9]+ elements"#,
                with: "known: <count> elements",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"hash sha256:[a-f0-9]+"#,
                with: "hash sha256:<hash>",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"last delta: (none|no_change)"#,
                with: "last delta: <settled>",
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
    private var nextObservationSequence: SettledObservationSequence = 0
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

    func immediate(scope: SemanticObservationScope) -> HeistSemanticObservation? {
        guard remainingUnavailableObservations == 0 else { return nil }
        guard !remainingObservations.isEmpty else {
            XCTFail("Expected scripted heist case observation", file: file, line: line)
            return nil
        }
        let state = remainingObservations.removeFirst()
        nextObservationSequence += 1
        let observation = observation(
            from: state,
            scope: scope,
            sequence: nextObservationSequence
        )
        previousObservation = observation.event.observation
        previousCapture = observation.accessibilityTrace.captures.last
        return observation
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
        let observation = observation(
            from: state,
            scope: scope,
            sequence: nextObservationSequence
        )
        previousObservation = observation.event.observation
        previousCapture = observation.accessibilityTrace.captures.last
        return observation
    }

    private func observation(
        from state: PostActionObservation.BeforeState,
        scope: SemanticObservationScope,
        sequence: SettledObservationSequence
    ) -> HeistSemanticObservation {
        let settledObservation = SettledSemanticObservation(
            sequence: sequence,
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
            sequence: sequence,
            scope: scope,
            observation: settledObservation,
            previous: previousObservation,
            trace: trace,
            delta: trace.endpointDelta
        )
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
