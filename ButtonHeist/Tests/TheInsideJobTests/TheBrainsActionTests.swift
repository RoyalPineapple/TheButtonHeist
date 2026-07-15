#if canImport(UIKit)
import ButtonHeistSupport
import ButtonHeistTestSupport
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

private final class ActionActivatingTextField: UITextField {
    private(set) var activationCount = 0

    override func accessibilityActivate() -> Bool {
        activationCount += 1
        return becomeFirstResponder()
    }
}

private final class ResignationTrackingTextField: UITextField {
    private(set) var resignationCount = 0

    override func resignFirstResponder() -> Bool {
        resignationCount += 1
        return super.resignFirstResponder()
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
        textField?.isFirstResponder == true ? inputDelegate : nil
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
        XCTAssertTrue(before.elements.isEmpty,
                      "Elements should be empty when no hierarchy set")
    }

    func testPostActionObservationCaptureIncludesRegisteredElements() {
        let element = makeElement(label: "Title", traits: .header)
        let heistId: HeistId = "header_title"
        installScreen(elements: [(element, heistId)])

        let before = brains.postActionObservation.captureSemanticState()
        XCTAssertEqual(before.screen.orderedElements.count, 1)
        XCTAssertEqual(before.screen.orderedElements.first?.heistId, heistId)
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

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(result.outcome.errorKind, .accessibilityTreeUnavailable)
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
        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "action unexpectedly failed")
        XCTAssertEqual(result.method, .activate)
        XCTAssertTrue(
            brains.stash.interfaceTree.orderedElements.contains { $0.element.label == "Visible Evidence Action" },
            "the observed full tree should be committed so action resolution sees live evidence"
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
            "actions=[activate, Delete, Archive]",
            "try use one of custom actions [\"Delete\", \"Archive\"]",
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
            "actions=[activate, Delete, Archive]",
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

    func testExecuteActivateFailsForNoTraitElementWithoutActivationSignal() async throws {
        let heistId: HeistId = "plain_label"
        let liveObject = UIView()
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Plain label"),
            object: liveObject
        )

        let target = try AccessibilityTarget.label("Plain label").resolve(in: .empty)
        let result = await brains.actions.executeActivate(target)

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
        let resolved = brains.stash.resolveTarget(target).resolved
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
        brains.stash.installScreenForTesting(.makeForTests(
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
        brains.stash.installScreenForTesting(.makeForTests(
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
            ("tap", .mechanicalTap(TapTarget(selection: .element(target)))),
            ("swipe", .mechanicalSwipe(SwipeTarget(selection: .elementDirection(target, .left)))),
            ("type text", .typeText(text: "hello", target: target)),
        ]

        for (label, authoredCommand) in commands {
            let command = try authoredCommand.resolve(in: .empty)
            brains.clearCache()
            let single = await brains.executeRuntimeAction(command)
            brains.clearCache()
            let heist = try await heistStepResult(
                for: .action(try ActionStep(command: authoredCommand)),
                label: command.runtimeType.rawValue
            )
            assertSameActionResult(
                label,
                single: single,
                heist: heist,
                normalizingTimeoutDuration: false
            )
        }

        let authoredWait = WaitStep(predicate: .exists(target), timeout: 0.01)
        brains.clearCache()
        let singleWait = await brains.performWait(step: try resolvedWait(authoredWait))
        brains.clearCache()
        let heistWait = try await heistStepResult(for: .wait(authoredWait), label: "wait")
        assertSameActionResult(
            "wait",
            single: singleWait,
            heist: heistWait,
            normalizingTimeoutDuration: true
        )
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
            .mechanicalTap(TapTarget(selection: point)),
            .mechanicalLongPress(LongPressTarget(selection: point)),
            .mechanicalSwipe(SwipeTarget(selection: .point(start: .coordinate(ScreenPoint(x: 20, y: 20)), destination: .direction(.left)))),
            .mechanicalDrag(DragTarget(start: .coordinate(ScreenPoint(x: 20, y: 20)), end: ScreenPoint(x: 80, y: 80))),
            .editAction(EditActionTarget(action: .paste)),
            .setPasteboard(SetPasteboardTarget(text: "clipboard")),
            .takeScreenshot,
            .dismissKeyboard,
        ]
        var dispatchedTypes: [HeistActionCommandType] = []
        let runtime = heistRuntime(observations: []) { command in
            dispatchedTypes.append(command.runtimeType)
            return ActionResult.success(
                method: command.testActionResultMethod,
                message: command.runtimeType.rawValue,
                evidence: .none
            )
        }
        let plan = try HeistPlan(body: commands.map { .action(try ActionStep(command: $0)) })

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "heist failed")
        let expectedTypes = try commands.map {
            try $0.resolve(in: .empty).runtimeType
        }
        XCTAssertEqual(dispatchedTypes, expectedTypes)
        guard case .heistExecution(let heist) = result.payload else {
            return XCTFail("Expected heist execution payload")
        }
        XCTAssertEqual(heist.steps.count, commands.count)
        XCTAssertTrue(heist.steps.allSatisfy { $0.status == HeistExecutionStepStatus.passed })
    }

    func testFailedActivateHeistActionKeepsActivationTraceInActionEvidence() async throws {
        let activationTrace = ActivationTrace(.activationPointFallback(
            axActivateReturned: false,
            tapActivationPoint: ScreenPoint(x: 195, y: 139),
            tapActivationSucceeded: true
        ))
        let target = AccessibilityTarget.label("Search all items")
        let command = HeistActionCommand.activate(target)
        let runtime = heistRuntime(observations: []) { _ in
            ActionResult.failure(
                method: .activate,
                errorKind: .actionFailed,
                message: "text entry failed: observed focus=none keyboardVisible=false activeTextInput=false",
                evidence: ActionResultFailureEvidence(
                    observation: .none,
                    activationTrace: activationTrace
                )
            )
        }
        let plan = try HeistPlan(body: [.action(ActionStep(command: command))])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertFalse(result.outcome.isSuccess)
        guard case .heistExecution(let heist) = result.payload else {
            return XCTFail("Expected failed heist execution payload")
        }
        let step = try XCTUnwrap(heist.steps.first)
        XCTAssertEqual(step.actionEvidence?.dispatchResult?.activationTrace, activationTrace)
    }

    func testViewportDebugCommandsResolveForDirectRuntimeDispatch() throws {
        let target = AccessibilityTarget.identifier("target")
        let commands: [(HeistActionCommand, HeistActionCommandType)] = [
            (.viewportScroll(ScrollTarget(direction: .down)), .scroll),
            (.viewportScrollToVisible(target), .scrollToVisible),
            (.viewportScrollToEdge(ScrollToEdgeTarget(edge: .bottom)), .scrollToEdge),
        ]

        for (command, expectedType) in commands {
            XCTAssertNotNil(command.durableHeistActionFailure)
            XCTAssertEqual(try command.resolve(in: .empty).runtimeType, expectedType)
        }
    }

    func testHeistActionAndWaitStepsUseSeparateRuntimeTransitions() async throws {
        let observedReady = observedState(labels: ["Ready"])
        let target = AccessibilityTarget.identifier("target")
        var dispatchedTypes: [HeistActionCommandType] = []
        var waitRequests: [TheBrains.HeistRuntimeWaitRequest] = []
        let runtime = heistRuntime(
            observations: [],
            execute: { command in
                dispatchedTypes.append(command.runtimeType)
                return ActionResult.success(method: .activate, message: command.runtimeType.rawValue, evidence: .none)
            },
            wait: { request in
                waitRequests.append(request)
                return ActionResult.success(
                    method: .wait,
                    evidence: ActionResultSuccessEvidence(
                        observation: .trace(makeTestTraceEvidence(
                            AccessibilityTrace(capture: observedReady.capture),
                            completeness: .incomplete
                        ))
                    )
                )
            }
        )
        let plan = try HeistPlan(body: [
            .action(try ActionStep(command: .activate(target))),
            .wait(WaitStep(
                predicate: .exists(.label("Ready")),
                timeout: 0
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist: HeistExecutionResult = try XCTUnwrap(result.heistExecutionPayload)
        let actionStep = try XCTUnwrap(heist.steps.first)
        let waitStep = try XCTUnwrap(heist.steps.dropFirst().first)

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "heist failed")
        XCTAssertEqual(dispatchedTypes, [.activate])
        XCTAssertEqual(waitRequests.count, 1)
        if case .standalone(let request)? = waitRequests.first {
            XCTAssertEqual(request.predicate, try resolvedPredicate(.exists(.label("Ready"))))
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
        let target = AccessibilityTarget.label("Checkout")
        let resolvedTarget = try target.resolve(in: .empty)
        let subject = makeTestHeistElement(
            label: "Checkout",
            traits: [.staticText],
            actions: [.activate]
        )
        let runtime = heistRuntime(
            observations: [],
            execute: { _ in
                ActionResult.success(
                    method: .activate,
                    evidence: ActionResultSuccessEvidence(
                        observation: .none,
                        subjectEvidence: ActionSubjectEvidence(
                            source: .resolvedSemanticTarget,
                            target: resolvedTarget,
                            element: subject,
                            resolution: ActionSubjectResolution(origin: .visible)
                        ),
                        warning: .activationWeakAffordance(
                            evidence: #"label="Checkout" traits=[staticText] actions=[activate]"#
                        )
                    )
                )
            }
        )
        let plan = try HeistPlan(body: [
            .action(try ActionStep(command: .activate(target))),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "heist failed")
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let warning = try XCTUnwrap(heist.steps.first?.actionEvidence?.warning)
        XCTAssertEqual(warning.code, "activation_weak_affordance_evidence")
        XCTAssertEqual(
            warning.message,
            "activate succeeded, but the target does not advertise a primary activation affordance"
        )
        XCTAssertEqual(warning.evidence, #"label="Checkout" traits=[staticText] actions=[activate]"#)
        XCTAssertEqual(heist.warnings, [])
    }

    func testHeistTypeTextRecordsWeakAffordanceWarningOnSuccessfulActionEvidence() async throws {
        let target = AccessibilityTarget.label("Notes")
        let resolvedTarget = try target.resolve(in: .empty)
        let subject = makeTestHeistElement(
            label: "Notes",
            traits: [.staticText],
            actions: []
        )
        let runtime = heistRuntime(
            observations: [],
            execute: { _ in
                ActionResult.success(
                    method: .typeText,
                    evidence: ActionResultSuccessEvidence(
                        observation: .none,
                        subjectEvidence: ActionSubjectEvidence(
                            source: .textInputTarget,
                            target: resolvedTarget,
                            element: subject,
                            resolution: ActionSubjectResolution(origin: .visible)
                        ),
                        warning: .textEntryWeakAffordance(
                            evidence: #"label="Notes" traits=[staticText] actions=[]"#
                        )
                    )
                )
            }
        )
        let plan = try HeistPlan(body: [
            .action(try ActionStep(command: .typeText(
                text: "hello",
                target: target
            ))),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "heist failed")
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let warning = try XCTUnwrap(heist.steps.first?.actionEvidence?.warning)
        XCTAssertEqual(warning.code, "text_entry_weak_affordance_evidence")
        XCTAssertEqual(
            warning.message,
            "typeText succeeded, but the target does not advertise a text-input trait"
        )
        XCTAssertEqual(warning.evidence, #"label="Notes" traits=[staticText] actions=[]"#)
    }

    func testHeistFailureRecordsScreenshotAsActionEvidence() async throws {
        let target = AccessibilityTarget.identifier("target")
        let screenshot = ScreenPayload(
            pngData: "png",
            width: 10,
            height: 20,
            timestamp: Date(timeIntervalSince1970: 0),
            interface: Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
        )
        var dispatchedTypes: [HeistActionCommandType] = []
        let runtime = heistRuntime(observations: []) { command in
            dispatchedTypes.append(command.runtimeType)
            if case .takeScreenshot = command {
                return ActionResult.success(payload: .screenshot(screenshot), evidence: .none)
            }
            return ActionResult.failure(
                method: .activate,
                errorKind: .actionFailed,
                message: "activate failed",
                evidence: .none
            )
        }
        let plan = try HeistPlan(body: [
            .action(try ActionStep(command: .activate(target))),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertFalse(result.outcome.isSuccess)
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
        guard case .screenshot(let payload) = screenshotStep.actionEvidence?.dispatchResult?.payload else {
            return XCTFail("Expected screenshot action payload")
        }
        XCTAssertEqual(payload, screenshot)
    }

    func testHeistFailurePhaseSkipsRemainingStepsWithoutDispatchingActions() async throws {
        let target = AccessibilityTarget.identifier("target")
        var dispatchedTypes: [HeistActionCommandType] = []
        let runtime = heistRuntime(observations: []) { command in
            dispatchedTypes.append(command.runtimeType)
            if case .takeScreenshot = command {
                return ActionResult.success(method: .takeScreenshot, evidence: .none)
            }
            return ActionResult.failure(
                method: .activate,
                errorKind: .actionFailed,
                message: "activate failed",
                evidence: .none
            )
        }
        let plan = try HeistPlan(body: [
            .action(try ActionStep(command: .activate(target))),
            .action(try ActionStep(command: .setPasteboard(SetPasteboardTarget(text: "not dispatched")))),
            .heist(try HeistPlan(body: [
                .action(try ActionStep(command: .dismissKeyboard)),
            ])),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertFalse(result.outcome.isSuccess)
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

        XCTAssertTrue(result.outcome.isSuccess)
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

        XCTAssertTrue(result.outcome.isSuccess)
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
                predicate: .exists(.label("Home")),
                timeout: 0
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertFalse(result.outcome.isSuccess)
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
                predicate: .exists(.label("Home")),
                timeout: 0,
                elseBody: [.warn(WarnStep(message: "no known state appeared"))]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.outcome.isSuccess)
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
                return ActionResult.success(method: .increment, message: command.runtimeType.rawValue, evidence: .none)
            }
        )
        let plan = try HeistPlan(body: [
            .repeatUntil(try RepeatUntilStep(
                predicate: .exists(.element(.identifier("quantity"), .value("2"))),
                timeout: 1,
                body: [
                    .action(try ActionStep(command: .increment(.predicate(.identifier("quantity"))))),
                ]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "repeat_until failed")
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
                return ActionResult.success(method: .increment, message: command.runtimeType.rawValue, evidence: .none)
            },
            observedTimeouts: { observedTimeouts.append($0) }
        )
        let plan = try HeistPlan(body: [
            .repeatUntil(try RepeatUntilStep(
                predicate: .exists(.element(.identifier("quantity"), .value("100"))),
                timeout: 5,
                body: [
                    .action(try ActionStep(command: .increment(.predicate(.identifier("quantity"))))),
                ]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "repeat_until failed")
        XCTAssertEqual(incrementCount, 1)
        XCTAssertEqual(step.repeatUntilEvidence?.iterationCount, 1)
        XCTAssertEqual(step.repeatUntilEvidence?.expectation.met, true)
        XCTAssertEqual(observedTimeouts.count, 1)
        let observedTimeout = try XCTUnwrap(observedTimeouts.first.flatMap { $0 })
        XCTAssertEqual(observedTimeout, defaultActionExpectationTimeout, accuracy: 0.1)
    }

    func testHeistRepeatUntilUsesActionTraceProgressBeforePostBodyWait() async throws {
        let predicate = AccessibilityPredicate.exists(.element(.identifier("quantity"), .value("2")))
        let resolved = try resolvedPredicate(predicate)
        let initialState = observedState(elements: [(makeElement(value: "0", identifier: "quantity"), "quantity")])
        let firstMutation = observedState(elements: [(makeElement(value: "1", identifier: "quantity"), "quantity")])
        let secondMutation = observedState(elements: [(makeElement(value: "2", identifier: "quantity"), "quantity")])
        let states = [initialState, firstMutation, secondMutation]
        var incrementCount = 0
        let runtime = repeatUntilReceiptRuntime(
            execute: { command in
                guard case .increment = command else {
                    return ActionResult.success(method: .activate, evidence: .none)
                }
                let before = states[incrementCount]
                incrementCount += 1
                let after = states[incrementCount]
                return ActionResult.success(
                    method: .increment,
                    evidence: ActionResultSuccessEvidence(
                        observation: .settledTrace(
                            makeTestTraceEvidence(
                                AccessibilityTrace(captures: [before.capture, after.capture]),
                                completeness: .incomplete
                            ),
                            .settled(durationMs: 0)
                        )
                    )
                )
            },
            wait: { request in
                switch request {
                case .immediate:
                    let initialTrace = AccessibilityTrace(capture: initialState.capture)
                    let expectation = PredicateEvaluation.evaluate(
                        resolved,
                        expression: predicate,
                        in: initialTrace,
                        completeness: .incomplete
                    )
                    return .timedOut(
                        message: expectation.actual,
                        traceEvidence: makeTestTraceEvidence(initialTrace, completeness: .incomplete),
                        expectation: self.unmetExpectation(expectation),
                        observedSequence: 1,
                        observationSummary: "interface: 1 elements"
                    )
                case .afterObservation:
                    XCTFail("repeat_until should use action trace progress before post-body wait")
                    return .failed(
                        errorKind: .general,
                        message: "unexpected post-body wait",
                        traceEvidence: nil,
                        expectation: ExpectationResult.Unmet(
                            predicate: predicate,
                            actual: "unexpected post-body wait"
                        )
                    )
                case .standalone, .actionEndpoint, .baselineTraceOnly:
                    XCTFail("repeat_until should not issue \(request)")
                    return .failed(
                        errorKind: .general,
                        message: "unexpected wait request",
                        traceEvidence: nil,
                        expectation: ExpectationResult.Unmet(
                            predicate: predicate,
                            actual: "unexpected wait request"
                        )
                    )
                }
            }
        )
        let plan = try HeistPlan(body: [
            .repeatUntil(try RepeatUntilStep(
                predicate: predicate,
                timeout: 1,
                body: [
                    .action(try ActionStep(command: .increment(.predicate(.identifier("quantity"))))),
                ]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        guard case .heistExecution(let heist) = result.payload else {
            return XCTFail("Expected heist execution payload")
        }
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "repeat_until failed")
        XCTAssertEqual(incrementCount, 2)
        XCTAssertEqual(step.repeatUntilEvidence?.iterationCount, 2)
        XCTAssertEqual(step.repeatUntilEvidence?.expectation.met, true)
        XCTAssertEqual(
            step.children.map(\.kind),
            [HeistExecutionStepKind.repeatUntilIteration, .repeatUntilIteration]
        )
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
                        return ActionResult.failure(
                            method: .activate,
                            errorKind: .actionFailed,
                            message: "Element is disabled (has 'notEnabled' trait)",
                            evidence: .none
                        )
                    }
                }
                return ActionResult.success(method: .activate, message: command.runtimeType.rawValue, evidence: .none)
            }
        )
        let plan = try HeistPlan(body: [
            .repeatUntil(try RepeatUntilStep(
                predicate: .exists(.element(.identifier("quantity"), .value("2"))),
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

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "repeat_until failed")
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
                        return ActionResult.failure(
                            method: .activate,
                            errorKind: .actionFailed,
                            message: "Element is disabled (has 'notEnabled' trait)",
                            evidence: .none
                        )
                    }
                }
                return ActionResult.success(method: .activate, message: command.runtimeType.rawValue, evidence: .none)
            }
        )
        let plan = try HeistPlan(body: [
            .repeatUntil(try RepeatUntilStep(
                predicate: .exists(.element(.identifier("quantity"), .value("2"))),
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

        XCTAssertFalse(result.outcome.isSuccess)
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
        XCTAssertEqual(failedRetry.actionEvidence?.dispatchResult?.outcome.errorKind, .actionFailed)
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
                return ActionResult.success(method: .increment, message: command.runtimeType.rawValue, evidence: .none)
            }
        )
        let plan = try HeistPlan(body: [
            .repeatUntil(try RepeatUntilStep(
                predicate: .exists(.element(.identifier("quantity"), .value("2"))),
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

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "repeat_until else failed")
        XCTAssertEqual(incrementCount, 0)
        XCTAssertEqual(step.kind, .repeatUntil)
        XCTAssertEqual(step.status, .passed)
        XCTAssertEqual(step.repeatUntilEvidence?.iterationCount, 0)
        XCTAssertEqual(step.repeatUntilEvidence?.expectation.met, false)
        XCTAssertEqual(step.repeatUntilEvidence?.outcome, .handledElse)
        XCTAssertNil(step.failure)
        XCTAssertEqual(step.children.map(\.kind), [.warn])
    }

    func testHeistRepeatUntilPostBodyMatchedWaitWithoutObservedSequenceDoesNotReusePreviousSequence() async throws {
        let predicate = AccessibilityPredicate.exists(.element(.identifier("quantity"), .value("2")))
        let resolved = try resolvedPredicate(predicate)
        let initialState = observedState(elements: [(makeElement(value: "0", identifier: "quantity"), "quantity")])
        let matchedState = observedState(elements: [(makeElement(value: "2", identifier: "quantity"), "quantity")])
        let initialTrace = AccessibilityTrace(interface: initialState.interface)
        let matchedTrace = AccessibilityTrace(interface: matchedState.interface)
        var afterObservationCount = 0
        let runtime = repeatUntilReceiptRuntime(
            wait: { request in
                switch request {
                case .immediate:
                    let expectation = PredicateEvaluation.evaluate(
                        resolved,
                        expression: predicate,
                        in: initialTrace,
                        completeness: .incomplete
                    )
                    return .timedOut(
                        message: expectation.actual,
                        traceEvidence: makeTestTraceEvidence(initialTrace, completeness: .incomplete),
                        expectation: self.unmetExpectation(expectation),
                        observedSequence: 1,
                        observationSummary: "interface: 1 elements"
                    )
                case .afterObservation:
                    afterObservationCount += 1
                    let expectation = PredicateEvaluation.evaluate(
                        resolved,
                        expression: predicate,
                        in: matchedTrace,
                        completeness: .incomplete
                    )
                    return .matched(
                        message: expectation.actual,
                        traceEvidence: makeTestTraceEvidence(matchedTrace, completeness: .incomplete),
                        expectation: self.metExpectation(expectation)
                    )
                case .standalone, .actionEndpoint, .baselineTraceOnly:
                    XCTFail("repeat_until should not issue \(request)")
                    return .failed(
                        errorKind: .general,
                        message: "unexpected wait request",
                        traceEvidence: nil,
                        expectation: ExpectationResult.Unmet(
                            predicate: predicate,
                            actual: "unexpected wait request"
                        )
                    )
                }
            }
        )
        let plan = try HeistPlan(body: [
            .repeatUntil(try RepeatUntilStep(
                predicate: predicate,
                timeout: 1,
                body: [
                    .action(try ActionStep(command: .increment(.predicate(.identifier("quantity"))))),
                ]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(afterObservationCount, 1)
        XCTAssertEqual(step.repeatUntilEvidence?.outcome, .failed)
        XCTAssertEqual(step.repeatUntilEvidence?.expectation.met, false)
        XCTAssertEqual(
            step.repeatUntilEvidence?.expectation.actual,
            "repeat_until post-body check matched without settled observation"
        )
        XCTAssertNil(step.repeatUntilEvidence?.lastObservedSummary)
    }

    func testHeistRepeatUntilPostBodyNilTraceWithNewSequenceDoesNotReuseStaleTraceOrSummary() async throws {
        let predicate = AccessibilityPredicate.exists(.element(.identifier("quantity"), .value("2")))
        let resolved = try resolvedPredicate(predicate)
        let initialState = observedState(elements: [(makeElement(value: "0", identifier: "quantity"), "quantity")])
        let initialTrace = AccessibilityTrace(interface: initialState.interface)
        let runtime = repeatUntilReceiptRuntime(
            wait: { request in
                switch request {
                case .immediate:
                    let expectation = PredicateEvaluation.evaluate(
                        resolved,
                        expression: predicate,
                        in: initialTrace,
                        completeness: .incomplete
                    )
                    return .timedOut(
                        message: expectation.actual,
                        traceEvidence: makeTestTraceEvidence(initialTrace, completeness: .incomplete),
                        expectation: self.unmetExpectation(expectation),
                        observedSequence: 1,
                        observationSummary: "interface: 1 elements"
                    )
                case .afterObservation:
                    return .timedOut(
                        message: "no observed accessibility trace",
                        traceEvidence: nil,
                        expectation: ExpectationResult.Unmet(
                            predicate: .changed(.elements()),
                            actual: "no observed accessibility trace"
                        ),
                        observedSequence: 2,
                        observationSummary: nil
                    )
                case .standalone, .actionEndpoint, .baselineTraceOnly:
                    XCTFail("repeat_until should not issue \(request)")
                    return .failed(
                        errorKind: .general,
                        message: "unexpected wait request",
                        traceEvidence: nil,
                        expectation: ExpectationResult.Unmet(
                            predicate: predicate,
                            actual: "unexpected wait request"
                        )
                    )
                }
            }
        )
        let plan = try HeistPlan(body: [
            .repeatUntil(try RepeatUntilStep(
                predicate: predicate,
                timeout: 1,
                body: [
                    .action(try ActionStep(command: .increment(.predicate(.identifier("quantity"))))),
                ]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(step.repeatUntilEvidence?.expectation.met, false)
        XCTAssertEqual(step.repeatUntilEvidence?.expectation.actual, "no observed accessibility trace")
        XCTAssertNil(step.repeatUntilEvidence?.lastObservedSummary)
    }

    func testHeistRepeatUntilTimeoutElseChildFailureReportsElsePath() async throws {
        let runtime = heistRuntime(observations: [
            observedState(elements: [(makeElement(value: "0", identifier: "quantity"), "quantity")]),
        ])
        let plan = try HeistPlan(body: [
            .repeatUntil(try RepeatUntilStep(
                predicate: .exists(.element(.identifier("quantity"), .value("2"))),
                timeout: 0,
                body: [
                    .action(try ActionStep(command: .increment(.predicate(.identifier("quantity"))))),
                ],
                elseBody: [
                    .fail(FailStep(message: "quantity did not reach 2")),
                ]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)
        let elseFailurePath = "$.body[0].repeat_until.else_body[0]"

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(heist.abortedAtPath, elseFailurePath)
        XCTAssertEqual(step.status, .failed)
        XCTAssertEqual(step.abortedAtChildPath, elseFailurePath)
        XCTAssertEqual(step.repeatUntilEvidence?.outcome, .failed)
        XCTAssertEqual(step.repeatUntilEvidence?.expectation.met, false)
        XCTAssertTrue(step.repeatUntilEvidence?.failureReason?.contains("else body failed at \(elseFailurePath)") == true)
        XCTAssertEqual(step.failure?.observed, "child failed at \(elseFailurePath)")
        XCTAssertEqual(step.children.first?.path, elseFailurePath)
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

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(step.kind, .conditional)
        XCTAssertEqual(step.caseSelectionEvidence?.selection.outcome, HeistCaseSelectionOutcome.matchedCase(index: 0))
        XCTAssertEqual(step.children.map(\.kind), [.warn])
    }

    func testPredicateObservationStreamSeparatesStateAndChangeEvidence() async throws {
        let readyTarget = AccessibilityTarget.label("Ready")
        let observationStream = brains.stash.semanticObservationStream
        let baselineEvent = observationStream.commitVisibleObservationForTesting(
            .makeForTests(elements: [(makeElement(label: "Loading"), HeistId(rawValue: "loading"))])
        )
        let changedEvent = observationStream.commitVisibleObservationForTesting(
            .makeForTests(elements: [
                (makeElement(label: "Loading"), HeistId(rawValue: "loading")),
                (makeElement(label: "Ready"), HeistId(rawValue: "ready")),
            ])
        )
        var stream = PredicateObservationStreamState()

        let baselineObservation = brains.postActionObservation.semanticObservation(from: baselineEvent)
        let changePredicate = AccessibilityPredicate.changed(.elements([.appeared(readyTarget)]))
        let resolvedChangePredicate = try resolvedPredicate(changePredicate)
        let seeded = stream.reducing(
            baselineObservation,
            predicate: resolvedChangePredicate,
            predicateExpression: changePredicate,
            baselineSeed: .previousObservationIfAvailable
        )
        stream = seeded.state

        XCTAssertFalse(seeded.reduction.expectation.met)
        XCTAssertEqual(
            seeded.reduction.expectation.actual,
            PredicateObservationDiagnostics.changePredicateNeedsFutureObservationMessage
        )

        let changedObservation = brains.postActionObservation.semanticObservation(from: changedEvent)
        let baseline = try XCTUnwrap(seeded.state.observationBaseline)
        let changed = stream.reducing(
            changedObservation,
            predicate: resolvedChangePredicate,
            predicateExpression: changePredicate,
            observationWindow: try XCTUnwrap(observationStream.observationWindow(
                from: baseline,
                through: changedEvent
            ))
        )
        let stateExpression = AccessibilityPredicate.exists(readyTarget)
        let stateExpectation = PredicateEvaluation.evaluate(
            try resolvedPredicate(stateExpression),
            expression: stateExpression,
            in: changed.reduction.evidence
        )

        XCTAssertTrue(stateExpectation.met)
        XCTAssertTrue(changed.reduction.expectation.met)
        XCTAssertEqual(changed.reduction.changeBaseline?.cursor.sequence, baselineObservation.event.sequence)
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

        XCTAssertTrue(result.outcome.isSuccess)
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
                predicate: .exists(.label("Never Appears")),
                timeout: 0
            )),
        ])

        let start = CFAbsoluteTimeGetCurrent()
        let result = await brains.executeHeistPlan(plan)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertLessThan(elapsed, 3)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)
        XCTAssertDiagnostic(step.reportActionResult?.message, contains: [
            "last settled: sequence ",
            "last change:",
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
                predicate: .exists(.label("Home")),
                timeout: 0
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(observedTimeouts, [])
    }

    func testPerformWaitTimeoutZeroDoesNotStartObservationWhenRuntimeInactive() async throws {
        let inactiveBrains = TheBrains(tripwire: TheTripwire())
        inactiveBrains.stash.installScreenForTesting(.makeForTests(elements: [
            (makeElement(label: "Home"), HeistId(rawValue: "home")),
        ]))
        XCTAssertFalse(inactiveBrains.stash.semanticObservationStream.isActive)

        let step = WaitStep(predicate: .exists(.label("Home")), timeout: 0)
        let result = await inactiveBrains.performWait(step: try resolvedWait(step))

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.outcome.errorKind, .actionFailed)
        XCTAssertEqual(result.message, TheBrains.runtimeInactiveMessage)
        XCTAssertFalse(inactiveBrains.stash.semanticObservationStream.isActive)
    }

    func testExecuteCommandDoesNotStartObservationWhenRuntimeInactive() async {
        let inactiveBrains = TheBrains(tripwire: TheTripwire())
        XCTAssertNil(inactiveBrains.stash.latestSettledSemanticObservation)
        XCTAssertFalse(inactiveBrains.stash.semanticObservationStream.isActive)

        let result = await inactiveBrains.executeRuntimeAction(.activate(.predicate(.label("Home"))))

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.outcome.errorKind, .actionFailed)
        XCTAssertEqual(result.message, TheBrains.runtimeInactiveMessage)
        XCTAssertFalse(inactiveBrains.stash.semanticObservationStream.isActive)
    }

    func testWaitReceiptUsesBeforeAndMatchedSettledObservations() async throws {
        let isolatedBrains = TheBrains(tripwire: TheTripwire())
        defer { isolatedBrains.stopSemanticObservation() }
        let beforeScreen = InterfaceObservation.makeForTests(elements: [
            (makeElement(label: "Before"), "before"),
        ])
        let matchedScreen = InterfaceObservation.makeForTests(elements: [
            (makeElement(label: "Before"), "before"),
            (makeElement(label: "Loaded"), "loaded"),
        ])

        let step = try resolvedWait(WaitStep(
                predicate: .exists(.label("Loaded")),
                timeout: 1
        ))
        let receiptTask = Task { @MainActor in
            await isolatedBrains.interactionObservation.waitForPredicate(step)
        }

        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)
        _ = isolatedBrains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(beforeScreen)
        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)

        _ = isolatedBrains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(matchedScreen)
        let receipt = await receiptTask.value
        let trace = try XCTUnwrap(receipt.actionResult.accessibilityTrace)

        XCTAssertTrue(receipt.actionResult.outcome.isSuccess)
        XCTAssertEqual(trace.captures.first?.interface.projectedElements.map(\.label), ["Before"])
        XCTAssertEqual(trace.captures.last?.interface.projectedElements.map(\.label), ["Before", "Loaded"])
        XCTAssertTrue(trace.changeFacts.contains { if case .elementsChanged = $0 { true } else { false } })
    }

    func testHeistScopedAnnouncementWaitStartsAtScopeCursor() async throws {
        let isolatedBrains = TheBrains(tripwire: TheTripwire())
        let notifications = isolatedBrains.stash.accessibilityNotifications
        let priorHeist = notifications.beginHeistScope()
        notifications.recordForTesting(
            code: 1008,
            notificationData: CapturedAccessibilityNotificationPayload("Ready" as NSString),
            associatedElement: .none
        )
        priorHeist.cancel()
        notifications.recordForTesting(
            code: 1008,
            notificationData: CapturedAccessibilityNotificationPayload("Ready" as NSString),
            associatedElement: .none
        )

        let currentHeist = notifications.beginHeistScope()
        defer { currentHeist.cancel() }
        isolatedBrains.interactionObservation.resetAnnouncementWaitCursorForHeist(
            to: currentHeist.cursor
        )
        let staleReceipt = await isolatedBrains.interactionObservation.waitForPredicate(
            try resolvedWait(WaitStep(predicate: .announcement("Ready"), timeout: 0)),
            announcementCursorStrategy: .heistScoped
        )

        XCTAssertFalse(staleReceipt.actionResult.outcome.isSuccess)

        notifications.recordForTesting(
            code: 1008,
            notificationData: CapturedAccessibilityNotificationPayload("Ready" as NSString),
            associatedElement: .none
        )
        let currentReceipt = await isolatedBrains.interactionObservation.waitForPredicate(
            try resolvedWait(WaitStep(predicate: .announcement("Ready"), timeout: 0)),
            announcementCursorStrategy: .heistScoped
        )

        XCTAssertTrue(currentReceipt.actionResult.outcome.isSuccess)
        XCTAssertEqual(currentReceipt.actionResult.announcement, "Ready")
    }

    func testFailedActionBatchBelongsToDiagnosticAndNextActionClaimsOnlyItsBatch() async {
        let isolatedBrains = TheBrains(tripwire: TheTripwire())
        let baseline = InterfaceObservation.makeForTests(elements: [
            (makeElement(label: "Before"), "before"),
        ])
        let baselineEvent = isolatedBrains.stash.semanticObservationStream.commitVisibleObservationForTesting(baseline)
        let before = isolatedBrains.postActionObservation.captureSemanticState(from: baselineEvent.observation)
        let failedScreen = InterfaceObservation.makeForTests(elements: [
            (makeElement(label: "Unstable"), "unstable"),
        ])

        let failedWindow = isolatedBrains.stash.accessibilityNotifications.beginActionWindow()
        isolatedBrains.stash.accessibilityNotifications.recordForTesting(
            code: 1008,
            notificationData: CapturedAccessibilityNotificationPayload("Action A" as NSString),
            associatedElement: .none
        )
        let failedObservation = await isolatedBrains.stash.semanticObservationStream.settlePostActionObservation(
            baselineTripwireSignal: before.tripwireSignal,
            settleOutcome: SettleSession.Outcome(
                outcome: .timedOut(timeMs: 1),
                events: [],
                finalObservation: SettleSessionFinalObservation(screen: failedScreen),
                elementsByKey: [:]
            ),
            notificationWindow: failedWindow
        )
        let failedResult = isolatedBrains.postActionObservation.settledObservationResult(
            before: before,
            observation: failedObservation
        )

        XCTAssertEqual(failedResult.accessibilityTrace.capturedAnnouncements.map(\.text), ["Action A"])

        let successfulScreen = InterfaceObservation.makeForTests(elements: [
            (makeElement(label: "After"), "after"),
        ])
        let successfulWindow = isolatedBrains.stash.accessibilityNotifications.beginActionWindow()
        isolatedBrains.stash.accessibilityNotifications.recordForTesting(
            code: 1008,
            notificationData: CapturedAccessibilityNotificationPayload("Action B" as NSString),
            associatedElement: .none
        )
        isolatedBrains.stash.recordParsedObservedEvidence(successfulScreen)
        let successfulObservation = await isolatedBrains.stash.semanticObservationStream.settlePostActionObservation(
            baselineTripwireSignal: before.tripwireSignal,
            settleOutcome: SettleSession.Outcome(
                outcome: .settled(timeMs: 1),
                events: [],
                finalObservation: SettleSessionFinalObservation(screen: successfulScreen),
                elementsByKey: [:]
            ),
            notificationWindow: successfulWindow
        )

        guard case .committed(let successfulEvent) = successfulObservation.result else {
            return XCTFail("Expected action B to commit")
        }
        XCTAssertEqual(successfulEvent.trace.capturedAnnouncements.map(\.text), ["Action B"])
        XCTAssertEqual(failedResult.accessibilityTrace.capturedAnnouncements.map(\.text), ["Action A"])
        XCTAssertEqual(
            isolatedBrains.stash.accessibilityNotifications
                .checkpoint(after: .origin, selection: .all)
                .events
                .map(\.sequence),
            [1, 2]
        )
    }

    func testActionExpectationWithMatchingInitialTracePollsForSettledMatch() async throws {
        let isolatedBrains = TheBrains(tripwire: TheTripwire())
        defer { isolatedBrains.stopSemanticObservation() }
        let beforeScreen = InterfaceObservation.makeForTests(elements: [
            (makeElement(label: "Menu"), "menu"),
        ])
        let firstSettledScreen = InterfaceObservation.makeForTests(elements: [
            (makeElement(label: "Menu"), "menu"),
            (makeElement(label: "Grid"), "grid"),
        ])
        let catchUpScreen = InterfaceObservation.makeForTests(elements: [
            (makeElement(label: "Menu"), "menu"),
            (makeElement(label: "Grid"), "grid"),
            (makeElement(label: "Ready"), "ready"),
        ])
        let traceMatchedScreen = catchUpScreen
        let beforeEvent = isolatedBrains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(beforeScreen)
        _ = isolatedBrains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(firstSettledScreen)
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

        let step = try resolvedWait(
            WaitStep(predicate: .exists(.label("Ready")), timeout: 1)
        )
        let receiptTask = Task { @MainActor in
            await isolatedBrains.interactionObservation.waitForPredicate(
                step,
                initialTrace: initialTrace
            )
        }

        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)
        _ = isolatedBrains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(firstSettledScreen)
        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)
        _ = isolatedBrains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(catchUpScreen)
        let receipt = await receiptTask.value

        XCTAssertTrue(receipt.actionResult.outcome.isSuccess)
        XCTAssertEqual(receipt.actionResult.accessibilityTrace?.captures.last?.interface.projectedElements.map(\.label), [
            "Menu",
            "Grid",
            "Ready",
        ])
    }

    func testActionExpectationWithMatchingInitialTraceFailsWithoutSettledPollMatch() async throws {
        let isolatedBrains = TheBrains(tripwire: TheTripwire())
        defer { isolatedBrains.stopSemanticObservation() }
        let beforeScreen = InterfaceObservation.makeForTests(elements: [
            (makeElement(label: "Menu"), "menu"),
        ])
        let firstSettledScreen = InterfaceObservation.makeForTests(elements: [
            (makeElement(label: "Menu"), "menu"),
            (makeElement(label: "Grid"), "grid"),
        ])
        let traceMatchedScreen = InterfaceObservation.makeForTests(elements: [
            (makeElement(label: "Menu"), "menu"),
            (makeElement(label: "Grid"), "grid"),
            (makeElement(label: "Ready"), "ready"),
        ])
        let beforeEvent = isolatedBrains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(beforeScreen)
        _ = isolatedBrains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(firstSettledScreen)
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

        let step = try resolvedWait(
            WaitStep(predicate: .exists(.label("Ready")), timeout: 0.05)
        )
        let receiptTask = Task { @MainActor in
            await isolatedBrains.interactionObservation.waitForPredicate(
                step,
                initialTrace: initialTrace
            )
        }

        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)
        _ = isolatedBrains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(firstSettledScreen)
        let receipt = await receiptTask.value

        XCTAssertFalse(receipt.actionResult.outcome.isSuccess)
        XCTAssertEqual(receipt.actionResult.outcome.errorKind, .timeout)
        XCTAssertEqual(receipt.expectation.actual, "expected target(predicate(label=\"Ready\")) to exist")
    }

    func testChangedActionExpectationUsesPreActionBaselineForSettledActionResult() async throws {
        let isolatedBrains = TheBrains(tripwire: TheTripwire())
        defer { isolatedBrains.stopSemanticObservation() }
        let beforeScreen = InterfaceObservation.makeForTests(elements: [
            (makeElement(label: "Menu", traits: .header), "menu_header"),
        ])
        let afterScreen = InterfaceObservation.makeForTests(elements: [
            (makeElement(label: "Controls Demo", traits: .header), "controls_demo_header"),
        ])
        let beforeEvent = isolatedBrains.stash.semanticObservationStream.commitVisibleObservationForTesting(beforeScreen)
        let afterEvent = isolatedBrains.stash.semanticObservationStream.commitVisibleObservationForTesting(afterScreen)
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
        let screenChanged = AccessibilityNotificationEvidence(
            sequence: 1,
            kind: .screenChanged,
            timestamp: Date(timeIntervalSince1970: 0),
            notificationData: .none,
            associatedElement: .none
        )
        let classification = ScreenClassifier.classify(
            before: before.screenSnapshot,
            after: after.screenSnapshot,
            notifications: [screenChanged.kind]
        )
        let initialTrace = isolatedBrains.postActionObservation.makeAccessibilityTrace(
            afterInterface: after.interface,
            parentCapture: detachedBeforeCapture,
            classification: classification,
            accessibilityNotifications: [screenChanged]
        )
        let actionResult = ActionResult.success(
            method: .activate,
            evidence: ActionResultSuccessEvidence(observation: .settledTrace(
                makeTestTraceEvidence(initialTrace, completeness: .incomplete),
                .settled(durationMs: 0)
            ))
        )

        XCTAssertEqual(classification, .screenChangedNotification)
        XCTAssertNotEqual(initialTrace.captures.first?.hash, afterEvent.trace.captures.first?.hash)
        XCTAssertEqual(initialTrace.captures.first?.hash, detachedBeforeCapture.hash)
        XCTAssertEqual(initialTrace.captures.last?.interface, after.interface)
        XCTAssertEqual(initialTrace.captures.last?.transition.accessibilityNotifications, [screenChanged])
        XCTAssertNil(initialTrace.captures.last?.transition.fallbackReason)
        XCTAssertEqual(actionResult.settled, true)

        let receipt = await isolatedBrains.interactionObservation.waitForPredicate(
            try resolvedWait(WaitStep(
                predicate: .changed(.screen([.exists(.element(
                    .label("Controls Demo"),
                    traits: [.header]
                ))])),
                timeout: 1
            )),
            initialTrace: actionResult.accessibilityTrace
        )

        XCTAssertTrue(receipt.actionResult.outcome.isSuccess)
        XCTAssertTrue(receipt.actionResult.accessibilityTrace?.changeFacts.contains {
            if case .screenChanged = $0 { true } else { false }
        } == true)
    }

    func testWaitReceiptTimeoutDiagnosticUsesFinalSettledObservation() async throws {
        let isolatedBrains = TheBrains(tripwire: TheTripwire())
        defer { isolatedBrains.stopSemanticObservation() }
        let beforeScreen = InterfaceObservation.makeForTests(elements: [
            (makeElement(label: "Known"), "known"),
        ])
        let step = try resolvedWait(WaitStep(
                predicate: .exists(.label("Missing")),
                timeout: 0.05
        ))
        let receiptTask = Task { @MainActor in
            await isolatedBrains.interactionObservation.waitForPredicate(step)
        }
        await waitForSettledSemanticWaiter(on: isolatedBrains.stash)
        _ = isolatedBrains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(beforeScreen)

        let receipt = await receiptTask.value

        XCTAssertFalse(receipt.actionResult.outcome.isSuccess)
        XCTAssertEqual(receipt.actionResult.outcome.errorKind, .timeout)
        XCTAssertTrue(receipt.actionResult.message?.contains("interface: 1 elements") == true)
        XCTAssertTrue(receipt.actionResult.message?.contains("last result:") == true)
    }

    func testHeistActionExpectationRequiresWaitObservationEvidence() async throws {
        let baselineEvent = brains.stash.semanticObservationStream.commitDiscoveryObservationForTesting(
            .makeForTests()
        )
        let baseline = try XCTUnwrap(baselineEvent.settledCapture)
        let expectation = WaitStep(
            predicate: .changed(.elements()),
            timeout: 0
        )
        var waitRequests: [TheBrains.HeistRuntimeWaitRequest] = []
        var baselineScopes: [SemanticObservationScope?] = []
        let runtime = heistRuntime(
            observations: [],
            executionBaseline: baseline,
            execute: { _ in
                ActionResult.success(method: .activate, evidence: .none)
            },
            wait: { request in
                waitRequests.append(request)
                return ActionResult.success(method: .wait, evidence: .none)
            },
            executionBaselineScopes: { scope in
                baselineScopes.append(scope)
            }
        )
        let plan = try HeistPlan(body: [
            .action(try ActionStep(
                command: .activate(.label("Submit")),
                expectationPolicy: .expect(try ActionExpectation(expectation)))),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(baselineScopes.first, .discovery)
        XCTAssertEqual(waitRequests.count, 1)
        if case .actionEndpoint(
            let request,
            trace: nil,
            baseline: baseline
        )? = waitRequests.first {
            XCTAssertEqual(request, try resolvedWait(expectation))
        } else {
            XCTFail("Expected action endpoint wait request")
        }
        XCTAssertEqual(step.actionEvidence?.expectationResult?.method, .wait)
        XCTAssertEqual(step.reportExpectation?.met, false)
        XCTAssertEqual(step.reportExpectation?.actual, "no observed accessibility trace")
    }

    func testTemporalActionExpectationCarriesUnavailableBaselineWithoutReplacement() async throws {
        let expectation = WaitStep(predicate: .changed(.elements()), timeout: 1)
        var waitRequests: [TheBrains.HeistRuntimeWaitRequest] = []
        var baselineScopes: [SemanticObservationScope?] = []
        let runtime = heistRuntime(
            observations: [],
            execute: { _ in
                ActionResult.success(method: .activate, evidence: .none)
            },
            wait: { request in
                waitRequests.append(request)
                return ActionResult.success(method: .wait, evidence: .none)
            },
            executionBaselineScopes: { scope in
                baselineScopes.append(scope)
            }
        )
        let plan = try HeistPlan(body: [
            .action(try ActionStep(
                command: .activate(.label("Submit")),
                expectationPolicy: .expect(try ActionExpectation(expectation)))),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let step = try XCTUnwrap(result.heistExecutionPayload?.steps.first)

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(baselineScopes.first, .discovery)
        XCTAssertEqual(waitRequests.count, 1)
        guard case .actionEndpoint(_, trace: nil, baseline: nil)? = waitRequests.first else {
            return XCTFail("Expected action endpoint wait with unavailable baseline")
        }
        XCTAssertEqual(
            step.reportExpectation?.actual,
            "no observed accessibility trace"
        )
    }

    func testActionExpectationSettlesWithDiscoveryScope() async throws {
        let observedReady = observedState(labels: ["Long List"])
        let target = AccessibilityTarget.identifier("target")
        var observedScopes: [SemanticObservationScope] = []
        var baselineScopes: [SemanticObservationScope?] = []
        let runtime = heistRuntime(
            observations: [observedReady],
            execute: { _ in
                ActionResult.success(method: .activate, evidence: .none)
            },
            observedScopes: { scope in
                observedScopes.append(scope)
            },
            executionBaselineScopes: { scope in
                baselineScopes.append(scope)
            }
        )
        let plan = try HeistPlan(body: [
            .action(try ActionStep(
                command: .activate(target),
                expectationPolicy: .expect(ActionExpectation(
                    predicate: .exists(.label("Long List")),
                    timeout: 0.01
                )))),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "heist failed")
        XCTAssertEqual(baselineScopes, [nil])
        XCTAssertEqual(observedScopes, [.discovery])
    }

    func testHeistRuntimeSafetyRejectsInvalidPlanBeforeDispatchOrObservation() async throws {
        let raw = HeistPlanAdmissionCandidate(body: [
            .action(try ActionStep(command: .activate(.ref("missing")))),
        ])

        XCTAssertThrowsError(try raw.validatedForRuntimeSafety()) { error in
            XCTAssertTrue(String(describing: error).contains("$.body[0].action.command.payload.target"))
            XCTAssertTrue(String(describing: error).contains("target ref must resolve"))
        }
    }

    func testHeistRuntimeSafetyRejectsInvalidStringLoopBeforeDispatch() async throws {
        let raw = HeistPlanAdmissionCandidate(body: [
            .forEachString(try ForEachStringStep(
                values: [""],
                parameter: "item",
                body: [
                    .action(try ActionStep(command: .typeText(
                        reference: "item",
                        target: .predicate(.label("Search"))
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
        var executedCommands: [ResolvedHeistActionCommand] = []
        let runtime = heistRuntime(
            observations: [],
            execute: { command in
                executedCommands.append(command)
                return ActionResult.success(method: .activate, evidence: .none)
            }
        )
        let plan = try HeistPlanAdmissionCandidate(definitions: [
            HeistPlanAdmissionCandidate(
                name: "addToCart",
                parameter: .string(name: "item"),
                definitions: [
                    HeistPlanAdmissionCandidate(name: "tapAddButton", body: [
                        .action(try ActionStep(
                            command: .activate(.label("Add to Cart"))
                        )),
                    ]),
                ],
                body: [
                    .action(try ActionStep(command: .activate(.label(
                        HeistReferenceName(stringLiteral: "item")
                    )))),
                    .invoke(HeistInvocationStep(path: ["tapAddButton"])),
                ]
            ),
        ], body: [
            .invoke(HeistInvocationStep(
                path: ["addToCart"],
                argument: .string("Milk")
            )),
        ]).validatedForRuntimeSafety()

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertTrue(result.outcome.isSuccess)
        let expectedCommands = try ["Milk", "Add to Cart"].map {
            try HeistActionCommand.activate(.label($0)).resolve(in: .empty)
        }
        XCTAssertEqual(executedCommands, expectedCommands)
    }

    func testHeistInvocationExpectationReturnsEvidenceOnInvokeNode() async throws {
        var executedCommands: [ResolvedHeistActionCommand] = []
        let expectation = WaitStep(
            predicate: .changed(.elements([.appeared(.label("subtotal"))])),
            timeout: defaultActionExpectationTimeout
        )
        let runtime = heistRuntime(
            observations: [
                observedState(labels: ["Search"]),
                observedState(labels: ["Search", "subtotal"]),
            ],
            execute: { command in
                executedCommands.append(command)
                return ActionResult.success(method: .activate, evidence: .none)
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
                                .action(try ActionStep(command: .activate(.label(
                                    HeistReferenceName(stringLiteral: "item")
                                )))),
                            ]
                        ),
                    ],
                    body: []
                ),
            ],
            body: [
                .invoke(HeistInvocationStep(
                    path: ["Cart", "addItem"],
                    argument: .string("Milk"),
                    expectation: expectation
                )),
            ]
        )

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(
            executedCommands,
            [try HeistActionCommand.activate(.label("Milk")).resolve(in: .empty)]
        )
        XCTAssertEqual(heist.expectationsChecked, 1)
        XCTAssertEqual(heist.expectationsMet, 1)
        XCTAssertEqual(step.kind, .invoke)
        XCTAssertEqual(step.invocationEvidence?.expectationActionResult?.method, .wait)
        XCTAssertEqual(step.invocationEvidence?.expectationActionResult?.outcome.isSuccess, true)
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
                ActionResult.success(method: .activate, evidence: .none)
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

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(step.kind, .invoke)
        XCTAssertEqual(step.invocationEvidence?.expectation?.met, true)
        XCTAssertEqual(step.invocationEvidence?.expectationActionResult?.outcome.isSuccess, true)
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
                ActionResult.success(method: .activate, evidence: .none)
            }
        )
        let plan = try HeistPlan(
            definitions: [
                try HeistPlan(name: "Cart", definitions: [
                    try HeistPlan(
                        name: "addItem",
                        parameter: .string(name: "item"),
                        body: [
                            .action(try ActionStep(command: .activate(.label(
                                HeistReferenceName(stringLiteral: "item")
                            )))),
                        ]
                    ),
                ], body: []),
            ],
            body: [
                .invoke(HeistInvocationStep(
                    path: ["Cart", "addItem"],
                    argument: .string("Eggs"),
                    expectation: WaitStep(
                        predicate: .changed(.elements([.updated(
                            .label("subtotal"),
                            .value(after: .contains("2 items"))
                        )])),
                        timeout: defaultActionExpectationTimeout
                    )
                )),
            ]
        )

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(step.kind, .invoke)
        XCTAssertEqual(step.invocationEvidence?.expectation?.met, true)
        XCTAssertEqual(step.invocationEvidence?.expectationActionResult?.outcome.isSuccess, true)
    }

    func testHeistInvocationScreenChangeExpectationEvaluatesAcrossNestedCall() async throws {
        let runtime = heistRuntime(
            observations: [
                observedState(labels: ["Checkout"], screenId: "checkout"),
                observedState(labels: ["Receipt"], screenId: "receipt", screenChanged: true),
            ],
            execute: { _ in
                ActionResult.success(method: .activate, evidence: .none)
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
                        predicate: .changed(.screen([.exists(.label("Receipt"))])),
                        timeout: defaultActionExpectationTimeout
                    )
                )),
            ]
        )

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(step.kind, .invoke)
        XCTAssertEqual(step.invocationEvidence?.expectation?.met, true)
        XCTAssertEqual(step.invocationEvidence?.expectationActionResult?.outcome.isSuccess, true)
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
                ActionResult.success(method: .activate, evidence: .none)
            }
        )
        let plan = try HeistPlan(
            definitions: [
                try HeistPlan(name: "Cart", definitions: [
                    try HeistPlan(
                        name: "addItem",
                        parameter: .string(name: "item"),
                        body: [
                            .action(try ActionStep(command: .activate(.label(
                                HeistReferenceName(stringLiteral: "item")
                            )))),
                        ]
                    ),
                ], body: []),
            ],
            body: [
                .invoke(HeistInvocationStep(
                    path: ["Cart", "addItem"],
                    argument: .string("Eggs"),
                    expectation: WaitStep(
                        predicate: .changed(.elements([.updated(
                            .label("subtotal"),
                            .value(after: .contains("2 items"))
                        )])),
                        timeout: defaultActionExpectationTimeout
                    )
                )),
            ]
        )

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(heist.abortedAtPath, "$.body[0]")
        XCTAssertEqual(step.kind, .invoke)
        XCTAssertEqual(step.status, .failed)
        XCTAssertNil(step.abortedAtChildPath)
        XCTAssertEqual(step.failure?.category, .expectation)
        XCTAssertEqual(step.invocationEvidence?.expectation?.met, false)
        XCTAssertEqual(step.invocationEvidence?.expectationActionResult?.outcome.isSuccess, false)
        XCTAssertTrue(step.children.allSatisfy { $0.status == .passed })
    }

    func testHeistInvocationExecutesQualifiedExportedNamespaceDependency() async throws {
        var executedCommands: [ResolvedHeistActionCommand] = []
        let runtime = heistRuntime(
            observations: [],
            execute: { command in
                executedCommands.append(command)
                return ActionResult.success(method: .activate, evidence: .none)
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

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(
            executedCommands,
            [try HeistActionCommand.activate(.label("Pay")).resolve(in: .empty)]
        )
    }

    func testHeistExecutionBindsRootStringArgument() async throws {
        var executedCommands: [ResolvedHeistActionCommand] = []
        let runtime = heistRuntime(
            observations: [],
            execute: { command in
                executedCommands.append(command)
                return ActionResult.success(method: .typeText, evidence: .none)
            }
        )
        let plan = try HeistPlan(
            name: "search",
            parameter: .string(name: "query"),
            body: [
                .action(try ActionStep(command: .typeText(
                    reference: "query",
                    target: .predicate(.label("Search"))
                ))),
            ]
        )

        let result = await brains.executeHeistPlanForTest(
            plan,
            argument: .string("milk"),
            runtime: runtime
        )

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(
            executedCommands,
            [try HeistActionCommand.typeText(text: "milk", target: .label("Search")).resolve(in: .empty)]
        )
    }

    func testHeistExecutionBindsRootAccessibilityTargetArgument() async throws {
        var executedCommands: [ResolvedHeistActionCommand] = []
        let runtime = heistRuntime(
            observations: [],
            execute: { command in
                executedCommands.append(command)
                return ActionResult.success(method: .activate, evidence: .none)
            }
        )
        let plan = try HeistPlan(
            name: "tapRow",
            parameter: .accessibilityTarget(name: "row"),
            body: [
                .action(try ActionStep(command: .activate(.ref("row")))),
            ]
        )

        let result = await brains.executeHeistPlanForTest(
            plan,
            argument: .accessibilityTarget(.label("Row 1")),
            runtime: runtime
        )

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(
            executedCommands,
            [try HeistActionCommand.activate(.label("Row 1")).resolve(in: .empty)]
        )
    }

    func testHeistExecutionRejectsMissingRootArgument() async throws {
        let runtime = heistRuntime(observations: [])
        let plan = try HeistPlan(
            name: "search",
            parameter: .string(name: "query"),
            body: [
                .action(try ActionStep(command: .typeText(
                    reference: "query",
                    target: .predicate(.label("Search"))
                ))),
            ]
        )

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.outcome.errorKind, .validationError)
        XCTAssertEqual(result.message, "Could not bind root heist argument: heist argument type none does not match parameter type string")
    }

    func testHeistInvocationAllowsSameLeafDefinitionNamesInDifferentScopes() async throws {
        var executedCommands: [ResolvedHeistActionCommand] = []
        let runtime = heistRuntime(
            observations: [],
            execute: { command in
                executedCommands.append(command)
                return ActionResult.success(method: .activate, evidence: .none)
            }
        )
        let plan = try HeistPlan(definitions: [
            try HeistPlan(
                name: "setup",
                definitions: [
                    try HeistPlan(name: "setup", body: [
                        .action(try ActionStep(command: .activate(.predicate(.label("Nested Setup"))))),
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

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(
            executedCommands,
            [try HeistActionCommand.activate(.label("Nested Setup")).resolve(in: .empty)]
        )
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
            context: AccessibilityTrace.Context(screenId: "buttons_actions"),
            transition: AccessibilityTrace.Transition(accessibilityNotifications: [
                AccessibilityNotificationEvidence(
                    sequence: 1,
                    kind: .screenChanged,
                    timestamp: Date(timeIntervalSince1970: 0),
                    notificationData: .none,
                    associatedElement: .none
                ),
            ])
        )
        let trace = AccessibilityTrace(captures: [beforeCapture, afterCapture])
        XCTAssertEqual(
            trace.changeFacts.map(\.kind),
            [.elementsChanged, .screenChanged, .elementsChanged]
        )
        let runtime = heistRuntime(
            observations: [],
            execute: { _ in
                ActionResult.success(
                    method: .activate,
                    evidence: ActionResultSuccessEvidence(observation: .settledTrace(
                        makeTestTraceEvidence(trace, completeness: .incomplete),
                        .settled(durationMs: 7)
                    ))
                )
            }
        )
        let plan = try HeistPlan(body: [
            .action(try ActionStep(
                command: .activate(.label("Controls Demo")),
                expectationPolicy: .expect(try ActionExpectation(expectation)))),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(step.actionEvidence?.dispatchResult?.settled, true)
        XCTAssertEqual(step.actionEvidence?.dispatchResult?.settleTimeMs, 7)
        XCTAssertEqual(step.actionEvidence?.dispatchResult?.accessibilityTrace, trace)
        XCTAssertEqual(step.actionEvidence?.expectationResult?.method, .wait)
        XCTAssertTrue(step.actionEvidence?.expectationResult?.outcome.isSuccess == true)
        XCTAssertEqual(step.actionEvidence?.expectationResult?.accessibilityTrace, trace)
        XCTAssertEqual(step.reportExpectation?.met, true)
        XCTAssertNil(step.reportExpectation?.actual)
    }

    func testHeistActionExpectationTimeoutZeroRejectsUnsettledActionTrace() async throws {
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
            context: AccessibilityTrace.Context(screenId: "buttons_actions"),
            transition: AccessibilityTrace.Transition(accessibilityNotifications: [
                AccessibilityNotificationEvidence(
                    sequence: 1,
                    kind: .screenChanged,
                    timestamp: Date(timeIntervalSince1970: 0),
                    notificationData: .none,
                    associatedElement: .none
                ),
            ])
        )
        let trace = AccessibilityTrace(captures: [beforeCapture, afterCapture])
        let runtime = heistRuntime(
            observations: [afterState],
            execute: { _ in
                ActionResult.success(
                    method: .activate,
                    evidence: ActionResultSuccessEvidence(observation: .settledTrace(
                        makeTestTraceEvidence(trace, completeness: .incomplete),
                        .timedOut(durationMs: 7)
                    ))
                )
            }
        )
        let plan = try HeistPlan(body: [
            .action(try ActionStep(
                command: .activate(.label("Controls Demo")),
                expectationPolicy: .expect(try ActionExpectation(expectation)))),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(step.actionEvidence?.dispatchResult?.settled, false)
        XCTAssertFalse(step.actionEvidence?.expectationResult?.outcome.isSuccess == true)
        XCTAssertEqual(step.reportExpectation?.met, false)
    }

    func testHeistActionExpectationUsesWaitFailureDiagnostic() async throws {
        let expectation = WaitStep(
            predicate: .missing(.label("Loading")),
            timeout: 0.2
        )
        let runtime = heistRuntime(
            observations: [],
            execute: { _ in
                ActionResult.success(method: .activate, evidence: .none)
            },
            wait: { _ in
                ActionResult.failure(
                    method: .wait,
                    errorKind: .timeout,
                    message: "timed out after 0.2s — expectation not met",
                    evidence: ActionResultFailureEvidence(
                        observation: .trace(makeTestTraceEvidence(
                            .noChangeForTests(elementCount: 1),
                            completeness: .incomplete
                        ))
                    )
                )
            }
        )
        let plan = try HeistPlan(body: [
            .action(try ActionStep(
                command: .activate(.label("Submit")),
                expectationPolicy: .expect(try ActionExpectation(expectation)))),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let step = try XCTUnwrap(heist.steps.first)

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(step.actionEvidence?.expectationResult?.outcome.errorKind, .timeout)
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
                return ActionResult.success(method: .activate, evidence: .none)
            },
            observedScopes: { _ in
                demandDuringObservation = self.brains.stash.semanticObservationStream.hasActiveObservationDemand
            }
        )
        let plan = try HeistPlan(body: [
            .action(try ActionStep(command: .activate(.label("Submit")))),
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
                return ActionResult.success(method: .activate, evidence: .none)
            }
        )
        let plan = try HeistPlan(body: [
            .action(try ActionStep(command: .activate(.label("1")))),
            .action(try ActionStep(command: .activate(.label("2")))),
            .action(try ActionStep(command: .activate(.label("3")))),
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

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(
            step.caseSelectionEvidence?.selection.outcome,
            HeistCaseSelectionOutcome.elseBranch(reason: .noMatch)
        )
        XCTAssertEqual(step.caseSelectionEvidence?.selection.cases.first?.result.met, false)
    }

    func testHeistForEachWithZeroMatchesSucceedsWithoutIterations() async throws {
        let matching = ElementPredicateTemplate.label("Delete")
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

        XCTAssertTrue(result.outcome.isSuccess)
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

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(heist.abortedAtPath, failedChildPath)
        XCTAssertEqual(heist.steps.map(\.kind), [.forEachString, .warn, .action])
        XCTAssertEqual(heist.steps.map(\.status), [.failed, .skipped, .passed])
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
        let matching = ElementPredicateTemplate.label("Delete")
        var executedCommands: [ResolvedHeistActionCommand] = []
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
                    return ActionResult.success(method: .takeScreenshot, evidence: .none)
                }
                return ActionResult.success(method: .activate, evidence: .none)
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

        XCTAssertFalse(result.outcome.isSuccess)
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
        let matching = ElementPredicateTemplate.label("Delete")
        var executedCommands: [ResolvedHeistActionCommand] = []
        let initialState = observedState(elements: [
            (makeElement(label: "Delete", identifier: "delete_first"), "delete_first"),
            (makeElement(label: "Delete", identifier: "delete_second"), "delete_second"),
            (makeElement(label: "Delete", identifier: "delete_third"), "delete_third"),
        ])
        let runtime = heistRuntime(
            observations: [initialState, initialState, initialState],
            execute: { command in
                executedCommands.append(command)
                return ActionResult.success(method: .activate, evidence: .none)
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

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(forEachResult.matchedCount, 3)
        XCTAssertEqual(forEachResult.iterationCount, 3)
        let expectedCommands = try (0...2).map {
            try HeistActionCommand.activate(.target(matching, ordinal: $0)).resolve(in: .empty)
        }
        XCTAssertEqual(executedCommands, expectedCommands)
        XCTAssertEqual(step.children.map(\.kind), [.forEachIteration, .forEachIteration, .forEachIteration])
        XCTAssertEqual(step.children.flatMap(\.children).map(\.kind), [.action, .action, .action])
        XCTAssertEqual(plan.body, originalBody)
    }

    func testHeistForEachPreservesCallerPredicateInsteadOfMinimumMatchers() async throws {
        let matching = ElementPredicateTemplate(label: "Delete", traits: [.button])
        var executedCommands: [ResolvedHeistActionCommand] = []
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
                return ActionResult.success(method: .activate, evidence: .none)
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

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(forEachResult.iterationCount, 2)
        let expectedCommands = try (0...1).map {
            try HeistActionCommand.activate(.target(matching, ordinal: $0)).resolve(in: .empty)
        }
        XCTAssertEqual(executedCommands, expectedCommands)
    }

    func testHeistForEachResetsOrdinalWhenMatchedCollectionIdentityChanges() async throws {
        let matching = ElementPredicateTemplate.label("Delete")
        var executedCommands: [ResolvedHeistActionCommand] = []
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
                return ActionResult.success(method: .activate, evidence: .none)
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

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(forEachResult.matchedCount, 2)
        XCTAssertEqual(forEachResult.iterationCount, 2)
        XCTAssertNil(forEachResult.failureReason)
        let expectedCommand = try HeistActionCommand.activate(.target(matching, ordinal: 0)).resolve(in: .empty)
        XCTAssertEqual(executedCommands, [expectedCommand, expectedCommand])
    }

    func testHeistForEachAdditionResetsOrdinalWithoutExtendingInitialIterationBudget() async throws {
        let matching = ElementPredicateTemplate.label("Delete")
        var executedCommands: [ResolvedHeistActionCommand] = []
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
                return ActionResult.success(method: .activate, evidence: .none)
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

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(forEachResult.matchedCount, 2)
        XCTAssertEqual(forEachResult.iterationCount, 2)
        let expectedCommand = try HeistActionCommand.activate(.target(matching, ordinal: 0)).resolve(in: .empty)
        XCTAssertEqual(executedCommands, [expectedCommand, expectedCommand])
    }

    func testHeistForEachDoesNotResetOrdinalForStateOnlyMatchMutation() async throws {
        let matching = ElementPredicateTemplate.label("Delete")
        var executedCommands: [ResolvedHeistActionCommand] = []
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
                return ActionResult.success(method: .activate, evidence: .none)
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

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(forEachResult.matchedCount, 2)
        XCTAssertEqual(forEachResult.iterationCount, 2)
        let expectedCommands = try (0...1).map {
            try HeistActionCommand.activate(.target(matching, ordinal: $0)).resolve(in: .empty)
        }
        XCTAssertEqual(executedCommands, expectedCommands)
    }

    func testHeistForEachBodyFailureStopsBeforeFollowingTopLevelSteps() async throws {
        let matching = ElementPredicateTemplate.label("Delete")
        let initialState = observedState(elements: [
            (makeElement(label: "Delete", identifier: "delete_first"), "delete_first"),
            (makeElement(label: "Delete", identifier: "delete_second"), "delete_second"),
        ])
        let runtime = heistRuntime(
            observations: [initialState],
            execute: { _ in
                ActionResult.failure(
                    method: .activate,
                    errorKind: .actionFailed,
                    message: "activate failed",
                    evidence: .none
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

        XCTAssertFalse(result.outcome.isSuccess)
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
        let matching = ElementPredicateTemplate.label("Delete")
        var executedCommands: [ResolvedHeistActionCommand] = []
        var waitedSteps: [ResolvedWaitRuntimeInput] = []
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
                return ActionResult.success(
                    method: .activate,
                    evidence: ActionResultSuccessEvidence(
                        observation: .trace(makeTestTraceEvidence(
                            AccessibilityTrace(capture: stillPresentState.capture),
                            completeness: .incomplete
                        ))
                    )
                )
            },
            wait: { request in
                waitedSteps.append(request.step)
                return ActionResult.success(
                    method: .wait,
                    evidence: ActionResultSuccessEvidence(
                        observation: .trace(makeTestTraceEvidence(
                            AccessibilityTrace(capture: waitObservedState.capture),
                            completeness: .incomplete
                        ))
                    )
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
                        expectationPolicy: .expect(ActionExpectation(
                            predicate: .missing(.ref("target")),
                            timeout: 2
                        )))),
                ]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let forEachResult = try XCTUnwrap(heist.steps.first?.forEachElementEvidence)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(forEachResult.iterationCount, 2)
        let expectedCommand = try HeistActionCommand.activate(.target(matching, ordinal: 0)).resolve(in: .empty)
        let authoredExpectation = AccessibilityPredicate.missing(.ref("target"))
        let resolvedExpectation = try resolvedPredicate(.missing(.predicate(matching, ordinal: 0)))
        XCTAssertEqual(executedCommands.first, expectedCommand)
        XCTAssertEqual(waitedSteps.first?.predicateExpression, authoredExpectation)
        XCTAssertEqual(waitedSteps.first?.predicate, resolvedExpectation)
        XCTAssertEqual(executedCommands.last, expectedCommand)
        XCTAssertEqual(waitedSteps.last?.predicateExpression, authoredExpectation)
        XCTAssertEqual(waitedSteps.last?.predicate, resolvedExpectation)
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
        let resolved = brains.stash.resolveTarget(target).resolved
        let liveTarget: TheStash.LiveActionTarget?
        if let resolved,
           case .resolved(let target) = brains.stash.resolveLiveActionTarget(for: resolved) {
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
        guard let committedTarget = brains.stash.resolveTarget(target).resolved else {
            XCTFail("Expected committed semantic target to resolve")
            return
        }
        guard case .objectUnavailable = brains.stash.resolveLiveActionTarget(for: committedTarget) else {
            XCTFail("Expected the settled UIKit evidence to be held weakly")
            return
        }
        brains.stash.nextVisibleRefreshScreenForTesting = .makeForTests(
            elements: [(refreshedElement, heistId)],
            objects: [heistId: replacementObject]
        )

        let result = await brains.actions.executeIncrement(target)

        XCTAssertTrue(result.success, result.message ?? "increment failed")
        XCTAssertEqual(result.method, .increment)
        XCTAssertEqual(committedTarget.heistId, heistId)
        XCTAssertEqual(result.subjectEvidence?.element.identifier, heistId.rawValue)
        XCTAssertEqual(replacementObject.incrementCount, 1)
        XCTAssertEqual(brains.stash.interfaceElement(heistId: heistId)?.element.bhFrame, settledElement.bhFrame)
        guard case .resolved(let liveTarget) = brains.stash.resolveLiveActionTarget(for: committedTarget) else {
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
        brains.stash.nextVisibleRefreshScreenForTesting = .makeForTests(
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

        await waitForSettledSemanticWaiter(on: brains.stash)
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
        _ = brains.stash.semanticObservationStream.commitVisibleObservationForTesting(reorderedScreen)
        brains.stash.nextVisibleRefreshScreenForTesting = reorderedScreen

        let result = await actionTask.value

        XCTAssertTrue(result.success, result.message ?? "activate failed")
        XCTAssertEqual(result.resolvedElementId, selectedId)
        XCTAssertEqual(selectedObject.activationCount, 1)
        XCTAssertEqual(otherObject.activationCount, 0)
    }

    func testExecuteTypeTextIntoTargetFocusesWithAccessibilityActivateBeforeTyping() async throws {
        brains.tripwire.startPulse()
        let rootView = UIView(frame: UIScreen.main.bounds)
        rootView.backgroundColor = .white

        let textField = ActionActivatingTextField(frame: CGRect(x: 48, y: 180, width: 240, height: 44))
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

        let heistId: HeistId = "message_field"
        let element = AccessibilityElement.make(
            label: "Message",
            identifier: heistId.rawValue,
            traits: .textEntry,
            frame: textField.frame
        )
        let staleTextField = ActionActivatingTextField()
        installScreen(elements: [(element, heistId)], objects: [heistId: staleTextField])
        brains.stash.nextVisibleRefreshScreenForTesting = .makeForTests(
            elements: [(element, heistId)],
            objects: [heistId: textField]
        )

        XCTAssertFalse(textField.isFirstResponder)

        let command = try HeistActionCommand.typeText(
            text: "hello",
            target: .identifier("message_field")
        ).resolve(in: .empty)
        let result = await brains.executeRuntimeAction(command)

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "type_text failed")
        XCTAssertEqual(result.method, .typeText)
        XCTAssertEqual(result.subjectEvidence?.element.identifier, heistId.rawValue)
        XCTAssertEqual(staleTextField.activationCount, 0)
        XCTAssertEqual(textField.activationCount, 1)
        XCTAssertTrue(textField.isFirstResponder)
        XCTAssertEqual(textField.text, "hello")
    }

    func testExecuteTypeTextKeepsCommittedHeistIdWhenOrdinalOrderChangesBeforeFocus() async throws {
        brains.stopSemanticObservation()
        let selectedId: HeistId = "selected_message"
        let otherId: HeistId = "other_message"
        let selectedTextField = ActionActivatingTextField(
            frame: CGRect(x: 48, y: 180, width: 240, height: 44)
        )
        let otherTextField = ActionActivatingTextField(
            frame: CGRect(x: 48, y: 240, width: 240, height: 44)
        )
        let rootView = UIView(frame: UIScreen.main.bounds)
        rootView.backgroundColor = .white
        for (textField, identifier) in [(selectedTextField, selectedId), (otherTextField, otherId)] {
            textField.isAccessibilityElement = true
            textField.accessibilityLabel = "Repeated Message"
            textField.accessibilityIdentifier = identifier.rawValue
            rootView.addSubview(textField)
        }
        let window = try installModalWindow(rootView: rootView)
        defer {
            window.rootViewController?.view.accessibilityViewIsModal = false
            window.isHidden = true
        }

        let selectedElement = AccessibilityElement.make(
            label: "Repeated Message",
            identifier: selectedId.rawValue,
            traits: .textEntry,
            frame: selectedTextField.frame
        )
        let otherElement = AccessibilityElement.make(
            label: "Repeated Message",
            identifier: otherId.rawValue,
            traits: .textEntry,
            frame: otherTextField.frame
        )
        installScreen(elements: [
            (selectedElement, selectedId),
            (otherElement, otherId),
        ])
        let keyboardImpl = ActionTextInputKeyboardImpl(textField: selectedTextField) {}
        brains.safecracker.keyboardBridgeProvider = { keyboardImpl.bridge() }

        let resolvedTarget = try AccessibilityTarget.target(
            .label("Repeated Message"),
            ordinal: 0
        ).resolve(in: .empty)
        let actionTask = Task { @MainActor in
            await brains.actions.executeTypeText(
                text: "hello",
                target: resolvedTarget,
                replacingExisting: false
            )
        }

        await waitForSettledSemanticWaiter(on: brains.stash)
        let reorderedScreen = InterfaceObservation.makeForTests(
            elements: [
                (otherElement, otherId),
                (selectedElement, selectedId),
            ],
            objects: [
                selectedId: selectedTextField,
                otherId: otherTextField,
            ]
        )
        _ = brains.stash.semanticObservationStream.commitVisibleObservationForTesting(reorderedScreen)
        brains.stash.nextVisibleRefreshScreenForTesting = reorderedScreen

        let result = await actionTask.value

        XCTAssertTrue(result.success, result.message ?? "type_text failed")
        XCTAssertEqual(result.resolvedElementId, selectedId)
        XCTAssertEqual(selectedTextField.activationCount, 1)
        XCTAssertEqual(otherTextField.activationCount, 0)
        XCTAssertEqual(selectedTextField.text, "hello")
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

        let command = try HeistActionCommand.typeText(
            text: "hello",
            target: .identifier("message_field")
        ).resolve(in: .empty)
        let result = await brains.executeRuntimeAction(command)

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "type_text failed")
        XCTAssertEqual(result.method, .typeText)
        let subjectEvidence = try XCTUnwrap(result.subjectEvidence)
        XCTAssertEqual(subjectEvidence.source, .textInputTarget)
        XCTAssertEqual(subjectEvidence.element.identifier, "message_field")
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

        let command = try HeistActionCommand.typeText(
            text: "b",
            target: .identifier("message_field"),
            replacingExisting: true
        ).resolve(in: .empty)
        let result = await brains.executeRuntimeAction(command)

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "type_text replacement failed")
        XCTAssertEqual(result.method, .typeText)
        XCTAssertEqual(result.subjectEvidence?.element.identifier, "message_field")
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

        let command = try HeistActionCommand.typeText(
            text: "",
            target: .identifier("message_field"),
            replacingExisting: true
        ).resolve(in: .empty)
        let result = await brains.executeRuntimeAction(command)

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "type_text clear failed")
        XCTAssertEqual(result.method, .typeText)
        XCTAssertEqual(result.subjectEvidence?.element.identifier, "message_field")
        XCTAssertEqual(textField.text, "")
        guard case .value(let value) = result.payload else {
            XCTFail("Expected final text value payload, got \(String(describing: result.payload))")
            return
        }
        XCTAssertEqual(value, "")
    }

    func testExecuteTypeTextWithoutActiveInputReportsFocusState() async {
        _ = brains.safecracker.resignFirstResponder()

        let result = await brains.actions.executeTypeText(
            text: "hello",
            target: nil,
            replacingExisting: false
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .typeText)
        XCTAssertNil(result.subjectEvidence)
        XCTAssertNil(result.resolvedElementId)
        XCTAssertDiagnostic(result.message, contains: [
            "text entry failed",
            "focus=none",
            "keyboardVisible=false",
            "activeTextInput=false",
            "try provide target for a text field",
        ])
    }

    func testExecuteTypeTextReportsKeyboardInjectionFailure() async {
        let keyboardImpl = KeyboardInjectionKeyboardImpl()
        brains.safecracker.keyboardBridgeProvider = { keyboardImpl.bridge(missingSelector: "addInputString:") }

        let result = await brains.actions.executeTypeText(
            text: "hello",
            target: nil,
            replacingExisting: false
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .typeText)
        XCTAssertDiagnostic(result.message, contains: [
            "UIKeyboardImplTextInjection failed",
            "missing selector addInputString:",
            "while typing \"h\"",
        ])
        XCTAssertTrue(keyboardImpl.inputStrings.isEmpty)
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
        XCTAssertNil(result.subjectEvidence)
        XCTAssertNil(result.resolvedElementId)
        XCTAssertDiagnostic(result.message, contains: [
            "resign first responder failed",
            "focus=none",
            "keyboardVisible=false",
            "activeTextInput=false",
            "try focus a text input before dismissing the keyboard",
        ])
    }

    func testExecuteResignFirstResponderUsesReplacementObjectForCommittedHeistId() async throws {
        let rootView = UIView(frame: UIScreen.main.bounds)
        rootView.backgroundColor = .white
        let replacementTextField = ResignationTrackingTextField(
            frame: CGRect(x: 48, y: 180, width: 240, height: 44)
        )
        replacementTextField.isAccessibilityElement = true
        replacementTextField.accessibilityLabel = "Message"
        replacementTextField.accessibilityIdentifier = "message_field"
        rootView.addSubview(replacementTextField)

        let window = try installModalWindow(rootView: rootView)
        defer {
            window.rootViewController?.view.accessibilityViewIsModal = false
            window.isHidden = true
        }
        XCTAssertTrue(replacementTextField.becomeFirstResponder())

        let heistId: HeistId = "message_field"
        let element = AccessibilityElement.make(
            label: "Message",
            identifier: heistId.rawValue,
            traits: .textEntry,
            frame: replacementTextField.frame
        )
        let staleTextField = ResignationTrackingTextField(frame: replacementTextField.frame)
        brains.stash.installScreenForTesting(.makeForTests(
            elements: [(element, heistId)],
            objects: [heistId: staleTextField],
            firstResponderHeistId: heistId
        ))
        brains.stash.nextVisibleRefreshScreenForTesting = .makeForTests(
            elements: [(element, heistId)],
            objects: [heistId: replacementTextField],
            firstResponderHeistId: heistId
        )

        let result = await brains.actions.executeResignFirstResponder()

        XCTAssertTrue(result.success, result.message ?? "resign first responder failed")
        XCTAssertEqual(result.method, .resignFirstResponder)
        XCTAssertEqual(staleTextField.resignationCount, 0)
        XCTAssertEqual(replacementTextField.resignationCount, 1)
        XCTAssertFalse(replacementTextField.isFirstResponder)
        XCTAssertEqual(brains.stash.interfaceTree.firstResponderHeistId, heistId)
    }

    func testExecuteTapOutsideWindowReportsGestureDispatchState() async throws {
        let result = await brains.actions.executeTap(
            try TapTarget(selection: .coordinate(ScreenPoint(x: -10_000, y: -10_000)))
                .resolve(in: .empty)
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .syntheticTap)
        XCTAssertDiagnostic(result.message, contains: [
            "syntheticTap failed",
            "point must be inside screen bounds",
            "observed (-10000, -10000)",
        ])
    }

    func testAccessibilityTargetedPointActionFailsWhenElementRemainsOffViewport() async throws {
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
            selection: .element(try AccessibilityTarget.label("Below Fold").resolve(in: .empty)),
            method: .syntheticTap
        ) { point in
            dispatchedPoint = point
            return true
        }

        XCTAssertFalse(result.success)
        XCTAssertNil(dispatchedPoint, "Off-viewport targets must not dispatch their stored activation point")
        XCTAssertDiagnostic(result.message, contains: [
            "element inflation failed [noRevealPath]",
            "off-viewport target \"Below Fold\"",
            "no scroll membership",
        ])
    }

    func testAccessibilityTargetedPointActionUsesAccessibilityCaptureActivationPoint() async throws {
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
            selection: .element(try AccessibilityTarget.label("Live").resolve(in: .empty)),
            method: .syntheticTap
        ) { point in
            dispatchedPoint = point
            return true
        }

        XCTAssertTrue(result.success)
        XCTAssertEqual(dispatchedPoint, capturePoint)
        XCTAssertNotEqual(dispatchedPoint, objectPoint)
    }

    func testElementUnitPointActionUsesElementFrameOverride() async throws {
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
                try AccessibilityTarget.label("Live").resolve(in: .empty),
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
            try DragTarget(
                start: .coordinate(ScreenPoint(x: 10, y: 10)),
                end: ScreenPoint(x: .infinity, y: 20),
                duration: GestureDuration(seconds: 0.01)
            ).resolve(in: .empty)
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .syntheticDrag)
        XCTAssertEqual(result.failureKind, .inputValidation)
        XCTAssertEqual(result.message, "syntheticDrag failed: endPoint must contain finite coordinates")
    }

    func testExecuteRotorWithoutCustomRotorsReportsNextStep() async throws {
        let heistId: HeistId = "plain_rotor_host"
        let liveObject = UIView()
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Plain rotor host", traits: .button),
            object: liveObject
        )

        let result = await brains.actions.executeRotor(
            selection: .named("Errors"),
            target: try AccessibilityTarget.label("Plain rotor host").resolve(in: .empty),
            direction: .next
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

    func testExecuteRotorDispatchesLiveRotorAction() async throws {
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
            selection: .named("Live Rotor"),
            target: try AccessibilityTarget.label("Rotor host").resolve(in: .empty),
            direction: .next
        )

        XCTAssertTrue(result.success, result.message ?? "rotor failed")
        XCTAssertEqual(result.method.rawValue, ActionMethod.rotor.rawValue)
        XCTAssertTrue(result.message?.contains("Rotor 'Live Rotor' found Rotor host") ?? false,
                      result.message ?? "missing rotor success message")
    }

    func testExecuteRotorUsesOnscreenAccessibilityGeometryAtViewportEdge() async throws {
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
            selection: .named("Live Rotor"),
            target: try AccessibilityTarget.identifier("edge_rotor_host").resolve(in: .empty),
            direction: .next
        )

        XCTAssertTrue(result.success, result.message ?? "rotor failed")
        XCTAssertEqual(result.method.rawValue, ActionMethod.rotor.rawValue)
        XCTAssertTrue(result.message?.contains("Rotor 'Live Rotor' found Edge Rotor Host") ?? false,
                      result.message ?? "missing rotor success message")
    }

    func testExecuteRotorDoesNotRequireHostActivationPointOnscreen() async throws {
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
            selection: .named("Live Rotor"),
            target: try AccessibilityTarget.identifier("offscreen_rotor_host").resolve(in: .empty),
            direction: .next
        )

        XCTAssertTrue(result.success, result.message ?? "rotor failed")
        XCTAssertEqual(result.method.rawValue, ActionMethod.rotor.rawValue)
        XCTAssertTrue(result.message?.contains("Rotor 'Live Rotor' found Offscreen Rotor Host") ?? false,
                      result.message ?? "missing rotor success message")
    }

    func testExecuteRotorScrollsViewportTowardResultActivationPoint() async throws {
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

        brains.stash.installScreenForTesting(InterfaceObservation.makeForTests(
            elements: [
                hostHeistId: InterfaceTree.Element(
                    heistId: hostHeistId,
                    scrollMembership: nil,
                    element: hostElement
                ),
                resultHeistId: InterfaceTree.Element(
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
            selection: .named("Live Rotor"),
            target: try AccessibilityTarget.identifier(hostHeistId.rawValue).resolve(in: .empty),
            direction: .next
        )

        XCTAssertTrue(result.success, result.message ?? "rotor failed")
        XCTAssertEqual(result.method.rawValue, ActionMethod.rotor.rawValue)
        XCTAssertGreaterThan(scrollView.contentOffset.y, 0)
        XCTAssertTrue(result.message?.contains("Rotor 'Live Rotor' found Rotor Result") ?? false,
                      result.message ?? "missing rotor success message")
    }

    func testExecuteRotorNotFoundReportsAvailableRotorsAndNextStep() async throws {
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
            selection: .named("Errors"),
            target: try AccessibilityTarget.label("Rotor host").resolve(in: .empty),
            direction: .next
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

    func testExecuteRotorDiagnosticsMergeLiveRotors() async throws {
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
            selection: .named("Errors"),
            target: try AccessibilityTarget.label("Rotor host").resolve(in: .empty),
            direction: .next
        )

        XCTAssertFalse(result.success)
        XCTAssertDiagnostic(result.message, contains: [
            "availableRotors=[\"Warnings\"]",
            "try use one of available rotors [\"Warnings\"]",
        ])
    }

    func testExecuteRotorDiagnosticsUseSystemRotorDisplayName() async throws {
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
            selection: .named("Errors"),
            target: try AccessibilityTarget.label("Rotor host").resolve(in: .empty),
            direction: .next
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

        XCTAssertEqual(brains.stash.interfaceTree, .empty)
    }

    // MARK: - Accessibility Tree Availability

    func testExecuteCommandWaitForFailsWhenAccessibilityTreeUnavailable() async throws {
        let step = WaitStep(predicate: .exists(.label("never")), timeout: 0)
        let resolvedStep = try resolvedWait(step)
        let result = await withNoTraversableWindows {
            await brains.performWait(step: resolvedStep)
        }

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.method, .wait)
        XCTAssertEqual(result.outcome.errorKind, .timeout)
        XCTAssertDiagnostic(result.message, contains: [
            "timed out after",
            "waiting for heist predicate",
            "expected: exists(target(predicate(label=\"never\")))",
            "last result: no settled semantic observation available",
            "last parsed: no accessibility tree",
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
        offViewport: [InterfaceObservation.OffViewportEntry]
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
        in screen: InterfaceObservation
    ) throws -> AccessibilityTarget {
        let treeElement = try XCTUnwrap(screen.orderedElements.first { $0.element.label == label })
        let elements = screen.orderedElements.map {
            PredicateSelectionSubjectElement(id: $0.heistId.predicateSelectionElementId, element: $0.element)
        }
        return try XCTUnwrap(
            MinimumPredicateSelector.minimumUniquePredicate(
                for: treeElement.heistId.predicateSelectionElementId,
                in: elements
            )
        ).target
    }

    private func assertSameInteraction(
        _ name: String,
        single singleResult: TheSafecracker.ActionDispatchOutcome,
        heist heistResult: TheSafecracker.ActionDispatchOutcome,
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
        XCTAssertEqual(heist.outcome.isSuccess, single.outcome.isSuccess, name, file: file, line: line)
        XCTAssertEqual(heist.method, single.method, name, file: file, line: line)
        if isPreDispatchMatcherFailure(single),
           isPreDispatchMatcherFailure(heist) {
            XCTAssertTrue(
                [.actionFailed, .elementNotFound].contains(single.outcome.errorKind),
                name,
                file: file,
                line: line
            )
            XCTAssertTrue(
                [.actionFailed, .elementNotFound].contains(heist.outcome.errorKind),
                name,
                file: file,
                line: line
            )
            return
        }
        XCTAssertEqual(heist.outcome.errorKind, single.outcome.errorKind, name, file: file, line: line)
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
            return
        }
        XCTAssertEqual(heist, single, name, file: file, line: line)
    }

    private func isPreDispatchMatcherFailure(_ result: ActionResult) -> Bool {
        guard result.outcome.isSuccess == false,
              [.actionFailed, .elementNotFound].contains(result.outcome.errorKind),
              let message = result.message
        else { return false }
        return message.contains("No match for:")
            || message.contains("Could not observe accessibility tree")
    }

    private func firstLine(_ message: String) -> Substring {
        message.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
    }

    private func heistStepResult(for step: HeistStep, label: String) async throws -> ActionResult {
        let result = await brains.executeHeistPlan(try HeistPlan(body: [step]))
        guard case .heistExecution(let heist) = result.payload,
              let stepResult = heist.steps.first,
              let actionResult = stepResult.reportActionResult else {
            XCTFail("Expected heist execution step result for \(label)")
            return result
        }
        return actionResult
    }

    private func observedState(
        labels: [String],
        screenId: String? = nil,
        screenChanged: Bool = false
    ) -> PostActionObservation.BeforeState {
        observedState(elements: labels.enumerated().map { index, label in
            (makeElement(label: label), HeistId(rawValue: "element_\(index)"))
        }, screenId: screenId, screenChanged: screenChanged)
    }

    private func waitForSettledSemanticWaiter(
        on stash: TheStash,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = CFAbsoluteTimeGetCurrent() + 1
        while stash.semanticObservationStream.observationReplayWaiterCount == 0,
              CFAbsoluteTimeGetCurrent() < deadline {
            await Task.yield()
            guard await Task.cancellableSleep(for: .milliseconds(5)) else { break }
        }
        XCTAssertEqual(stash.semanticObservationStream.observationReplayWaiterCount, 1, file: file, line: line)
    }

    private func observedState(
        elements: [(AccessibilityElement, HeistId)],
        screenId: String? = nil,
        screenChanged: Bool = false
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
            transition: screenChanged
                ? AccessibilityTrace.Transition(accessibilityNotifications: [
                    AccessibilityNotificationEvidence(
                        sequence: 1,
                        kind: .screenChanged,
                        timestamp: Date(timeIntervalSince1970: 0),
                        notificationData: .none,
                        associatedElement: .none
                    ),
                ])
                : state.capture.transition
        )
        return PostActionObservation.BeforeState(
            screen: state.screen,
            capture: capture,
            tripwireSignal: state.tripwireSignal,
            settledObservationSequence: state.settledObservationSequence
        )
    }

    private func heistRuntime(
        observations: [PostActionObservation.BeforeState],
        executionBaseline: SettledCapture? = nil,
        execute: (@MainActor (ResolvedHeistActionCommand) async -> ActionResult)? = nil,
        wait: (@MainActor (TheBrains.HeistRuntimeWaitRequest) async -> ActionResult)? = nil,
        observedScopes: (@MainActor (SemanticObservationScope) -> Void)? = nil,
        observedTimeouts: (@MainActor (Double?) -> Void)? = nil,
        executionBaselineScopes: (@MainActor (SemanticObservationScope?) -> Void)? = nil,
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
            execute: { command, baselineScope in
                executionBaselineScopes?(baselineScope)
                let result: ActionResult
                if let execute {
                    result = await execute(command)
                } else {
                    result = ActionResult.success(
                        method: command.testActionResultMethod,
                        message: command.runtimeType.rawValue,
                        evidence: .none
                    )
                }
                return RuntimeActionExecution(
                    result: result,
                    expectationBaseline: executionBaseline
                )
            },
            wait: { request in
                await self.heistRuntimeWaitReceipt(
                    for: request,
                    wait: wait,
                    observationSource: observationSource
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

    private func repeatUntilReceiptRuntime(
        execute: (@MainActor (ResolvedHeistActionCommand) async -> ActionResult)? = nil,
        wait: @escaping @MainActor (TheBrains.HeistRuntimeWaitRequest) async -> HeistWaitReceipt
    ) -> TheBrains.HeistExecutionRuntime {
        TheBrains.HeistExecutionRuntime(
            execute: { command, _ in
                let result: ActionResult
                if let execute {
                    result = await execute(command)
                } else {
                    result = ActionResult.success(
                        method: command.testActionResultMethod,
                        message: command.runtimeType.rawValue,
                        evidence: .none
                    )
                }
                return RuntimeActionExecution(result: result, expectationBaseline: nil)
            },
            wait: wait,
            selectPredicateCase: { _, _ in
                HeistCaseSelectionResult(cases: [], outcome: .noMatch, elapsedMs: 0)
            },
            observeSemanticState: { _, _, _ in nil }
        )
    }

    private func heistRuntimeWaitReceipt(
        for request: TheBrains.HeistRuntimeWaitRequest,
        wait: (@MainActor (TheBrains.HeistRuntimeWaitRequest) async -> ActionResult)?,
        observationSource: ScriptedHeistObservationSource
    ) async -> HeistWaitReceipt {
        let waitStep = request.step
        let initialTrace = request.initialTrace
        let afterSequence = request.afterSequence
        let observationScope = SemanticObservationScope.discovery
        if let wait {
            return heistWaitReceipt(for: waitStep, result: await wait(request))
        }
        if let initialTrace, afterSequence == nil {
            let expectation = PredicateEvaluation.evaluate(
                waitStep.predicate,
                expression: waitStep.predicateExpression,
                in: initialTrace,
                completeness: .incomplete
            )
            if expectation.met || waitStep.timeout == 0 {
                let result = makeWaitActionResult(
                    met: expectation.met,
                    message: expectation.actual,
                    traceEvidence: makeTestTraceEvidence(initialTrace, completeness: .incomplete)
                )
                return heistWaitReceipt(for: waitStep, result: result, expectation: expectation)
            }
        }
        if waitStep.timeout == 0,
           afterSequence == nil,
           let observation = observationSource.immediate(scope: observationScope) {
            return heistWaitReceipt(for: waitStep, observation: observation)
        }
        guard let observation = observationSource.next(
            scope: observationScope,
            timeout: waitStep.timeout
        ) else {
            let expectation = ExpectationResult(
                met: false,
                predicate: waitStep.predicateExpression,
                actual: "no settled semantic observation available"
            )
            let result = ActionResult.failure(
                method: .wait,
                errorKind: .timeout,
                message: expectation.actual,
                evidence: .none
            )
            return heistWaitReceipt(for: waitStep, result: result, expectation: expectation)
        }
        return heistWaitReceipt(for: waitStep, observation: observation)
    }

    private func heistWaitReceipt(
        for step: ResolvedWaitRuntimeInput,
        observation: HeistSemanticObservation
    ) -> HeistWaitReceipt {
        let expectation = PredicateEvaluation.evaluate(
            step.predicate,
            expression: step.predicateExpression,
            in: observation
        )
        let result = makeWaitActionResult(
            met: expectation.met,
            message: expectation.actual,
            traceEvidence: makeTestTraceEvidence(
                observation.accessibilityTrace,
                completeness: .incomplete
            )
        )
        switch expectation {
        case .met(let expectation):
            return .matched(
                message: result.message,
                traceEvidence: result.traceEvidence,
                expectation: expectation,
                observedSequence: observation.event.sequence,
                observationSummary: observation.summary
            )
        case .unmet(let expectation):
            return .timedOut(
                message: result.message,
                traceEvidence: result.traceEvidence,
                expectation: expectation,
                observedSequence: observation.event.sequence,
                observationSummary: observation.summary
            )
        }
    }

    private func heistWaitReceipt(
        for step: ResolvedWaitRuntimeInput,
        result: ActionResult
    ) -> HeistWaitReceipt {
        let expectation: ExpectationResult
        if result.outcome.isSuccess {
            expectation = step.predicate.validate(against: result).expectation(for: step.predicateExpression)
        } else {
            expectation = ExpectationResult(
                met: false,
                predicate: step.predicateExpression,
                actual: result.message ?? "failed"
            )
        }
        return heistWaitReceipt(for: step, result: result, expectation: expectation)
    }

    private func heistWaitReceipt(
        for _: ResolvedWaitRuntimeInput,
        result: ActionResult,
        expectation: ExpectationResult
    ) -> HeistWaitReceipt {
        if result.outcome.isSuccess, case .met(let expectation) = expectation {
            return .matched(
                message: result.message,
                traceEvidence: result.traceEvidence,
                expectation: expectation
            )
        }
        let unmet = ExpectationResult.Unmet(expectation) ?? ExpectationResult.Unmet(
            predicate: expectation.predicate,
            actual: result.message ?? expectation.actual
        )
        if result.outcome.errorKind == .timeout || result.outcome.isSuccess {
            return .timedOut(
                message: result.message,
                traceEvidence: result.traceEvidence,
                expectation: unmet
            )
        }
        return .failed(
                errorKind: result.outcome.errorKind ?? .general,
                message: result.message,
                traceEvidence: result.traceEvidence,
                expectation: unmet
            )
    }

    private func metExpectation(
        _ result: ExpectationResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> ExpectationResult.Met {
        guard let expectation = ExpectationResult.Met(result) else {
            XCTFail("Expected met expectation fixture", file: file, line: line)
            return ExpectationResult.Met(predicate: result.predicate, actual: result.actual)
        }
        return expectation
    }

    private func unmetExpectation(
        _ result: ExpectationResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> ExpectationResult.Unmet {
        guard let expectation = ExpectationResult.Unmet(result) else {
            XCTFail("Expected unmet expectation fixture", file: file, line: line)
            return ExpectationResult.Unmet(predicate: result.predicate, actual: result.actual)
        }
        return expectation
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
                of: #"interface: [0-9]+ elements"#,
                with: "interface: <count> elements",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"hash sha256:[a-f0-9]+"#,
                with: "hash sha256:<hash>",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"last change: (none|no_change)"#,
                with: "last change: <settled>",
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

private extension ResolvedHeistActionCommand {
    var testActionResultMethod: ActionMethod {
        switch self {
        case .activate: .activate
        case .increment: .increment
        case .decrement: .decrement
        case .customAction: .customAction
        case .rotor: .rotor
        case .dismiss: .dismiss
        case .magicTap: .magicTap
        case .mechanicalTap: .syntheticTap
        case .mechanicalLongPress: .syntheticLongPress
        case .mechanicalSwipe: .syntheticSwipe
        case .mechanicalDrag: .syntheticDrag
        case .typeText: .typeText
        case .editAction: .editAction
        case .viewportScroll: .scroll
        case .viewportScrollToVisible: .scrollToVisible
        case .viewportScrollToEdge: .scrollToEdge
        case .dismissKeyboard: .resignFirstResponder
        case .setPasteboard: .setPasteboard
        case .takeScreenshot: .takeScreenshot
        }
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
            semanticSignal: .empty
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
            trace: trace
        )
        return HeistSemanticObservation(
            event: event,
            state: state,
            accessibilityTrace: trace,
            summary: "interface: \(state.interface.projectedElements.count) elements"
        )
    }
}

private extension ActionResult {
    var heistExecutionPayload: HeistExecutionResult? {
        guard case .heistExecution(let result) = payload else { return nil }
        return result
    }
}

private func makeWaitActionResult(
    met: Bool,
    message: String?,
    traceEvidence: AccessibilityTraceEvidence?
) -> ActionResult {
    let observation = traceEvidence.map(ActionResultObservationEvidence.trace) ?? .none
    if met {
        return ActionResult.success(
            method: .wait,
            message: message,
            evidence: ActionResultSuccessEvidence(observation: observation)
        )
    }
    return ActionResult.failure(
        method: .wait,
        errorKind: .timeout,
        message: message,
        evidence: ActionResultFailureEvidence(observation: observation)
    )
}

#endif
