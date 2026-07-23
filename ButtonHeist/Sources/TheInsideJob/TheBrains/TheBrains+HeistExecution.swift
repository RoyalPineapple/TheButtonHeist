#if canImport(UIKit)
#if DEBUG
import Foundation

import ThePlans
@_spi(ButtonHeistInternals) import TheScore

// MARK: - Heist Execution

extension TheBrains {

    internal struct HeistExecutionScope {
        internal let rootPlan: HeistPlan
        internal let plan: HeistPlan
        internal var definitionPath: [HeistPlanName] = []
        internal var invocationStack: Set<HeistInvocationPath> = []

        internal init(
            plan: HeistPlan,
            rootPlan: HeistPlan? = nil,
            definitionPath: [HeistPlanName] = [],
            invocationStack: Set<HeistInvocationPath> = []
        ) {
            self.rootPlan = rootPlan ?? plan
            self.plan = plan
            self.definitionPath = definitionPath
            self.invocationStack = invocationStack
        }
    }

    internal enum HeistRuntimeWaitRequest: Equatable, Sendable {
        case standalone(ResolvedWaitRuntimeInput, startedAt: RuntimeElapsed.Instant)
        case actionEndpoint(
            ResolvedWaitRuntimeInput,
            trace: AccessibilityTrace?,
            context: ActionExpectationContext?
        )
        case immediate(ResolvedWaitRuntimeInput)
        case afterObservation(
            ResolvedWaitRuntimeInput,
            baselineTrace: AccessibilityTrace?,
            moment: Observation.Moment
        )
        case baselineTraceOnly(ResolvedWaitRuntimeInput, trace: AccessibilityTrace?)

        internal var step: ResolvedWaitRuntimeInput {
            switch self {
            case .standalone(let step, _),
                 .actionEndpoint(let step, _, _),
                 .immediate(let step),
                 .afterObservation(let step, _, _),
                 .baselineTraceOnly(let step, _):
                return step
            }
        }

        internal var initialTrace: AccessibilityTrace? {
            switch self {
            case .standalone,
                 .immediate:
                return nil
            case .actionEndpoint(_, let trace, _),
                 .afterObservation(_, let trace, _),
                 .baselineTraceOnly(_, let trace):
                return trace
            }
        }

        internal var startedAt: RuntimeElapsed.Instant? {
            switch self {
            case .standalone(_, let startedAt):
                return startedAt
            case .actionEndpoint,
                 .immediate,
                 .afterObservation,
                 .baselineTraceOnly:
                return nil
            }
        }

        internal var afterSequence: SettledObservationSequence? {
            switch self {
            case .standalone,
                 .immediate,
                 .baselineTraceOnly:
                return nil
            case .actionEndpoint(_, _, let context):
                return context?.preActionMoment.sequence
            case .afterObservation(_, _, let moment):
                return moment.sequence
            }
        }

        internal var changeBaseline: PredicateChangeBaselineSource {
            switch self {
            case .actionEndpoint(_, _, let context):
                .supplied(context?.preActionMoment)
            case .baselineTraceOnly:
                .supplied(nil)
            case .standalone, .immediate, .afterObservation:
                .establishFromFirstObservation
            }
        }

        internal var actionExpectationContext: ActionExpectationContext? {
            guard case .actionEndpoint(_, _, let context) = self else { return nil }
            return context
        }

    }

    internal struct HeistExecutionRuntime {
        internal let execute: @MainActor (
            ResolvedHeistActionCommand,
            ResolvedWaitRuntimeInput?
        ) async -> RuntimeActionExecution
        internal let wait: @MainActor (HeistRuntimeWaitRequest) async -> HeistWaitResult
        internal let selectPredicateCase: @MainActor ([ResolvedPredicateCaseRuntimeInput], Double) async -> HeistCaseSelectionResult
        internal let settledEvidence: @MainActor (SemanticObservationScope, SettledObservationSequence?, Double?) async -> SettledObservationEvidence?

        internal init(
            execute: @escaping @MainActor (
                ResolvedHeistActionCommand,
                ResolvedWaitRuntimeInput?
            ) async -> RuntimeActionExecution,
            wait: @escaping @MainActor (HeistRuntimeWaitRequest) async -> HeistWaitResult,
            selectPredicateCase: @escaping @MainActor ([ResolvedPredicateCaseRuntimeInput], Double) async -> HeistCaseSelectionResult,
            settledEvidence: @escaping @MainActor (SemanticObservationScope, SettledObservationSequence?, Double?) async -> SettledObservationEvidence?
        ) {
            self.execute = execute
            self.wait = wait
            self.selectPredicateCase = selectPredicateCase
            self.settledEvidence = settledEvidence
        }

