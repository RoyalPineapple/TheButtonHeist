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

final class TouchFallbackTextField: UITextField {
    private(set) var accessibilityActivationCount = 0
    var onBecomeFirstResponder: (@MainActor () -> Void)?

    override func accessibilityActivate() -> Bool {
        accessibilityActivationCount += 1
        return true
    }

    override func becomeFirstResponder() -> Bool {
        onBecomeFirstResponder?()
        return super.becomeFirstResponder()
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

    @objc(deleteFromInput)
    func deleteFromInput() {
        inputDelegate.deleteBackward()
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
        installObservedGeometryHeartbeat()
        await brains.startActionTestRuntime()
    }

    override func tearDown() async throws {
        brains.stopActionTestRuntime()
        brains = nil
        visibleObservationSource = nil
        try await super.tearDown()
    }

    func replaceBrains(keyboardInput: SafecrackerKeyboardInput) async {
        brains.stopActionTestRuntime()
        brains = TheBrains(
            tripwire: TheTripwire(),
            keyboardInput: keyboardInput,
            visibleObservationSource: visibleObservationSource.capture
        )
        installObservedGeometryHeartbeat()
        await brains.startActionTestRuntime()
    }

    private func installObservedGeometryHeartbeat() {
        brains.navigation.elementInflation.geometryEnvironment = .init(
            now: { RuntimeElapsed.now },
            awaitFrame: { _ in .observed }
        )
    }

    // MARK: - Helpers

    func registerScreenElement(
        heistId: HeistId,
        element: AccessibilityElement,
        object: NSObject?
    ) async {
        if let object {
            object.accessibilityFrame = element.shape.frame
        }
        await installScreen(elements: [(element, heistId)], objects: [heistId: object])
    }

    func installSyntheticObservation(_ observation: InterfaceObservation) async {
        visibleObservationSource.observation = observation
        await brains.vault.installObservationForTesting(observation)
    }

    func installScreen(
        elements: [(AccessibilityElement, HeistId)],
        objects: [HeistId: NSObject?] = [:]
    ) async {
        let observation = InterfaceObservation.makeForTests(
            elements: elements.map { ($0.0, $0.1) },
            objects: objects
        )
        await installSyntheticObservation(observation)
    }

    func installScreen(
        offViewport: [InterfaceObservation.OffViewportEntry]
    ) async {
        let observation = InterfaceObservation.makeForTests(
            offViewport: offViewport
        )
        await installSyntheticObservation(observation)
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
    ) async -> Observation.SnapshotEvent {
        await observedState(elements: labels.enumerated().map { index, label in
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
    ) async -> Observation.SnapshotEvent {
        let event = await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            .makeForTests(elements: elements)
        )
        guard let screenId else { return event }
        let state = event.moment.capture

        let context = AccessibilityTrace.Context(
            firstResponder: state.context.firstResponder,
            keyboardVisible: state.context.keyboardVisible,
            screenId: screenId,
            observationGeneration: state.context.observationGeneration,
            windowStack: state.context.windowStack
        )
        let capture = AccessibilityTrace.Capture(
            sequence: state.sequence,
            interface: state.interface,
            parentHash: state.parentHash,
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
                : state.transition
        )
        let snapshot = Observation.Snapshot(
            sequence: event.sequence,
            generation: event.generation,
            sourceScope: event.scope,
            observation: event.snapshot.observation,
            semanticSignal: event.snapshot.semanticSignal,
            notificationSequence: event.notificationSequence,
            trace: AccessibilityTrace(capture: capture)
        )
        var log = Observation.Log(retentionLimit: 1)
        do {
            return try log.record(snapshot: snapshot, continuity: .sameGeneration)
        } catch {
            preconditionFailure("Test observation fixture produced an invalid transition: \(error)")
        }
    }

    func observationEvents(
        for events: [Observation.SnapshotEvent]
    ) -> [Observation.SnapshotEvent] {
        var log = Observation.Log(retentionLimit: Observation.Store.defaultRetentionLimit)
        var previousCapture: AccessibilityTrace.Capture?
        var recordedEvents: [Observation.SnapshotEvent] = []

        for (index, event) in events.enumerated() {
            let capture = event.moment.capture
            let trace = previousCapture.map {
                AccessibilityTrace(capture: $0).appending(
                    capture.interface,
                    context: capture.context,
                    transition: capture.transition
                )
            } ?? AccessibilityTrace(capture: capture)
            let snapshot = Observation.Snapshot(
                sequence: SettledObservationSequence(UInt64(index + 1)),
                generation: .initial,
                sourceScope: .visible,
                observation: event.snapshot.observation,
                semanticSignal: .empty,
                notificationSequence: UInt64(index + 1),
                trace: trace
            )
            do {
                let event = try log.record(snapshot: snapshot, continuity: .sameGeneration)
                recordedEvents.append(event)
            } catch {
                preconditionFailure("Test moment fixture produced an invalid observation transition: \(error)")
            }
            previousCapture = trace.captures.last
        }
        return recordedEvents
    }

    func heistRuntime(
        observations: [Observation.SnapshotEvent],
        execute: (@MainActor (ResolvedHeistActionCommand) async -> ActionResult)? = nil,
        settle: (@MainActor (Settlement.Command) async -> Settlement.Result)? = nil,
        observedScopes: (@MainActor (SemanticObservationScope) -> Void)? = nil,
        observedTimeouts: (@MainActor (Double?) -> Void)? = nil,
        observedSettlementCommands: (@MainActor (Settlement.Command) -> Void)? = nil,
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
            execute: { command, expectation in
                let result = if let execute {
                    await execute(command)
                } else {
                    ActionResult.success(payload: command.resultPayload)
                }
                guard result.outcome.isSuccess, let expectation else {
                    return RuntimeActionExecution(result: result)
                }
                let settlementCommand = Settlement.Command.action(.init(
                    command: command,
                    predicate: .init(authored: expectation.predicateExpression, resolved: expectation.predicate),
                    allowances: .init(readiness: .milliseconds(Int64(SettleSession.defaultTimeoutMs)),
                        expectation: .milliseconds(Int64((expectation.timeout.seconds * 1_000).rounded(.up)))
                    ),
                    baseline: .capture
                ))
                observedSettlementCommands?(settlementCommand)
                guard let settle else {
                    preconditionFailure("Scripted attached expectation requires action settlement")
                }
                return RuntimeActionExecution(
                    evidence: Settlement.ResultProjector.projectAction(await settle(settlementCommand))
                )
            },
            settle: { command in
                observedSettlementCommands?(command)
                return await self.scriptedSettlement(
                    command,
                    settle: settle,
                    observationSource: observationSource
                )
            }
        )
    }

    func repeatUntilSettlementRuntime(
        execute: (@MainActor (ResolvedHeistActionCommand) async -> ActionResult)? = nil,
        settle: @escaping @MainActor (Settlement.Command) async -> Settlement.Result
    ) -> TheBrains.HeistExecutionRuntime {
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
                return RuntimeActionExecution(result: result)
            },
            settle: settle
        )
    }

    private func scriptedSettlement(
        _ command: Settlement.Command,
        settle: (@MainActor (Settlement.Command) async -> Settlement.Result)?,
        observationSource: ScriptedHeistObservationSource
    ) async -> Settlement.Result {
        if let settle {
            return await settle(command)
        }
        if let baseline = command.baseline,
           case .unavailable = baseline {
            return TheInsideJobTests.scriptedSettlement(command, observation: nil)
        }
        let timeout: Double?
        switch command {
        case .currentState:
            timeout = nil
        case .observation(_, let deadline, _):
            timeout = deadline.remainingDuration(at: RuntimeElapsed.now) / .seconds(1)
        case .action(let action):
            timeout = action.allowances.readiness / .seconds(1)
        }
        let observation = observationSource.next(
            scope: command.observationScope,
            timeout: timeout
        )
        return TheInsideJobTests.scriptedSettlement(command, observation: observation)
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

@MainActor
extension TheBrains {
    func startActionTestRuntime() async {
        tripwire.uikitIdleTracker.installIfAvailable()
        tripwire.startPulse()
        await startSemanticObservation()
    }

    func stopActionTestRuntime() {
        stopSemanticObservation()
        tripwire.stopPulse()
        tripwire.uikitIdleTracker.uninstallIfNeeded()
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
    private var remainingObservations: [Observation.SnapshotEvent]
    private var remainingUnavailableObservations: Int
    private var previousCapture: AccessibilityTrace.Capture?
    private var nextObservationSequence: SettledObservationSequence = 0
    private var log = Observation.Log(retentionLimit: Observation.Store.defaultRetentionLimit)
    private let observedScopes: (@MainActor (SemanticObservationScope) -> Void)?
    private let observedTimeouts: (@MainActor (Double?) -> Void)?
    private let file: StaticString
    private let line: UInt

    init(
        observations: [Observation.SnapshotEvent],
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

    func next(
        scope: SemanticObservationScope,
        timeout: Double?
    ) -> Observation.SnapshotEvent? {
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
        let sourceEvent = remainingObservations.removeFirst()
        nextObservationSequence += 1
        let event = event(
            from: sourceEvent,
            scope: scope,
            sequence: nextObservationSequence
        )
        previousCapture = event.trace.captures.last
        return event
    }

    private func event(
        from sourceEvent: Observation.SnapshotEvent,
        scope: SemanticObservationScope,
        sequence: SettledObservationSequence
    ) -> Observation.SnapshotEvent {
        let capture = sourceEvent.moment.capture
        let trace = if let previousCapture {
            AccessibilityTrace(capture: previousCapture).appending(
                capture.interface,
                context: capture.context,
                transition: capture.transition
            )
        } else {
            AccessibilityTrace(capture: capture)
        }
        let snapshot = Observation.Snapshot(
            sequence: sequence,
            generation: .initial,
            sourceScope: scope,
            observation: sourceEvent.snapshot.observation,
            semanticSignal: .empty,
            notificationSequence: 0,
            trace: trace
        )
        do {
            return try log.record(snapshot: snapshot, continuity: .sameGeneration)
        } catch {
            preconditionFailure("Scripted heist produced an invalid observation transition: \(error)")
        }
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
