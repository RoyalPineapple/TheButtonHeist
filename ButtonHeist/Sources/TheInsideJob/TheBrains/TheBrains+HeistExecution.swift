#if canImport(UIKit)
#if DEBUG
import Foundation

import ButtonHeistSupport
import ThePlans
@_spi(ButtonHeistInternals) import TheScore

extension TheBrains {

    struct HeistExecutionScope {
        let rootPlan: HeistPlan
        let plan: HeistPlan
        var definitionPath: [String] = []
        var invocationStack: Set<String> = []

        init(
            plan: HeistPlan,
            rootPlan: HeistPlan? = nil,
            definitionPath: [String] = [],
            invocationStack: Set<String> = []
        ) {
            self.rootPlan = rootPlan ?? plan
            self.plan = plan
            self.definitionPath = definitionPath
            self.invocationStack = invocationStack
        }
    }

    enum HeistRuntimeWaitRequest: Equatable, Sendable {
        case standalone(ResolvedWaitStep)
        case actionEndpoint(
            ResolvedWaitStep,
            trace: AccessibilityTrace?
        )
        case immediate(ResolvedWaitStep)
        case afterObservation(
            ResolvedWaitStep,
            baselineTrace: AccessibilityTrace?,
            sequence: SettledObservationSequence
        )
        case baselineTraceOnly(ResolvedWaitStep, trace: AccessibilityTrace?)

        var step: ResolvedWaitStep {
            switch self {
            case .standalone(let step),
                 .actionEndpoint(let step, _),
                 .immediate(let step),
                 .afterObservation(let step, _, _),
                 .baselineTraceOnly(let step, _):
                return step
            }
        }

        var initialTrace: AccessibilityTrace? {
            switch self {
            case .standalone,
                 .immediate:
                return nil
            case .actionEndpoint(_, let trace),
                 .afterObservation(_, let trace, _),
                 .baselineTraceOnly(_, let trace):
                return trace
            }
        }

        var afterSequence: SettledObservationSequence? {
            switch self {
            case .standalone,
                 .actionEndpoint,
                 .immediate,
                 .baselineTraceOnly:
                return nil
            case .afterObservation(_, _, let sequence):
                return sequence
            }
        }

        var announcementCursorStrategy: AnnouncementWaitCursorStrategy {
            switch self {
            case .standalone:
                return .heistScoped
            case .actionEndpoint,
                 .immediate,
                 .afterObservation,
                 .baselineTraceOnly:
                return .futureOnly
            }
        }
    }

    struct HeistExecutionRuntime {
        let execute: @MainActor (RuntimeActionMessage) async -> ActionResult
        let wait: @MainActor (HeistRuntimeWaitRequest) async -> HeistWaitReceipt
        let selectPredicateCase: @MainActor ([ResolvedPredicateCase], Double) async -> HeistCaseSelectionResult
        let observeSemanticState: @MainActor (SemanticObservationScope, SettledObservationSequence?, Double?) async -> HeistSemanticObservation?

        @MainActor
        static func live(_ brains: TheBrains) -> HeistExecutionRuntime {
            HeistExecutionRuntime(
                execute: { command in
                    await brains.executeRuntimeAction(command)
                },
                wait: { request in
                    let allowsTransitionFinalStateWarning: Bool
                    switch request {
                    case .standalone:
                        allowsTransitionFinalStateWarning = true
                    case .actionEndpoint, .immediate, .afterObservation, .baselineTraceOnly:
                        allowsTransitionFinalStateWarning = false
                    }
                    let observationPlan = WaitObservationPlan(step: request.step)
                    return await brains.interactionObservation.waitForPredicate(
                        request.step,
                        initialTrace: request.initialTrace,
                        after: request.afterSequence,
                        observationPlan: observationPlan,
                        allowsTransitionFinalStateWarning: allowsTransitionFinalStateWarning,
                        announcementCursorStrategy: request.announcementCursorStrategy
                    )
                },
                selectPredicateCase: { cases, timeout in
                    await brains.interactionObservation.waitForPredicateCases(cases, timeout: timeout)
                },
                observeSemanticState: { scope, sequence, timeout in
                    await brains.interactionObservation.observeSemanticState(scope: scope, after: sequence, timeout: timeout)
                }
            )
        }
    }

    private struct InvocationResolution {
        let requestedName: String
        let resolvedPath: [String]
        let resolvedName: String
        let definition: HeistPlan?
    }

