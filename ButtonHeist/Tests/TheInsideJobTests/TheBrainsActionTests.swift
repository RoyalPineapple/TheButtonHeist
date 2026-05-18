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

    // MARK: - clampDuration

    func testClampDurationNilReturnsDefault() {
        let result = brains.actions.clampDuration(nil)
        XCTAssertEqual(result, 0.5, accuracy: 0.001,
                       "nil duration should return default (0.5)")
    }

    func testClampDurationRespectsMinimum() {
        let result = brains.actions.clampDuration(0.001)
        XCTAssertEqual(result, 0.01, accuracy: 0.001,
                       "Duration below minimum should clamp to 0.01")
    }

    func testClampDurationRespectsMaximum() {
        let result = brains.actions.clampDuration(120.0)
        XCTAssertEqual(result, 60.0, accuracy: 0.001,
                       "Duration above maximum should clamp to 60.0")
    }

    func testClampDurationPassesThroughValidValue() {
        let result = brains.actions.clampDuration(1.5)
        XCTAssertEqual(result, 1.5, accuracy: 0.001,
                       "Valid duration should pass through unchanged")
    }

    // MARK: - resolveDuration

    func testResolveDurationExplicitDurationTakesPrecedence() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)]
        let result = brains.actions.resolveDuration(2.0, velocity: 50.0, points: points)
        XCTAssertEqual(result, 2.0, accuracy: 0.001,
                       "Explicit duration should take precedence over velocity")
    }

    func testResolveDurationFromVelocity() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 100, y: 0),
            CGPoint(x: 200, y: 0),
        ]
        let result = brains.actions.resolveDuration(nil, velocity: 100.0, points: points)
        XCTAssertEqual(result, 2.0, accuracy: 0.01,
                       "200pt path at 100pt/s = 2.0s")
    }

    func testResolveDurationFromVelocityDiagonal() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 300, y: 400),
        ]
        let result = brains.actions.resolveDuration(nil, velocity: 500.0, points: points)
        XCTAssertEqual(result, 1.0, accuracy: 0.01,
                       "500pt diagonal path at 500pt/s = 1.0s")
    }

    func testResolveDurationNilBothReturnsDefault() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)]
        let result = brains.actions.resolveDuration(nil, velocity: nil, points: points)
        XCTAssertEqual(result, 0.5, accuracy: 0.001,
                       "No duration and no velocity should return default")
    }

    func testResolveDurationZeroVelocityReturnsDefault() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)]
        let result = brains.actions.resolveDuration(nil, velocity: 0.0, points: points)
        XCTAssertEqual(result, 0.5, accuracy: 0.001,
                       "Zero velocity should fall through to default")
    }

    func testResolveDurationVelocityResultIsClamped() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 10000, y: 0)]
        let result = brains.actions.resolveDuration(nil, velocity: 1.0, points: points)
        XCTAssertEqual(result, 60.0, accuracy: 0.001,
                       "Very long path at low velocity should clamp to max")
    }

    func testResolveDurationVelocitySmallPathClamps() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 0.0001, y: 0)]
        let result = brains.actions.resolveDuration(nil, velocity: 1000.0, points: points)
        XCTAssertEqual(result, 0.01, accuracy: 0.001,
                       "Tiny path at high velocity should clamp to minimum")
    }

    // MARK: - BeforeState Capture

    func testCaptureBeforeStateReturnsEmptySnapshotWhenRegistryEmpty() {
        let before = brains.captureBeforeState()
        XCTAssertTrue(before.snapshot.isEmpty,
                      "Snapshot should be empty when no elements in registry")
        XCTAssertTrue(before.elements.isEmpty,
                      "Elements should be empty when no hierarchy set")
    }

    func testCaptureBeforeStateIncludesRegisteredElements() {
        let element = makeElement(label: "Title", traits: .header)
        let heistId = "header_title"
        installScreen(elements: [(element, heistId)])

        let before = brains.captureBeforeState()
        XCTAssertEqual(before.snapshot.count, 1)
        XCTAssertEqual(before.snapshot.first?.heistId, heistId)
        XCTAssertEqual(before.elements.count, 1)
    }

    // MARK: - Deallocated Element Fail-Closed

    func testExecuteIncrementFailsWhenElementObjectIsDeallocated() async {
        let heistId = "volume_slider"
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Volume", traits: .adjustable),
            object: nil
        )

        let result = await brains.actions.executeIncrement(.heistId(heistId))

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .elementDeallocated)
        XCTAssertDiagnostic(result.message, contains: [
            "adjustable action failed",
            "heistId=\"volume_slider\"",
            "label=\"Volume\"",
            "traits=[adjustable]",
            "liveObject=deallocated",
            "try refresh with get_interface",
        ])
    }

    func testExecuteDecrementFailsWhenElementObjectIsDeallocated() async {
        let heistId = "brightness_slider"
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Brightness", traits: .adjustable),
            object: nil
        )

        let result = await brains.actions.executeDecrement(.heistId(heistId))

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .elementDeallocated)
        XCTAssertDiagnostic(result.message, contains: [
            "adjustable action failed",
            "heistId=\"brightness_slider\"",
            "label=\"Brightness\"",
            "traits=[adjustable]",
            "liveObject=deallocated",
            "try refresh with get_interface",
        ])
    }

    func testExecuteIncrementFailsWhenElementIsNotAdjustable() async {
        let heistId = "live_button"
        let liveObject = UIButton(type: .system)
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Live", traits: .button),
            object: liveObject
        )

        let result = await brains.actions.executeIncrement(.heistId(heistId))

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

        let result = await brains.actions.executeDecrement(.heistId(heistId))

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

    func testExecuteCustomActionFailsWhenElementObjectIsDeallocated() async {
        let heistId = "options_button"
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Options", traits: .button),
            object: nil
        )

        let result = await brains.actions.executeCustomAction(
            CustomActionTarget(elementTarget: .heistId(heistId), actionName: "Delete")
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .elementDeallocated)
        XCTAssertDiagnostic(result.message, contains: [
            "custom action failed",
            "heistId=\"options_button\"",
            "label=\"Options\"",
            "liveObject=deallocated",
            "try refresh with get_interface",
        ])
    }

    func testExecuteCustomActionMissingReportsAvailableCustomActions() async {
        let heistId = "options_button"
        let liveObject = UIButton(type: .system)
        registerScreenElement(
            heistId: heistId,
            element: makeElement(
                label: "Options",
                traits: .button,
                customActions: [.init(name: "Delete"), .init(name: "Archive")]
            ),
            object: liveObject
        )

        let result = await brains.actions.executeCustomAction(
            CustomActionTarget(elementTarget: .heistId(heistId), actionName: "Share")
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
        let liveObject = UIButton(type: .system)
        liveObject.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Delete") { _ in false },
            UIAccessibilityCustomAction(name: "Archive") { _ in true },
        ]
        registerScreenElement(
            heistId: heistId,
            element: makeElement(
                label: "Options",
                traits: .button,
                customActions: [.init(name: "Delete"), .init(name: "Archive")]
            ),
            object: liveObject
        )

        let result = await brains.actions.executeCustomAction(
            CustomActionTarget(elementTarget: .heistId(heistId), actionName: "Delete")
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

    func testExecuteActivateSucceedsForNoTraitElementWithActivationOverride() async {
        let heistId = "plain_action"
        let liveObject = ActionActivationOverrideView()
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Plain action"),
            object: liveObject
        )

        let result = await brains.actions.executeActivate(.heistId(heistId))

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

        let result = await brains.actions.executeActivate(.heistId(heistId))

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

        let result = await brains.actions.executeActivate(.heistId(heistId))

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

        let result = await brains.actions.executeIncrement(.heistId(heistId))

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.method, .increment)
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
            TouchTapTarget(pointX: -10_000, pointY: -10_000)
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .syntheticTap)
        XCTAssertDiagnostic(result.message, contains: [
            "gesture dispatch failed",
            "method=syntheticTap",
            "phase=dispatch",
            "point=(-10000,-10000)",
            "window=none",
            "try target a visible element",
        ])
    }

    func testElementTargetedPointActionFailsWhenElementRemainsKnownOnly() async {
        let stalePoint = CGPoint(x: 333, y: 777)
        let element = AccessibilityElement.make(
            label: "Below Fold",
            traits: .button,
            shape: .frame(CGRect(x: 300, y: 750, width: 66, height: 54)),
            activationPoint: stalePoint
        )
        installScreen(offViewport: [.init(element, heistId: "below_fold_button")])

        var dispatchedPoint: CGPoint?
        let result = await brains.actions.performPointAction(
            elementTarget: .heistId("below_fold_button"),
            pointX: nil,
            pointY: nil,
            method: .syntheticTap
        ) { point in
            dispatchedPoint = point
            return true
        }

        XCTAssertFalse(result.success)
        XCTAssertNil(dispatchedPoint, "Known-only targets must not dispatch their stored activation point")
        XCTAssertDiagnostic(result.message, contains: [
            "gesture target unavailable",
            "method=syntheticTap",
            "phase=targeting",
            "heistId=\"below_fold_button\"",
            "visible=false",
            "element-derived gesture points require a live reachable element",
        ])
    }

    func testElementTargetedPointActionUsesLiveActivationPoint() async {
        let stalePoint = CGPoint(x: 10, y: 20)
        let livePoint = CGPoint(x: 123, y: 456)
        let heistId = "live_button"
        let element = AccessibilityElement.make(
            label: "Live",
            traits: .button,
            shape: .frame(CGRect(x: 0, y: 0, width: 40, height: 40)),
            activationPoint: stalePoint
        )
        let liveObject = ActionGeometryView(activationPoint: livePoint)
        liveObject.accessibilityFrame = CGRect(x: 100, y: 430, width: 46, height: 52)
        installScreen(elements: [(element, heistId)], objects: [heistId: liveObject])

        var dispatchedPoint: CGPoint?
        let result = await brains.actions.performPointAction(
            elementTarget: .heistId(heistId),
            pointX: nil,
            pointY: nil,
            method: .syntheticTap
        ) { point in
            dispatchedPoint = point
            return true
        }

        XCTAssertTrue(result.success)
        XCTAssertEqual(dispatchedPoint, livePoint)
        XCTAssertNotEqual(dispatchedPoint, stalePoint)
    }

    func testRawCoordinatePointActionDispatchesUnchanged() async {
        let rawPoint = CGPoint(x: 222, y: 333)

        var dispatchedPoint: CGPoint?
        let result = await brains.actions.performPointAction(
            elementTarget: nil,
            pointX: Double(rawPoint.x),
            pointY: Double(rawPoint.y),
            method: .syntheticTap
        ) { point in
            dispatchedPoint = point
            return true
        }

        XCTAssertTrue(result.success)
        XCTAssertEqual(dispatchedPoint, rawPoint)
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
            RotorTarget(elementTarget: .heistId(heistId), rotor: "Errors")
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
            RotorTarget(elementTarget: .heistId(heistId), rotor: "Errors")
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
            RotorTarget(elementTarget: .heistId(heistId), rotor: "Errors")
        )

        XCTAssertFalse(result.success)
        XCTAssertDiagnostic(result.message, contains: [
            "availableRotors=[\"Warnings\"]",
            "try use one of available rotors [\"Warnings\"]",
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

    func testExecuteWaitForIdleFailsWhenAccessibilityTreeUnavailable() async {
        let result = await withNoTraversableWindows {
            await brains.executeWaitForIdle(timeout: 0.1)
        }

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .waitForIdle)
        XCTAssertEqual(result.errorKind, .actionFailed)
        // The wire kind stays actionFailed for compatibility. The factual
        // message is what lets TheFence surface the local tree-unavailable
        // diagnostic without adding a new ErrorKind raw value.
        XCTAssertEqual(result.message, "Could not access accessibility tree: no traversable app windows")
    }

    func testExecuteCommandExploreFailsWhenAccessibilityTreeUnavailable() async {
        let result = await withNoTraversableWindows {
            await brains.executeCommand(.explore)
        }

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .explore)
        XCTAssertEqual(result.errorKind, .actionFailed)
    }

    func testExecuteCommandWaitForFailsWhenAccessibilityTreeUnavailable() async {
        let target = WaitForTarget(
            elementTarget: .matcher(ElementMatcher(label: "never"))
        )
        let result = await withNoTraversableWindows {
            await brains.executeCommand(.waitFor(target))
        }

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .waitFor)
        XCTAssertEqual(result.errorKind, .actionFailed)
    }

    func testWaitForTreeUnavailableFailureKindMapsToActionFailed() {
        XCTAssertEqual(
            TheBrains.waitForErrorKind(for: .treeUnavailable),
            .actionFailed
        )
        XCTAssertEqual(TheBrains.waitForErrorKind(for: .timeout), .timeout)
        XCTAssertEqual(TheBrains.waitForErrorKind(for: nil), .elementNotFound)
    }

    // MARK: - Helpers

    private func registerScreenElement(
        heistId: String,
        element: AccessibilityElement,
        object: NSObject?
    ) {
        installScreen(elements: [(element, heistId)], objects: [heistId: object])
    }

    private func installScreen(
        elements: [(AccessibilityElement, String)],
        objects: [String: NSObject?] = [:]
    ) {
        brains.stash.currentScreen = .makeForTests(
            elements: elements.map { ($0.0, $0.1) },
            objects: objects
        )
    }

    private func installScreen(
        offViewport: [Screen.OffViewportEntry]
    ) {
        brains.stash.currentScreen = .makeForTests(
            offViewport: offViewport
        )
    }

    private func makeElement(
        label: String? = nil,
        traits: UIAccessibilityTraits = .none,
        customActions: [AccessibilityElement.CustomAction] = [],
        customRotors: [AccessibilityElement.CustomRotor] = []
    ) -> AccessibilityElement {
        .make(
            label: label,
            traits: traits,
            customActions: customActions,
            customRotors: customRotors,
            respondsToUserInteraction: false
        )
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
