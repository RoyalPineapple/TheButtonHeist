#if canImport(UIKit)
import ButtonHeistSupport
import ButtonHeistTestSupport
import XCTest
@testable import AccessibilitySnapshotParser
@_spi(ButtonHeistInternals) @testable import ThePlans
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

final class ActionActivationOverrideView: UIView {
    private(set) var activationCount = 0
    var onActivation: (@MainActor () -> Void)?

    override func accessibilityActivate() -> Bool {
        activationCount += 1
        onActivation?()
        return true
    }
}

final class RefusingActivationView: UIView {
    private(set) var activationCount = 0

    override func accessibilityActivate() -> Bool {
        activationCount += 1
        return false
    }
}

final class ActionActivatingTextField: UITextField {
    private(set) var activationCount = 0

    override func accessibilityActivate() -> Bool {
        activationCount += 1
        return becomeFirstResponder()
    }
}

final class ResignationTrackingTextField: UITextField {
    private(set) var resignationCount = 0

    override func resignFirstResponder() -> Bool {
        resignationCount += 1
        return super.resignFirstResponder()
    }
}

@MainActor
final class ActionTextInputKeyboardImpl: NSObject {
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

    @objc(addInputString:withFlags:)
    func addInputString(_ text: NSString, flags: UInt) {
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

final class CustomActionTargetObject: NSObject {
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

final class ActionGeometryView: UIView {
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

final class AdjustableGeometryView: UIView {
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

    var brains: TheBrains!
    var visibleObservationSource: VisibleObservationSourceFixture!

    override func setUp() async throws {
        try await super.setUp()
        visibleObservationSource = VisibleObservationSourceFixture()
        brains = TheBrains(
            tripwire: TheTripwire(),
            visibleObservationSource: visibleObservationSource.capture
        )
        brains.startSemanticObservation()
    }

    override func tearDown() async throws {
        brains.stopSemanticObservation()
        brains = nil
        visibleObservationSource = nil
        try await super.tearDown()
    }

    func replaceBrains(keyboardInput: SafecrackerKeyboardInput) {
        brains.stopSemanticObservation()
        brains.tripwire.stopPulse()
        brains = TheBrains(
            tripwire: TheTripwire(),
            keyboardInput: keyboardInput,
            visibleObservationSource: visibleObservationSource.capture
        )
        brains.startSemanticObservation()
    }

    // MARK: - Helpers

    func registerScreenElement(
        heistId: HeistId,
        element: AccessibilityElement,
        object: NSObject?
    ) {
        if let object {
            object.accessibilityFrame = element.shape.frame
        }
        installScreen(elements: [(element, heistId)], objects: [heistId: object])
    }

    func installSyntheticObservation(_ observation: InterfaceObservation) {
        visibleObservationSource.observation = observation
        brains.vault.installObservationForTesting(observation)
    }

    func installScreen(
        elements: [(AccessibilityElement, HeistId)],
        objects: [HeistId: NSObject?] = [:]
    ) {
        let observation = InterfaceObservation.makeForTests(
            elements: elements.map { ($0.0, $0.1) },
            objects: objects
        )
        installSyntheticObservation(observation)
    }

    func installScreen(
        offViewport: [InterfaceObservation.OffViewportEntry]
    ) {
        let observation = InterfaceObservation.makeForTests(
            offViewport: offViewport
        )
        installSyntheticObservation(observation)
    }

    func installModalWindow(rootView: UIView) throws -> UIWindow {
        visibleObservationSource.useLiveCapture()
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

    func makeElement(
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

    func matcherTarget(
        label: String,
        in observation: InterfaceObservation
    ) throws -> AccessibilityTarget {
        let treeElement = try XCTUnwrap(observation.tree.orderedElements.first { $0.element.label == label })
        let elements = observation.tree.orderedElements.map {
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
        single singleResult: TheSafecracker.ActionDispatchResult,
        heist heistResult: TheSafecracker.ActionDispatchResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(heistResult.success, singleResult.success, name, file: file, line: line)
        XCTAssertEqual(heistResult.method, singleResult.method, name, file: file, line: line)
        XCTAssertEqual(heistResult.message, singleResult.message, name, file: file, line: line)
        XCTAssertEqual(heistResult.failureKind, singleResult.failureKind, name, file: file, line: line)
    }

    func assertSameActionResult(
        _ name: String,
        single: ActionResult,
        heist: ActionResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(heist.outcome.isSuccess, single.outcome.isSuccess, name, file: file, line: line)
        XCTAssertEqual(heist.method, single.method, name, file: file, line: line)
        if isPreDispatchMatcherFailure(single),
           isPreDispatchMatcherFailure(heist) {
            XCTAssertTrue(
                [.actionFailed, .elementNotFound].contains(single.outcome.failureKind),
                name,
                file: file,
                line: line
            )
            XCTAssertTrue(
                [.actionFailed, .elementNotFound].contains(heist.outcome.failureKind),
                name,
                file: file,
                line: line
            )
            return
        }
        XCTAssertEqual(heist.outcome.failureKind, single.outcome.failureKind, name, file: file, line: line)
        assertSameActionMessage(
            name,
            single: single.message,
            heist: heist.message,
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
              [.actionFailed, .elementNotFound].contains(result.outcome.failureKind),
              let message = result.message
        else { return false }
        return message.contains("No match for:")
            || message.contains("Could not observe accessibility tree")
    }

    private func firstLine(_ message: String) -> Substring {
        message.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
    }

    func heistStepResult(for step: HeistStep, label: String) async throws -> ActionResult {
        let result = await brains.executeHeistPlan(try HeistPlan(body: [step]))
        guard case .heist(let payload) = result.payload,
              let heistResult = payload,
              let stepResult = heistResult.steps.first,
              let actionResult = stepResult.reportActionResult else {
            XCTFail("Expected heist execution step result for \(label)")
            return result
        }
        return actionResult
    }

    func observedState(
        labels: [String],
        screenId: String? = nil,
        screenChanged: Bool = false
    ) -> ActionEvidenceProjector.Baseline {
        observedState(elements: labels.enumerated().map { index, label in
            (makeElement(label: label), HeistId(rawValue: "element_\(index)"))
        }, screenId: screenId, screenChanged: screenChanged)
    }

    func waitForSettledSemanticWaiter(
        on vault: TheVault,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = CFAbsoluteTimeGetCurrent() + 1
        while vault.semanticObservationStream.observationWaiterCount == 0,
              CFAbsoluteTimeGetCurrent() < deadline {
            await Task.yield()
            guard await Task.cancellableSleep(for: .milliseconds(5)) else { break }
        }
        XCTAssertEqual(vault.semanticObservationStream.observationWaiterCount, 1, file: file, line: line)
    }

    func observedState(
        elements: [(AccessibilityElement, HeistId)],
        screenId: String? = nil,
        screenChanged: Bool = false
    ) -> ActionEvidenceProjector.Baseline {
        brains.vault.installObservationForTesting(.makeForTests(elements: elements))
        let state = brains.actionEvidenceProjector.projectBaseline()
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
        return ActionEvidenceProjector.Baseline(
            observation: state.observation,
            capture: capture,
            tripwireSignal: state.tripwireSignal,
            settledObservationSequence: state.settledObservationSequence
        )
    }

    func heistRuntime(
        observations: [ActionEvidenceProjector.Baseline],
        actionExpectationContext: ActionExpectationContext? = nil,
        execute: (@MainActor (ResolvedHeistActionCommand) async -> ActionResult)? = nil,
        wait: (@MainActor (TheBrains.HeistRuntimeWaitRequest) async -> ActionResult)? = nil,
        observedScopes: (@MainActor (SemanticObservationScope) -> Void)? = nil,
        observedTimeouts: (@MainActor (Double?) -> Void)? = nil,
        expectationContextScopes: (@MainActor (SemanticObservationScope?) -> Void)? = nil,
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
        let caseBrains = TheBrains(tripwire: TheTripwire())

        return TheBrains.HeistExecutionRuntime(
            execute: { command, contextScope in
                expectationContextScopes?(contextScope)
                let result: ActionResult
                if let execute {
                    result = await execute(command)
                } else {
                    result = ActionResult.success(
                        payload: command.resultPayload
                    )
                }
                return RuntimeActionExecution(
                    result: result,
                    actionExpectationContext: actionExpectationContext
                )
            },
            wait: { request in
                await self.heistRuntimeWaitResult(
                    for: request,
                    wait: wait,
                    observationSource: observationSource
                )
            },
            selectPredicateCase: { cases, timeout in
                observationSource.prepareCaseSelection(
                    in: caseBrains.vault,
                    timeout: timeout
                )
                return await caseBrains.interactionCoordinator.waitForPredicateCases(
                    cases,
                    timeout: timeout
                )
            },
            settledEvidence: { scope, _, timeout in
                observationSource.next(scope: scope, timeout: timeout)
            }
        )
    }

    func repeatUntilWaitRuntime(
        observations: [ActionEvidenceProjector.Baseline],
        execute: (@MainActor (ResolvedHeistActionCommand) async -> ActionResult)? = nil,
        wait: @escaping @MainActor (TheBrains.HeistRuntimeWaitRequest) async -> HeistWaitResult
    ) -> TheBrains.HeistExecutionRuntime {
        let observationSource = ScriptedHeistObservationSource(
            observations: observations,
            unavailableObservationCount: 0,
            observedScopes: nil,
            observedTimeouts: nil,
            file: #filePath,
            line: #line
        )
        return TheBrains.HeistExecutionRuntime(
            execute: { command, _ in
                let result: ActionResult
                if let execute {
                    result = await execute(command)
                } else {
                    result = ActionResult.success(
                        payload: command.resultPayload
                    )
                }
                return RuntimeActionExecution(result: result, actionExpectationContext: nil)
            },
            wait: wait,
            selectPredicateCase: { _, _ in
                .selectingFirstMatch(cases: [], ifNone: .noMatch, elapsedMs: 0)
            },
            settledEvidence: { scope, _, timeout in
                observationSource.next(scope: scope, timeout: timeout)
            }
        )
    }

    private func heistRuntimeWaitResult(
        for request: TheBrains.HeistRuntimeWaitRequest,
        wait: (@MainActor (TheBrains.HeistRuntimeWaitRequest) async -> ActionResult)?,
        observationSource: ScriptedHeistObservationSource
    ) async -> HeistWaitResult {
        let waitStep = request.step
        let initialTrace = request.initialTrace
        let afterSequence = request.afterSequence
        let observationScope = SemanticObservationScope.visible
        if let wait {
            return heistWaitResult(for: waitStep, result: await wait(request))
        }
        if waitStep.predicate.requiresChangeBaseline,
           let initialTrace,
           afterSequence == nil {
            let expectation = PredicateEvaluation.evaluate(
                waitStep.predicate,
                expression: waitStep.predicateExpression,
                in: initialTrace,
                completeness: .incomplete
            )
            if expectation.met {
                let result = makeWaitActionResult(
                    met: expectation.met,
                    message: expectation.actual,
                    traceEvidence: makeTestTraceEvidence(initialTrace, completeness: .incomplete)
                )
                return heistWaitResult(for: waitStep, result: result, expectation: expectation)
            }
        }
        guard let observation = observationSource.next(
            scope: observationScope,
            timeout: waitStep.timeout.seconds
        ) else {
            let expectation = ExpectationResult(
                met: false,
                predicate: waitStep.predicateExpression,
                actual: "no settled semantic observation available"
            )
            let result = ActionResult.failure(
                payload: .wait,
                failureKind: .timeout,
                message: expectation.actual,
            )
            return heistWaitResult(for: waitStep, result: result, expectation: expectation)
        }
        return heistWaitResult(for: waitStep, observation: observation)
    }

    private func heistWaitResult(
        for step: ResolvedWaitRuntimeInput,
        observation: SettledObservationEvidence
    ) -> HeistWaitResult {
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

    private func heistWaitResult(
        for step: ResolvedWaitRuntimeInput,
        result: ActionResult
    ) -> HeistWaitResult {
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
        return heistWaitResult(for: step, result: result, expectation: expectation)
    }

    private func heistWaitResult(
        for _: ResolvedWaitRuntimeInput,
        result: ActionResult,
        expectation: ExpectationResult
    ) -> HeistWaitResult {
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
        if result.outcome.failureKind == .timeout || result.outcome.isSuccess {
            return .timedOut(
                message: result.message,
                traceEvidence: result.traceEvidence,
                expectation: unmet
            )
        }
        return .failed(
                failureKind: result.outcome.failureKind ?? .actionFailed,
                message: result.message,
                traceEvidence: result.traceEvidence,
                expectation: unmet
            )
    }

    func metExpectation(
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

    func unmetExpectation(
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

    func withNoTraversableWindows<T>(
        _ operation: () async -> T
    ) async -> T {
        let windows = brains.tripwire.captureTraversableWindows().map(\.window)
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

extension ResolvedHeistActionCommand {
    var resultPayload: ActionResult.Payload {
        switch self {
        case .activate: .activate
        case .increment: .increment
        case .decrement: .decrement
        case .customAction: .customAction
        case .rotor: .rotor(nil)
        case .dismiss: .dismiss
        case .magicTap: .magicTap
        case .oneFingerTap: .oneFingerTap
        case .longPress: .longPress
        case .swipe: .swipe
        case .drag: .drag
        case .typeText: .typeText(nil)
        case .editAction: .editAction
        case .scroll: .scroll
        case .scrollToVisible: .scrollToVisible
        case .scrollToEdge: .scrollToEdge
        case .dismissKeyboard: .dismissKeyboard
        case .setPasteboard: .setPasteboard(nil)
        case .takeScreenshot: .screenshot(nil)
        }
    }
}

@MainActor
private final class ScriptedHeistObservationSource {
    private var remainingObservations: [ActionEvidenceProjector.Baseline]
    private var remainingUnavailableObservations: Int
    private var previousObservation: SettledObservation?
    private var previousCapture: AccessibilityTrace.Capture?
    private var nextObservationSequence: SettledObservationSequence = 0
    private let observedScopes: (@MainActor (SemanticObservationScope) -> Void)?
    private let observedTimeouts: (@MainActor (Double?) -> Void)?
    private let file: StaticString
    private let line: UInt

    init(
        observations: [ActionEvidenceProjector.Baseline],
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

    func prepareCaseSelection(
        in vault: TheVault,
        timeout: Double
    ) {
        vault.semanticObservationStream.invalidateLatestSettledObservation()
        guard let observation = next(scope: .visible, timeout: timeout) else { return }
        vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation.baseline.observation
        )
    }

    func next(
        scope: SemanticObservationScope,
        timeout: Double?
    ) -> SettledObservationEvidence? {
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
        previousObservation = observation.event.settledObservation
        previousCapture = observation.accessibilityTrace.captures.last
        return observation
    }

    private func observation(
        from state: ActionEvidenceProjector.Baseline,
        scope: SemanticObservationScope,
        sequence: SettledObservationSequence
    ) -> SettledObservationEvidence {
        let settledObservation = SettledObservation(
            sequence: sequence,
            scope: scope,
            observation: .empty,
            semanticSignal: .empty
        )
        let trace = if let previousCapture {
            AccessibilityTrace(capture: previousCapture).appending(
                state.capture.interface,
                context: state.capture.context,
                transition: state.capture.transition
            )
        } else {
            AccessibilityTrace(capture: state.capture)
        }
        let event = SettledObservationEvent(
            continuity: .sameGeneration,
            settledObservation: settledObservation,
            previous: previousObservation,
            trace: trace
        )
        return SettledObservationEvidence(
            event: event,
            baseline: state,
            accessibilityTrace: trace,
            summary: "interface: \(state.interface.projectedElements.count) elements"
        )
    }
}

private extension ActionResult {
    var resultPayload: HeistResult? {
        guard case .heist(let result) = payload else { return nil }
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
            payload: .wait,
            message: message,
            observation: observation
        )
    }
    return ActionResult.failure(
        payload: .wait,
        failureKind: .timeout,
        message: message,
        observation: observation
    )
}

#endif