    private struct InvocationExecutionContext {
        let invoke: HeistInvocationStep
        let path: String
        let start: CFAbsoluteTime
        let requestedName: String
        let intent: HeistStepIntent

        var argumentSummary: String? {
            invoke.argument == .none ? nil : invoke.runHeistSummary
        }
    }

    private struct InvocationExpectationContext {
        let source: WaitStep
        let resolved: ResolvedWaitStep
        let baseline: HeistWaitReceipt
    }

    private enum InvocationExpectationPreparation {
        case none
        case prepared(InvocationExpectationContext)
        case failed(HeistExecutionStepResult)
    }

    private enum InvocationExpectationOutcome {
        case notEvaluated
        case matched(HeistWaitReceipt)
        case failed(receipt: HeistWaitReceipt, detail: HeistFailureDetail)

        var receipt: HeistWaitReceipt? {
            switch self {
            case .notEvaluated:
                return nil
            case .matched(let receipt):
                return receipt
            case .failed(receipt: let receipt, detail: _):
                return receipt
            }
        }

    }

    private enum HeistExecutionPhase: Equatable, Sendable {
        case ready
        case aborted(failedPath: String)
        case completed(abortedPath: String?)

        var abortedPath: String? {
            switch self {
            case .completed(let abortedPath):
                return abortedPath
            case .ready, .aborted:
                return nil
            }
        }
    }

    private struct HeistExecutionTransitionRejection: Equatable, Sendable {
        let path: String
        let reason: String

        static func stepAfterCompletion(path: String) -> HeistExecutionTransitionRejection {
            HeistExecutionTransitionRejection(
                path: path,
                reason: "cannot begin heist step after execution completed"
            )
        }

        static func skipBeforeAbort(path: String) -> HeistExecutionTransitionRejection {
            HeistExecutionTransitionRejection(
                path: path,
                reason: "cannot skip heist step before execution aborts"
            )
        }

        static func executeAfterAbort(path: String) -> HeistExecutionTransitionRejection {
            HeistExecutionTransitionRejection(
                path: path,
                reason: "cannot execute heist step after execution aborts"
            )
        }

        static func appendAfterCompletion(path: String) -> HeistExecutionTransitionRejection {
            HeistExecutionTransitionRejection(
                path: path,
                reason: "cannot append heist step after execution completed"
            )
        }

        static func completeTwice(path: String) -> HeistExecutionTransitionRejection {
            HeistExecutionTransitionRejection(
                path: path,
                reason: "cannot complete heist plan twice"
            )
        }
    }

    private enum HeistStepTransitionResult: Equatable, Sendable {
        case accepted
        case rejected(HeistExecutionTransitionRejection)
    }

    private enum HeistStepTransition: Equatable, Sendable {
        case executed(HeistExecutionStepResult)
        case skipped(HeistExecutionStepResult, abortedPath: String)

        var path: String {
            switch self {
            case .executed(let result),
                 .skipped(let result, _):
                return result.path
            }
        }
    }

    private enum HeistStepLifecycleEvent: Equatable, Sendable {
        case transition(HeistStepTransition)
        case complete
        case reject(HeistExecutionTransitionRejection, result: HeistExecutionStepResult)
    }

    private enum HeistStepLifecycleEffect: Equatable, Sendable {
        case appendStep(HeistExecutionStepResult)
    }

    private typealias HeistStepLifecycleChange = StateChange<
        HeistExecutionPhase,
        HeistStepLifecycleEffect,
        HeistExecutionTransitionRejection
    >

    private struct HeistStepLifecycleMachine: SimpleStateMachine {
        func advance(_ state: HeistExecutionPhase, with event: HeistStepLifecycleEvent) -> HeistStepLifecycleChange {
            switch (state, event) {
            case (.ready, .transition(.executed(let result))):
                return .changed(
                    to: result.isFailure
                        ? .aborted(failedPath: result.firstFailedStep?.path ?? result.path)
                        : .ready,
                    effects: [.appendStep(result)]
                )
            case (.aborted, .transition(.skipped(let result, let abortedPath))):
                return .changed(
                    to: .aborted(failedPath: abortedPath),
                    effects: [.appendStep(result)]
                )
            case (.ready, .transition(let transition)):
                return .rejected(.skipBeforeAbort(path: transition.path), stayingIn: state)
            case (.aborted, .transition(let transition)):
                return .rejected(.executeAfterAbort(path: transition.path), stayingIn: state)
            case (.completed, .transition(let transition)):
                return .rejected(.appendAfterCompletion(path: transition.path), stayingIn: state)
            case (.ready, .complete):
                return .changed(to: .completed(abortedPath: nil))
            case (.aborted(let failedPath), .complete):
                return .changed(to: .completed(abortedPath: failedPath))
            case (.completed, .complete):
                return .rejected(.completeTwice(path: "$.body"), stayingIn: state)
            case (_, .reject(let rejection, let result)):
                return .changed(
                    to: .completed(abortedPath: rejection.path),
                    effects: [.appendStep(result)]
                )
            }
        }
    }

