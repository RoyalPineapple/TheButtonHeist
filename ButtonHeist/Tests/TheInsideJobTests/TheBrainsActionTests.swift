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
            predicate: .state(.present(ElementPredicate(label: "never")))
        )
        let result = await withNoTraversableWindows {
            await brains.executeCommand(.wait(target))
        }

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .wait)
        XCTAssertEqual(result.errorKind, .actionFailed)
    }

    func testWaitForTreeUnavailableFailureKindMapsToActionFailed() {
        XCTAssertEqual(
            TheBrains.waitForErrorKind(for: .treeUnavailable),
            .actionFailed
        )
        XCTAssertEqual(TheBrains.waitForErrorKind(for: .timeout), .timeout)
        XCTAssertEqual(TheBrains.waitForErrorKind(for: .targetUnavailable), .elementNotFound)
        XCTAssertEqual(TheBrains.waitForErrorKind(for: nil), .elementNotFound)
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

#endif
