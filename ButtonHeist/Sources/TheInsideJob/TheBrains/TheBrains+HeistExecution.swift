#if canImport(UIKit)
#if DEBUG
import Foundation

import ThePlans
@_spi(ButtonHeistInternals) import TheScore

extension TheBrains {

    internal struct HeistStepExecution: Sendable, Equatable {
        internal let result: HeistExecutionStepResult
        internal let lastSuccessfulActionBoundary: EvidenceContinuity.Boundary?

        internal init(
            result: HeistExecutionStepResult,
            lastSuccessfulActionBoundary: EvidenceContinuity.Boundary? = nil
        ) {
            self.result = result
            self.lastSuccessfulActionBoundary = lastSuccessfulActionBoundary
        }
    }

    internal struct HeistExecutionAggregate: Sendable, Equatable {
        internal static let empty = HeistExecutionAggregate(
            children: .passed(.empty),
            lastSuccessfulActionBoundary: nil
        )

        internal let children: HeistExecutedChildren
        internal let lastSuccessfulActionBoundary: EvidenceContinuity.Boundary?

        internal func appending(_ step: HeistStepExecution) -> HeistExecutionAggregate {
            var nextChildren = children
            nextChildren.append(step.result)
            return HeistExecutionAggregate(
                children: nextChildren,
                lastSuccessfulActionBoundary: step.lastSuccessfulActionBoundary
                    ?? lastSuccessfulActionBoundary
            )
        }
    }

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
            baseline: SettledCapture?
        )
        case immediate(ResolvedWaitRuntimeInput)
        case afterObservation(
            ResolvedWaitRuntimeInput,
            baselineTrace: AccessibilityTrace?,
            sequence: SettledObservationSequence
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
            case .actionEndpoint(_, _, let baseline):
                return baseline?.cursor.sequence
            case .afterObservation(_, _, let sequence):
                return sequence
            }
        }

        internal var changeBaseline: PredicateChangeBaselineSource {
            switch self {
            case .actionEndpoint(_, _, let baseline):
                .supplied(baseline)
            case .baselineTraceOnly:
                .supplied(nil)
            case .standalone, .immediate, .afterObservation:
                .establishFromFirstObservation
            }
        }

        internal var announcementCursorStrategy: AnnouncementWaitCursorStrategy {
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

    internal struct HeistExecutionRuntime {
        internal let execute: @MainActor (
            ResolvedHeistActionCommand,
            SemanticObservationScope?
        ) async -> RuntimeActionExecution
        internal let wait: @MainActor (HeistRuntimeWaitRequest) async -> HeistWaitResult
        internal let selectPredicateCase: @MainActor ([ResolvedPredicateCaseRuntimeInput], Double) async -> HeistCaseSelectionResult
        internal let settledEvidence: @MainActor (SemanticObservationScope, SettledObservationSequence?, Double?) async -> SettledObservationEvidence?

        internal init(
            execute: @escaping @MainActor (
                ResolvedHeistActionCommand,
                SemanticObservationScope?
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
        internal static func live(
            _ brains: TheBrains,
            continuity: EvidenceContinuity.Reference? = nil
        ) -> HeistExecutionRuntime {
            HeistExecutionRuntime(
                execute: { command, expectationBaselineScope in
                    await brains.executeRuntimeActionWithBaseline(
                        command,
                        expectationBaselineScope: expectationBaselineScope
                    )
                },
                wait: { request in
                    let waitContinuity: PredicateWaitContinuity
                    switch request {
                    case .standalone:
                        waitContinuity = brains.admitWaitContinuity(
                            continuity,
                            for: request.step.predicate
                        )
                    case .actionEndpoint, .immediate, .afterObservation, .baselineTraceOnly:
                        waitContinuity = .notProvided
                    }
                    return await brains.interactionCoordinator.waitForPredicate(
                        request.step,
                        initialTrace: request.initialTrace,
                        baselineSequence: request.afterSequence,
                        changeBaseline: request.changeBaseline,
                        announcementCursorStrategy: request.announcementCursorStrategy,
                        continuity: waitContinuity,
                        startedAt: request.startedAt
                    )
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

    internal func executeHeistPlan(
        _ plan: HeistPlan,
        argument: HeistArgument = .none,
        continuity: EvidenceContinuity.Reference? = nil
    ) async -> ActionResult {
        guard semanticObservationIsActive else {
            return runtimeInactiveResult(payload: .heist(nil))
        }
        return await executeHeistPlan(
            plan,
            argument: argument,
            continuity: continuity,
            runtime: .live(self, continuity: continuity)
        )
    }

    internal func executeHeistPlanForTest(
        _ plan: HeistPlan,
        argument: HeistArgument = .none,
        continuity: EvidenceContinuity.Reference? = nil,
        runtime: HeistExecutionRuntime
    ) async -> ActionResult {
        await executeHeistPlan(
            plan,
            argument: argument,
            continuity: continuity,
            runtime: runtime
        )
    }

    private func executeHeistPlan(
        _ plan: HeistPlan,
        argument: HeistArgument,
        continuity: EvidenceContinuity.Reference?,
        runtime: HeistExecutionRuntime
    ) async -> ActionResult {
        let notificationScope = vault.accessibilityNotifications.beginHeistScope()
        interactionCoordinator.resetAnnouncementWaitCursorForHeist(to: notificationScope.cursor)
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
        var stepResults = execution.children.values
        let abortedAtPath = execution.children.abortedAtPath
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
        let evidenceContinuity = execution.lastSuccessfulActionBoundary.flatMap {
            evidenceContinuityStore.register($0)
        }
        let result: HeistResult
        do {
            result = try HeistResult(
                steps: stepResults,
                durationMs: durationMs,
                evidenceContinuity: evidenceContinuity
            )
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
    ) async -> HeistExecutionAggregate {
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
    ) async -> HeistExecutionAggregate {
        var execution = HeistExecutionAggregate.empty

        for (index, step) in steps.enumerated() {
            let stepPath = path.step(at: index)

            if execution.children.abortedAtPath != nil {
                execution = execution.appending(HeistStepExecution(
                    result: .skipped(path: stepPath, durationMs: 0, step: step)
                ))
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
                execution = execution.appending(stepResult)
            }
        }
        return execution
    }

    private func executeHeistStep(
        _ step: HeistStep,
        index: Int,
        path: HeistExecutionPath,
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment,
        scope: HeistExecutionScope
    ) async -> HeistStepExecution {
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
            return HeistStepExecution(result: executeWarnStep(warn, path: path, start: start))
        case .fail(let fail):
            return HeistStepExecution(result: executeFailStep(fail, path: path, start: start))
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
    ) async -> HeistStepExecution {
        let execution = await executeHeistSteps(
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
        let result: HeistExecutionStepResult
        switch execution.children {
        case .passed(let children):
            result = .heist(
                path: path,
                durationMs: elapsedMilliseconds(since: start),
                name: plan.name,
                completion: .passed(children: children)
            )
        case .aborted(let children):
            result = .heist(
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
        return HeistStepExecution(
            result: result,
            lastSuccessfulActionBoundary: execution.lastSuccessfulActionBoundary
        )
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