    private struct HeistExecutionAccumulator {
        private(set) var steps: [HeistExecutionStepResult] = []
        private var lifecycle = StateDriver(
            initial: HeistExecutionPhase.ready,
            machine: HeistStepLifecycleMachine()
        )

        private var phase: HeistExecutionPhase {
            lifecycle.state
        }

        var abortedPath: String? {
            phase.abortedPath
        }

        func decision(for path: String) -> HeistExecutionStepDecision {
            switch phase {
            case .ready:
                return .execute
            case .aborted(let failedPath):
                return .skip(abortedPath: failedPath)
            case .completed:
                return .reject(.stepAfterCompletion(path: path))
            }
        }

        mutating func apply(_ transition: HeistStepTransition) -> HeistStepTransitionResult {
            let change = lifecycle.send(.transition(transition))
            return record(change)
        }

        mutating func complete() -> HeistStepTransitionResult {
            let change = lifecycle.send(.complete)
            return record(change)
        }

        mutating func reject(_ rejection: HeistExecutionTransitionRejection, result: HeistExecutionStepResult) {
            let change = lifecycle.send(.reject(rejection, result: result))
            record(change)
        }

        @discardableResult
        private mutating func record(_ change: HeistStepLifecycleChange) -> HeistStepTransitionResult {
            for effect in change.effects {
                switch effect {
                case .appendStep(let result):
                    steps.append(result)
                }
            }

            switch change {
            case .changed:
                return .accepted
            case .rejected(let rejection, _):
                return .rejected(rejection)
            }
        }
    }

    private enum HeistExecutionStepDecision: Equatable, Sendable {
        case execute
        case skip(abortedPath: String)
        case reject(HeistExecutionTransitionRejection)
    }

    func executeHeistPlan(_ plan: HeistPlan, argument: HeistArgument = .none) async -> ActionResult {
        guard semanticObservationIsActive else {
            return runtimeInactiveResult(method: .heistPlan)
        }
        return await executeHeistPlan(plan, argument: argument, runtime: .live(self))
    }

    func executeHeistPlanForTest(
        _ plan: HeistPlan,
        argument: HeistArgument = .none,
        runtime: HeistExecutionRuntime
    ) async -> ActionResult {
        await executeHeistPlan(plan, argument: argument, runtime: runtime)
    }

    private func executeHeistPlan(
        _ plan: HeistPlan,
        argument: HeistArgument,
        runtime: HeistExecutionRuntime
    ) async -> ActionResult {
        let notificationScope = stash.accessibilityNotifications.beginHeistScope()
        interactionObservation.resetAnnouncementWaitCursorForHeist()
        defer { notificationScope.cancel() }

        let demand = stash.beginSemanticObservationDemand(scope: .visible)
        defer { demand.cancel() }

        let heistStart = CFAbsoluteTimeGetCurrent()
        let environment: HeistExecutionEnvironment
        do {
            environment = try HeistExecutionEnvironment.empty.binding(argument: argument, to: plan.parameter)
        } catch {
            return .failure(
                method: .heistPlan,
                errorKind: .validationError,
                message: "Could not bind root heist argument: \(error)"
            )
        }
        let execution = await executeHeistStepAccumulator(
            plan.body,
            runtime: runtime,
            environment: environment,
            scope: HeistExecutionScope(plan: plan),
            path: "$.body"
        )
        var stepResults = execution.steps
        let abortedAtPath = execution.abortedPath
        if let failedPath = abortedAtPath,
           let mode = failureEvidencePolicy.captureMode,
           let failureScreenshotStep = await failureScreenshotStep(
            runtime: runtime,
            failedPath: failedPath,
            mode: mode
           ) {
            stepResults.append(failureScreenshotStep)
        }
        let durationMs = Int((CFAbsoluteTimeGetCurrent() - heistStart) * 1000)
        let heistResult: HeistExecutionResult
        if let abortedAtPath {
            heistResult = .failed(
                steps: stepResults,
                durationMs: durationMs,
                abortedAtPath: abortedAtPath
            )
        } else {
            heistResult = .passed(
                steps: stepResults,
                durationMs: durationMs
            )
        }

        let message = heistExecutionMessage(
            completedCount: stepResults.count,
            abortedAtPath: abortedAtPath
        )

        if abortedAtPath == nil {
            return .success(payload: .heistExecution(heistResult), message: message)
        }
        return .failure(payload: .heistExecution(heistResult), errorKind: .actionFailed, message: message)
    }

