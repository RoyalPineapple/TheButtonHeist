#if canImport(UIKit)
#if DEBUG
import Foundation

import ThePlans
@_spi(ButtonHeistInternals) import TheScore

extension TheBrains {

    internal struct HeistExecutionScope {
        internal let rootPlan: HeistPlan
        internal let plan: HeistPlan
        internal var definitionPath: [String] = []
        internal var invocationStack: Set<String> = []

        internal init(
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

    internal enum HeistRuntimeWaitRequest: Equatable, Sendable {
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

        internal var step: ResolvedWaitStep {
            switch self {
            case .standalone(let step),
                 .actionEndpoint(let step, _),
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
            case .actionEndpoint(_, let trace),
                 .afterObservation(_, let trace, _),
                 .baselineTraceOnly(_, let trace):
                return trace
            }
        }

        internal var afterSequence: SettledObservationSequence? {
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
        internal let execute: @MainActor (RuntimeActionMessage) async -> ActionResult
        internal let wait: @MainActor (HeistRuntimeWaitRequest) async -> HeistWaitReceipt
        internal let selectPredicateCase: @MainActor ([ResolvedPredicateCase], Double) async -> HeistCaseSelectionResult
        internal let observeSemanticState: @MainActor (SemanticObservationScope, SettledObservationSequence?, Double?) async -> HeistSemanticObservation?

        internal init(
            execute: @escaping @MainActor (RuntimeActionMessage) async -> ActionResult,
            wait: @escaping @MainActor (HeistRuntimeWaitRequest) async -> HeistWaitReceipt,
            selectPredicateCase: @escaping @MainActor ([ResolvedPredicateCase], Double) async -> HeistCaseSelectionResult,
            observeSemanticState: @escaping @MainActor (SemanticObservationScope, SettledObservationSequence?, Double?) async -> HeistSemanticObservation?
        ) {
            self.execute = execute
            self.wait = wait
            self.selectPredicateCase = selectPredicateCase
            self.observeSemanticState = observeSemanticState
        }

        @MainActor
        internal static func live(_ brains: TheBrains) -> HeistExecutionRuntime {
            HeistExecutionRuntime(
                execute: { command in
                    await brains.executeRuntimeAction(command)
                },
                wait: { request in
                    let observationPlan = WaitObservationPlan(step: request.step)
                    return await brains.interactionObservation.waitForPredicate(
                        request.step,
                        initialTrace: request.initialTrace,
                        after: request.afterSequence,
                        observationPlan: observationPlan,
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

    internal func executeHeistPlan(_ plan: HeistPlan, argument: HeistArgument = .none) async -> ActionResult {
        guard semanticObservationIsActive else {
            return runtimeInactiveResult(method: .heistPlan)
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
        let notificationScope = stash.accessibilityNotifications.beginHeistScope()
        interactionObservation.resetAnnouncementWaitCursorForHeist(to: notificationScope.cursor)
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
                message: "Could not bind root heist argument: \(error)",
                evidence: .none
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
            return .success(payload: .heistExecution(heistResult), message: message, evidence: .none)
        }
        return .failure(
            payload: .heistExecution(heistResult),
            errorKind: .actionFailed,
            message: message,
            evidence: .none
        )
    }

    internal func executeHeistSteps(
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

}

#endif // DEBUG
#endif // canImport(UIKit)