        @MainActor
        internal static func live(_ brains: TheBrains) -> HeistExecutionRuntime {
            HeistExecutionRuntime(
                execute: { command, expectation in
                    await brains.executeRuntimeActionForHeist(
                        command,
                        expectation: expectation
                    )
                },
                wait: { request in
                    switch request {
                    case .standalone(let step, let startedAt):
                        return await brains.executeStandaloneWait(step, startedAt: startedAt)
                    case .afterObservation(let step, _, let moment):
                        return await brains.executeSettlementWait(
                            step,
                            baseline: .supplied(.init(moment: moment))
                        )
                    case .actionEndpoint, .immediate, .baselineTraceOnly:
                        return await brains.interactionCoordinator.waitForPredicate(
                            request.step,
                            initialTrace: request.initialTrace,
                            baselineSequence: request.afterSequence,
                            changeBaseline: request.changeBaseline,
                            actionExpectationContext: request.actionExpectationContext,
                            startedAt: request.startedAt
                        )
                    }
                },
                selectPredicateCase: { cases, timeout in
                    await brains.interactionCoordinator.waitForPredicateCases(cases, timeout: timeout)
                },
                settledEvidence: { scope, sequence, timeout in
                    await brains.interactionCoordinator.settledEvidence(scope: scope, after: sequence, timeout: timeout)
                }
            )
        }
    }

    internal func executeHeistPlan(_ plan: HeistPlan, argument: HeistArgument = .none) async -> ActionResult {
        guard semanticObservationIsActive else {
            return runtimeInactiveResult(payload: .heist(nil))
        }

        let demand = vault.semanticObservationStream.beginActiveObservationDemand()
        defer { demand.cancel() }
        if tripwire.isPulseRunning,
           await interactionCoordinator.refreshedVisibleBaseline() == nil {
            return await treeUnavailableResult(payload: .heist(nil))
        }
        return await executeHeistPlan(plan, argument: argument, runtime: .live(self))
    }

    internal func executeHeistPlanForTest(
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
        let notificationScope = vault.accessibilityNotifications.beginHeistScope()
        defer { notificationScope.cancel() }

        let demand = vault.semanticObservationStream.beginActiveObservationDemand()
        defer { demand.cancel() }

        let heistStart = RuntimeElapsed.now
        let environment: HeistExecutionEnvironment
        do {
            environment = try HeistExecutionEnvironment.empty.binding(argument: argument, to: plan.parameter)
        } catch {
            return .failure(
                payload: .heist(nil),
                failureKind: .validationError,
                message: "Could not bind root heist argument: \(error)"
            )
        }
        let execution = await executeHeistStepAccumulator(
            plan.body,
            runtime: runtime,
            environment: environment,
            scope: HeistExecutionScope(plan: plan),
            path: .body
        )
        var stepResults = execution.values
        let abortedAtPath = execution.abortedAtPath
        if let failedPath = abortedAtPath,
           let mode = failureEvidencePolicy.captureMode,
           let failureScreenshotStep = await failureScreenshotStep(
            runtime: runtime,
            failedPath: failedPath,
            mode: mode
           ) {
            stepResults.append(failureScreenshotStep)
        }
        let durationMs = elapsedMilliseconds(since: heistStart)
        let result: HeistResult
        do {
            result = try HeistResult(steps: stepResults, durationMs: durationMs)
        } catch {
            return .failure(
                payload: .heist(nil),
                failureKind: .validationError,
                message: "Could not admit heist execution result: \(error)"
            )
        }

        let message = heistExecutionMessage(
            completedCount: stepResults.count,
            abortedAtPath: abortedAtPath
        )

        if abortedAtPath == nil {
            return .success(payload: .heist(result), message: message)
        }
        return .failure(
            payload: .heist(result),
            failureKind: .actionFailed,
            message: message
        )
    }

    internal func executeHeistSteps(
        _ steps: [HeistStep],
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment,
        scope: HeistExecutionScope,
        path: HeistExecutionPath = .body
    ) async -> HeistExecutedChildren {
        await executeHeistStepAccumulator(
            steps,
            runtime: runtime,
            environment: environment,
            scope: scope,
            path: path
        )
    }

    private func executeHeistStepAccumulator(
        _ steps: [HeistStep],
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment,
        scope: HeistExecutionScope,
        path: HeistExecutionPath
    ) async -> HeistExecutedChildren {
        var children = HeistExecutedChildren.empty

        for (index, step) in steps.enumerated() {
            let stepPath = path.step(at: index)

            if children.abortedAtPath != nil {
                children.append(.skipped(path: stepPath, durationMs: 0, step: step))
                continue
            } else {
                let stepResult = await executeHeistStep(
                    step,
                    index: index,
                    path: stepPath,
                    runtime: runtime,
                    environment: environment,
                    scope: scope
                )
                children.append(stepResult)
            }
        }
        return children
    }

    private func executeHeistStep(
        _ step: HeistStep,
        index: Int,
        path: HeistExecutionPath,
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment,
        scope: HeistExecutionScope
    ) async -> HeistExecutionStepResult {
        let start = RuntimeElapsed.now
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

    private func executeInlineHeistStep(
        _ plan: HeistPlan,
        index _: Int,
        path: HeistExecutionPath,
        start: RuntimeElapsed.Instant,
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
            path: path.heistBody()
        )
        switch children {
        case .passed(let children):
            return .heist(
                path: path,
                durationMs: elapsedMilliseconds(since: start),
                name: plan.name,
                completion: .passed(children: children)
            )
        case .aborted(let children):
            return .heist(
                path: path,
                durationMs: elapsedMilliseconds(since: start),
                name: plan.name,
                completion: .childAborted(
                    failure: childFailureDetail(
                        category: .invocation,
                        childPath: children.abortedAtPath
                    ),
                    children: children
                )
            )
        }
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