    private func failureScreenshotStep(
        runtime: HeistExecutionRuntime,
        failedPath: String,
        mode: ScreenCaptureMode
    ) async -> HeistExecutionStepResult? {
        let start = CFAbsoluteTimeGetCurrent()
        let result = mode == .raw
            ? await runtime.execute(.takeScreenshot)
            : await executeTakeScreenshot(mode: mode)
        guard result.method == .takeScreenshot else { return nil }
        let command = HeistActionCommand.takeScreenshot
        let evidence = HeistActionEvidence.dispatch(command: command, dispatchResult: result)
        let outcome: HeistStepReceiptOutcome
        if let failure = failureScreenshotDetail(for: result) {
            outcome = .failed(evidence: .action(evidence), failure: failure)
        } else {
            outcome = .passed(evidence: .action(evidence))
        }
        return heistActionReceipt(
            path: "\(failedPath).failure.actions[0]",
            durationMs: elapsedMilliseconds(since: start),
            intent: .action(command: command),
            outcome: outcome
        )
    }

    private func failureScreenshotDetail(for result: ActionResult) -> HeistFailureDetail? {
        guard !result.outcome.isSuccess else { return nil }
        return HeistFailureDetail(
            category: .action,
            contract: "failure screenshot action captures visible screen",
            observed: result.message ?? "screenshot action failed",
            expected: HeistActionCommandType.takeScreenshot.rawValue
        )
    }

    func executeHeistSteps(
        _ steps: [HeistStep],
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment,
        scope: HeistExecutionScope,
        path: String = "$.body"
    ) async -> [HeistExecutionStepResult] {
        let accumulator = await executeHeistStepAccumulator(
            steps,
            runtime: runtime,
            environment: environment,
            scope: scope,
            path: path
        )
        return accumulator.steps
    }

    private func executeHeistStepAccumulator(
        _ steps: [HeistStep],
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment,
        scope: HeistExecutionScope,
        path: String
    ) async -> HeistExecutionAccumulator {
        var accumulator = HeistExecutionAccumulator()

        for (index, step) in steps.enumerated() {
            let stepPath = "\(path)[\(index)]"

            switch accumulator.decision(for: stepPath) {
            case .skip(let abortedPath):
                let transition = accumulator.apply(.skipped(
                    skippedHeistStep(step, path: stepPath, scope: scope),
                    abortedPath: abortedPath
                ))
                if case .rejected(let rejection) = transition {
                    return rejectedAccumulator(rejecting: rejection, accumulated: accumulator)
                }
                continue

            case .execute:
                let stepResult = await executeHeistStep(
                    step,
                    index: index,
                    path: stepPath,
                    runtime: runtime,
                    environment: environment,
                    scope: scope
                )
                let transition = accumulator.apply(.executed(stepResult))
                if case .rejected(let rejection) = transition {
                    return rejectedAccumulator(rejecting: rejection, accumulated: accumulator)
                }

            case .reject(let rejection):
                return rejectedAccumulator(rejecting: rejection, accumulated: accumulator)
            }
        }

        let completion = accumulator.complete()
        if case .rejected(let rejection) = completion {
            return rejectedAccumulator(rejecting: rejection, accumulated: accumulator)
        }
        return accumulator
    }

    private func rejectedAccumulator(
        rejecting rejection: HeistExecutionTransitionRejection,
        accumulated accumulator: HeistExecutionAccumulator
    ) -> HeistExecutionAccumulator {
        var rejected = accumulator
        rejected.reject(
            rejection,
            result: heistTransitionRejectionResult(rejection)
        )
        return rejected
    }

    private func heistTransitionRejectionResult(
        _ rejection: HeistExecutionTransitionRejection
    ) -> HeistExecutionStepResult {
        heistExplicitFailureReceipt(
            path: rejection.path,
            durationMs: 0,
            intent: .fail(message: rejection.reason),
            failure: HeistFailureDetail(
                category: .validation,
                contract: "heist execution state transitions are valid",
                observed: rejection.reason
            )
        )
    }

    private func skippedHeistStep(
        _ step: HeistStep,
        path: String,
        scope: HeistExecutionScope
    ) -> HeistExecutionStepResult {
        let kind: HeistExecutionStepKind
        let children: [HeistExecutionStepResult]

        switch step {
        case .action:
            kind = .action
            children = []
        case .wait:
            kind = .wait
            children = []
        case .conditional:
            kind = .conditional
            children = []
        case .forEachElement:
            kind = .forEachElement
            children = []
        case .forEachString:
            kind = .forEachString
            children = []
        case .repeatUntil:
            kind = .repeatUntil
            children = []
        case .warn:
            kind = .warn
            children = []
        case .fail:
            kind = .fail
            children = []
        case .heist(let plan):
            kind = .heist
            children = skippedHeistSteps(plan.body, path: "\(path).heist.body", scope: scope)
        case .invoke:
            kind = .invoke
            children = []
        }

        return heistSkippedReceipt(
            path: path,
            kind: kind,
            children: children
        )
    }

    private func skippedHeistSteps(
        _ steps: [HeistStep],
        path: String,
        scope: HeistExecutionScope
    ) -> [HeistExecutionStepResult] {
        steps.enumerated().map { index, step in
            skippedHeistStep(step, path: "\(path)[\(index)]", scope: scope)
        }
    }

    private func executeHeistStep(
        _ step: HeistStep,
        index: Int,
        path: String,
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment,
        scope: HeistExecutionScope
    ) async -> HeistExecutionStepResult {
        let start = CFAbsoluteTimeGetCurrent()
        switch step {
        case .action(let action):
            return await executeActionStep(
                action,
                index: index,
                path: path,
                start: start,
                runtime: runtime,
                environment: environment
            )
        case .wait(let waitStep):
            return await executeWaitStep(
                waitStep,
                index: index,
                path: path,
                start: start,
                runtime: runtime,
                environment: environment,
                scope: scope
            )
        case .conditional(let conditional):
            return await executeConditionalStep(
                conditional,
                index: index,
                path: path,
                start: start,
                runtime: runtime,
                environment: environment,
                scope: scope
            )
        case .forEachElement(let forEach):
            return await executeForEachElementStep(
                forEach,
                index: index,
                path: path,
                start: start,
                runtime: runtime,
                environment: environment,
                scope: scope
            )
        case .forEachString(let forEach):
            return await executeForEachStringStep(
                forEach,
                index: index,
                path: path,
                start: start,
                runtime: runtime,
                environment: environment,
                scope: scope
            )
        case .repeatUntil(let repeatUntil):
            return await executeRepeatUntilStep(
                repeatUntil,
                index: index,
                path: path,
                start: start,
                runtime: runtime,
                environment: environment,
                scope: scope
            )
        case .warn(let warn):
            return executeWarnStep(warn, path: path, start: start)
        case .fail(let fail):
            return executeFailStep(fail, path: path, start: start)
        case .heist(let plan):
            return await executeInlineHeistStep(
                plan,
                index: index,
                path: path,
                start: start,
                runtime: runtime,
                environment: environment,
                scope: scope
            )
        case .invoke(let invoke):
            return await executeInvocationStep(
                invoke,
                index: index,
                path: path,
                start: start,
                runtime: runtime,
                environment: environment,
                scope: scope
            )
        }
    }

    private func executeWarnStep(
        _ warn: WarnStep,
        path: String,
        start: CFAbsoluteTime
    ) -> HeistExecutionStepResult {
        return heistWarningReceipt(
            path: path,
            durationMs: elapsedMilliseconds(since: start),
            intent: .warn(message: warn.message),
            warning: HeistExecutionWarning(path: path, message: warn.message)
        )
    }

    private func executeFailStep(
        _ fail: FailStep,
        path: String,
        start: CFAbsoluteTime
    ) -> HeistExecutionStepResult {
        return heistExplicitFailureReceipt(
            path: path,
            durationMs: elapsedMilliseconds(since: start),
            intent: .fail(message: fail.message),
            failure: HeistFailureDetail(
                category: .explicitFailure,
                contract: "explicit heist failure",
                observed: fail.message
            )
        )
    }

    private func executeInlineHeistStep(
        _ plan: HeistPlan,
        index _: Int,
        path: String,
        start: CFAbsoluteTime,
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment,
        scope: HeistExecutionScope
    ) async -> HeistExecutionStepResult {
        let children = await executeHeistSteps(
            plan.body,
            runtime: runtime,
            environment: environment,
            scope: HeistExecutionScope(
                plan: plan,
                rootPlan: plan,
                definitionPath: scope.definitionPath,
                invocationStack: scope.invocationStack
            ),
            path: "\(path).heist.body"
        )
        let childExecution = HeistReceiptChildren(children)
        return heistChildParentReceipt(
            path: path,
            kind: .heist,
            durationMs: elapsedMilliseconds(since: start),
            intent: .heist(name: plan.name),
            evidence: .invocation(.heist(
                name: plan.name.map { "heist \($0)" } ?? "inline heist",
                childFailedPath: childExecution.abortedAtChildPath
            )),
            childFailureCategory: .invocation,
            children: childExecution
        )
    }

    private func executeInvocationStep(
        _ invoke: HeistInvocationStep,
        index _: Int,
        path: String,
        start: CFAbsoluteTime,
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment,
        scope: HeistExecutionScope
    ) async -> HeistExecutionStepResult {
        let resolution = resolveInvocation(invoke, scope: scope)
        let context = InvocationExecutionContext(
            invoke: invoke,
            path: path,
            start: start,
            requestedName: resolution.requestedName,
            intent: invocationIntent(invoke, invocationName: resolution.requestedName)
        )
        guard !scope.invocationStack.contains(resolution.resolvedName) else {
            return recursiveInvocationResult(context: context, resolvedInvocationName: resolution.resolvedName)
        }
        guard let definition = resolution.definition else {
            return unknownInvocationResult(context: context)
        }

        let childEnvironment: HeistExecutionEnvironment
        do {
            childEnvironment = try environment.binding(argument: invoke.argument, to: definition.parameter)
        } catch {
            return invocationBindingFailureResult(context: context, error: error)
        }

        let expectationContext: InvocationExpectationContext?
        switch await prepareInvocationExpectation(context: context, environment: environment, runtime: runtime) {
        case .none:
            expectationContext = nil
        case .prepared(let prepared):
            expectationContext = prepared
        case .failed(let result):
            return result
        }

        let children = await executeHeistSteps(
            definition.body,
            runtime: runtime,
            environment: childEnvironment,
            scope: HeistExecutionScope(
                plan: definition,
                rootPlan: scope.rootPlan,
                definitionPath: resolution.resolvedPath,
                invocationStack: scope.invocationStack.union([resolution.resolvedName])
            ),
            path: "\(path).invoke.body"
        )
        let childExecution = HeistReceiptChildren(children)
        let expectationOutcome = await evaluateInvocationExpectation(
            expectationContext,
            runtime: runtime,
            childExecution: childExecution
        )
        return completedInvocationResult(
            context: context,
            childExecution: childExecution,
            expectationContext: expectationContext,
            expectationOutcome: expectationOutcome
        )
    }

    private func resolveInvocation(
        _ invoke: HeistInvocationStep,
        scope: HeistExecutionScope
    ) -> InvocationResolution {
        let requestedName = invoke.path.joined(separator: ".")
        let localDefinition = scope.plan.heistDefinition(at: invoke.path)
        let rootDefinition = invoke.path.count > 1 ? scope.rootPlan.heistDefinition(at: invoke.path) : nil
        let resolvedPath = localDefinition == nil && rootDefinition != nil
            ? invoke.path
            : scope.definitionPath + invoke.path
        return InvocationResolution(
            requestedName: requestedName,
            resolvedPath: resolvedPath,
            resolvedName: resolvedPath.joined(separator: "."),
            definition: localDefinition ?? rootDefinition
        )
    }

    private func invocationIntent(
        _ invoke: HeistInvocationStep,
        invocationName: String
    ) -> HeistStepIntent {
        HeistStepIntent.invoke(
            path: invoke.invocationPath,
            argument: invoke.argument
        )
    }

    private func recursiveInvocationResult(
        context: InvocationExecutionContext,
        resolvedInvocationName: String
    ) -> HeistExecutionStepResult {
        let observed = "recursive heist run \(resolvedInvocationName)"
        return heistInvocationReceipt(
            path: context.path,
            durationMs: elapsedMilliseconds(since: context.start),
            intent: context.intent,
            outcome: .failed(
                evidence: .invocation(HeistInvocationEvidence.invocation(
                    context.invoke,
                    name: context.requestedName
                )),
                failure: HeistFailureDetail(
                    category: .invocation,
                    contract: "heist invocation must not recurse",
                    observed: observed
                ),
                children: .empty
            )
        )
    }

    private func unknownInvocationResult(
        context: InvocationExecutionContext
    ) -> HeistExecutionStepResult {
        let observed = "unknown heist run \(context.requestedName)"
        return heistInvocationReceipt(
            path: context.path,
            durationMs: elapsedMilliseconds(since: context.start),
            intent: context.intent,
            outcome: .failed(
                evidence: .invocation(HeistInvocationEvidence.invocation(
                    context.invoke,
                    name: context.requestedName
                )),
                failure: HeistFailureDetail(
                    category: .invocation,
                    contract: "heist invocation path resolves to a definition",
                    observed: observed,
                    expected: context.requestedName
                ),
                children: .empty
            )
        )
    }

    private func invocationBindingFailureResult(
        context: InvocationExecutionContext,
        error: Error
    ) -> HeistExecutionStepResult {
        let observed = "could not bind heist run argument: \(error)"
        return heistInvocationReceipt(
            path: context.path,
            durationMs: elapsedMilliseconds(since: context.start),
            intent: context.intent,
            outcome: .failed(
                evidence: .invocation(HeistInvocationEvidence.invocation(
                    context.invoke,
                    name: context.requestedName
                )),
                failure: HeistFailureDetail(
                    category: .validation,
                    contract: "heist invocation argument binds to the target parameter",
                    observed: observed
                ),
                children: .empty
            )
        )
    }

    private func prepareInvocationExpectation(
        context: InvocationExecutionContext,
        environment: HeistExecutionEnvironment,
        runtime: HeistExecutionRuntime
    ) async -> InvocationExpectationPreparation {
        guard let expectation = context.invoke.expectation else { return .none }
        let resolved: ResolvedWaitStep
        do {
            resolved = try expectation.resolve(in: environment)
        } catch {
            return .failed(invocationExpectationResolutionFailureResult(
                context: context,
                expectation: expectation,
                error: error
            ))
        }
        let baseline = await runtime.wait(
            .immediate(ResolvedWaitStep(predicate: resolved.predicate, timeout: immediateTimeout))
        )
        return .prepared(InvocationExpectationContext(
            source: expectation,
            resolved: resolved,
            baseline: baseline
        ))
    }

    private func invocationExpectationResolutionFailureResult(
        context: InvocationExecutionContext,
        expectation: WaitStep,
        error: Error
    ) -> HeistExecutionStepResult {
        let observed = "could not resolve heist run expectation: \(error)"
        let expectationActionResult = ActionResult.failure(
            method: .wait,
            errorKind: .actionFailed,
            message: observed
        )
        let expectationResult = ExpectationResult(
            met: false,
            predicate: nil,
            actual: observed
        )
        return heistInvocationReceipt(
            path: context.path,
            durationMs: elapsedMilliseconds(since: context.start),
            intent: context.intent,
            outcome: .failed(
                evidence: .invocation(HeistInvocationEvidence.invocation(
                    context.invoke,
                    name: context.requestedName,
                    argument: context.argumentSummary,
                    expectation: .init(
                        actionResult: expectationActionResult,
                        expectation: expectationResult
                    )
                )),
                failure: HeistFailureDetail(
                    category: .expectation,
                    contract: "heist invocation expectation predicate resolves before evaluation",
                    observed: observed,
                    expected: expectation.predicate.description
                ),
                children: .empty
            )
        )
    }

    private func evaluateInvocationExpectation(
        _ context: InvocationExpectationContext?,
        runtime: HeistExecutionRuntime,
        childExecution: HeistReceiptChildren
    ) async -> InvocationExpectationOutcome {
        guard childExecution.abortedAtChildPath == nil, let context else { return .notEvaluated }
        let receipt: HeistWaitReceipt
        if let observedSequence = context.baseline.observedSequence {
            receipt = await runtime.wait(.afterObservation(
                context.resolved,
                baselineTrace: context.baseline.actionResult.accessibilityTrace,
                sequence: observedSequence
            ))
        } else {
            receipt = await runtime.wait(.baselineTraceOnly(
                context.resolved,
                trace: context.baseline.actionResult.accessibilityTrace
            ))
        }
        guard let failure = invocationExpectationFailure(expectation: context.source, receipt: receipt) else {
            return .matched(receipt)
        }
        return .failed(receipt: receipt, detail: failure)
    }

    private func completedInvocationResult(
        context: InvocationExecutionContext,
        childExecution: HeistReceiptChildren,
        expectationContext: InvocationExpectationContext?,
        expectationOutcome: InvocationExpectationOutcome
    ) -> HeistExecutionStepResult {
        let expectationEvidence = expectationOutcome.receipt.map {
            invocationExpectationEvidence(receipt: $0, context: expectationContext)
        }
        let invocationExpectation = expectationEvidence.map {
            HeistInvocationEvidence.InvocationExpectationEvidence(
                actionResult: $0.actionResult,
                expectation: $0.expectation,
                waitEvidence: $0
            )
        }
        let evidence = HeistInvocationEvidence.invocation(
            context.invoke,
            name: context.requestedName,
            argument: context.argumentSummary,
            childFailedPath: childExecution.abortedAtChildPath,
            expectation: invocationExpectation
        )
        let outcome: HeistStepReceiptOutcome
        switch expectationOutcome {
        case .notEvaluated, .matched:
            outcome = childAwarePassedOutcome(
                evidence: .invocation(evidence),
                children: childExecution,
                childFailure: { childPath in
                    childFailureDetail(category: .invocation, childPath: childPath)
                }
            )
        case .failed(receipt: _, detail: let detail):
            outcome = childAwareFailedOutcome(
                evidence: .invocation(evidence),
                failure: detail,
                children: childExecution,
                childFailure: { childPath in
                    childFailureDetail(category: .invocation, childPath: childPath)
                }
            )
        }
        return heistInvocationReceipt(
            path: context.path,
            durationMs: elapsedMilliseconds(since: context.start),
            intent: context.intent,
            outcome: outcome
        )
    }

    private func invocationExpectationEvidence(
        receipt: HeistWaitReceipt,
        context: InvocationExpectationContext?
    ) -> HeistWaitEvidence {
        let finalSummary = receipt.observationSummary ?? receipt.expectation.actual
        if let expectation = MetExpectationResult(receipt.expectation),
           let check = HeistWaitEvidence.MatchedCheck(
               actionResult: receipt.actionResult,
               expectation: expectation
           ) {
            return .matched(
                check,
                baselineSummary: context?.baseline.observationSummary,
                finalSummary: finalSummary,
                warning: receipt.warning
            )
        }
        guard let check = HeistWaitEvidence.UnmatchedCheck(
            actionResult: receipt.actionResult,
            expectation: receipt.expectation
        ) else {
            preconditionFailure("Failed invocation expectation evidence requires a failed action result or unmet expectation")
        }
        return .failed(
            check,
            baselineSummary: context?.baseline.observationSummary,
            finalSummary: finalSummary,
            warning: receipt.warning
        )
    }

    private func invocationExpectationFailure(
        expectation: WaitStep,
        receipt: HeistWaitReceipt
    ) -> HeistFailureDetail? {
        guard !receipt.actionResult.outcome.isSuccess || !receipt.expectation.met else { return nil }
        return HeistFailureDetail(
            category: .expectation,
            contract: "heist invocation expectation is met",
            observed: expectationObserved(receipt),
            expected: expectation.predicate.description
        )
    }

    private func expectationObserved(_ receipt: HeistWaitReceipt) -> String {
        [
            receipt.expectation.actual,
            receipt.actionResult.message,
            receipt.actionResult.outcome.errorKind.map { "errorKind=\($0.rawValue)" },
            receipt.actionResult.settled.map { "settled=\($0)" },
        ].compactMap { $0 }.joined(separator: "; ")
    }

    func childFailureDetail(category: HeistFailureCategory, childPath: String) -> HeistFailureDetail {
        HeistFailureDetail(
            category: category,
            contract: "child execution completes without failure",
            observed: "child failed at \(childPath)",
            expected: "all executed child steps pass"
        )
    }

    private func heistExecutionMessage(
        completedCount: Int,
        abortedAtPath: String?
    ) -> String {
        if let abortedAtPath {
            return "Heist execution stopped at \(abortedAtPath) after \(completedCount) executed step(s)"
        }
        return "Heist execution completed \(completedCount) step(s)"
    }

    func elapsedMilliseconds(since start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
