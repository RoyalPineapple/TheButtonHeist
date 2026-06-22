#if canImport(UIKit)
#if DEBUG
import Foundation

import ThePlans
@_spi(ButtonHeistInternals) import TheScore

extension TheBrains {

    struct HeistExecutionScope {
        let plan: HeistPlan
        var definitionPath: [String] = []
        var invocationStack: Set<String> = []
    }

    struct HeistExecutionRuntime {
        let execute: @MainActor (RuntimeActionMessage) async -> ActionResult
        let wait: @MainActor (ResolvedWaitStep, AccessibilityTrace?) async -> HeistWaitReceipt
        let selectPredicateCase: @MainActor ([ResolvedPredicateCase], Double) async -> HeistCaseSelectionResult
        let observeSemanticState: @MainActor (SemanticObservationScope, UInt64?, Double?) async -> HeistSemanticObservation?

        @MainActor
        static func live(_ brains: TheBrains) -> HeistExecutionRuntime {
            HeistExecutionRuntime(
                execute: { command in
                    await brains.executeRuntimeAction(command)
                },
                wait: { waitStep, initialTrace in
                    await brains.interactionObservation.waitForPredicate(waitStep, initialTrace: initialTrace)
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
        let demand = stash.beginSemanticObservationDemand(scope: .visible)
        defer { demand.cancel() }

        let heistStart = CFAbsoluteTimeGetCurrent()
        let environment: HeistExecutionEnvironment
        do {
            environment = try HeistExecutionEnvironment.empty.binding(argument: argument, to: plan.parameter)
        } catch {
            var builder = ActionResultBuilder(method: .heistPlan)
            builder.message = "Could not bind root heist argument: \(error)"
            return builder.failure(errorKind: .validationError)
        }
        let stepResults = await executeHeistSteps(
            plan.body,
            runtime: runtime,
            environment: environment,
            scope: HeistExecutionScope(plan: plan),
            path: "$.body"
        )
        let abortedAtPath = stepResults.firstFailedStep?.path
        let heistResult = HeistExecutionResult(
            steps: stepResults,
            durationMs: Int((CFAbsoluteTimeGetCurrent() - heistStart) * 1000),
            abortedAtPath: abortedAtPath
        )

        var builder = ActionResultBuilder(method: .heistPlan)
        builder.message = heistExecutionMessage(
            completedCount: stepResults.count,
            abortedAtPath: abortedAtPath
        )

        if abortedAtPath == nil {
            return builder.success(payload: .heistExecution(heistResult))
        }
        return builder.failure(errorKind: .actionFailed, payload: .heistExecution(heistResult))
    }

    func executeHeistSteps(
        _ steps: [HeistStep],
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment,
        scope: HeistExecutionScope,
        path: String = "$.body"
    ) async -> [HeistExecutionStepResult] {
        var stepResults: [HeistExecutionStepResult] = []
        var aborting = false

        for (index, step) in steps.enumerated() {
            let stepPath = "\(path)[\(index)]"
            guard !aborting else {
                stepResults.append(skippedHeistStep(step, path: stepPath, scope: scope))
                continue
            }
            let stepResult = await executeHeistStep(
                step,
                index: index,
                path: stepPath,
                runtime: runtime,
                environment: environment,
                scope: scope
            )
            stepResults.append(stepResult)

            if stepResult.isFailure {
                aborting = true
            }
        }

        return stepResults
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

        return HeistExecutionStepResult(
            path: path,
            kind: kind,
            status: .skipped,
            durationMs: 0,
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
        HeistExecutionStepResult(
            path: path,
            kind: .warn,
            status: .passed,
            durationMs: elapsedMilliseconds(since: start),
            intent: .warn(message: warn.message),
            evidence: .warning(HeistExecutionWarning(path: path, message: warn.message))
        )
    }

    private func executeFailStep(
        _ fail: FailStep,
        path: String,
        start: CFAbsoluteTime
    ) -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            path: path,
            kind: .fail,
            status: .failed,
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
                definitionPath: scope.definitionPath,
                invocationStack: scope.invocationStack
            ),
            path: "\(path).heist.body"
        )
        let abortedAtChildPath = children.firstFailedStep?.path
        return HeistExecutionStepResult(
            path: path,
            kind: .heist,
            status: abortedAtChildPath == nil ? .passed : .failed,
            durationMs: elapsedMilliseconds(since: start),
            intent: .heist(name: plan.name),
            evidence: .invocation(HeistInvocationEvidence(
                name: plan.name.map { "heist \($0)" } ?? "inline heist",
                childFailedPath: abortedAtChildPath
            )),
            failure: abortedAtChildPath.map {
                childFailureDetail(category: .invocation, childPath: $0)
            },
            abortedAtChildPath: abortedAtChildPath,
            children: children
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
        let invocationName = invoke.path.joined(separator: ".")
        let resolvedInvocationName = (scope.definitionPath + invoke.path).joined(separator: ".")
        let intent = HeistStepIntent.invoke(
            path: invocationName,
            argument: invoke.argument == .none ? nil : invoke.runHeistSummary
        )
        guard !scope.invocationStack.contains(resolvedInvocationName) else {
            let observed = "recursive heist run \(resolvedInvocationName)"
            return HeistExecutionStepResult(
                path: path,
                kind: .invoke,
                status: .failed,
                durationMs: elapsedMilliseconds(since: start),
                intent: intent,
                evidence: .invocation(HeistInvocationEvidence(invocation: invoke, name: invocationName)),
                failure: HeistFailureDetail(
                    category: .invocation,
                    contract: "heist invocation must not recurse",
                    observed: observed
                )
            )
        }
        guard let definition = scope.plan.heistDefinition(at: invoke.path) else {
            let observed = "unknown heist run \(invocationName)"
            return HeistExecutionStepResult(
                path: path,
                kind: .invoke,
                status: .failed,
                durationMs: elapsedMilliseconds(since: start),
                intent: intent,
                evidence: .invocation(HeistInvocationEvidence(invocation: invoke, name: invocationName)),
                failure: HeistFailureDetail(
                    category: .invocation,
                    contract: "heist invocation path resolves to a definition",
                    observed: observed,
                    expected: invocationName
                )
            )
        }
        let childEnvironment: HeistExecutionEnvironment
        do {
            childEnvironment = try environment.binding(argument: invoke.argument, to: definition.parameter)
        } catch {
            let observed = "could not bind heist run argument: \(error)"
            return HeistExecutionStepResult(
                path: path,
                kind: .invoke,
                status: .failed,
                durationMs: elapsedMilliseconds(since: start),
                intent: intent,
                evidence: .invocation(HeistInvocationEvidence(invocation: invoke, name: invocationName)),
                failure: HeistFailureDetail(
                    category: .validation,
                    contract: "heist invocation argument binds to the target parameter",
                    observed: observed
                )
            )
        }
        let children = await executeHeistSteps(
            definition.body,
            runtime: runtime,
            environment: childEnvironment,
            scope: HeistExecutionScope(
                plan: definition,
                definitionPath: scope.definitionPath + invoke.path,
                invocationStack: scope.invocationStack.union([resolvedInvocationName])
            ),
            path: "\(path).invoke.body"
        )
        let abortedAtChildPath = children.firstFailedStep?.path
        return HeistExecutionStepResult(
            path: path,
            kind: .invoke,
            status: abortedAtChildPath == nil ? .passed : .failed,
            durationMs: elapsedMilliseconds(since: start),
            intent: intent,
            evidence: .invocation(HeistInvocationEvidence(
                invocation: invoke,
                name: invocationName,
                argument: invoke.argument == .none ? nil : invoke.runHeistSummary,
                childFailedPath: abortedAtChildPath
            )),
            failure: abortedAtChildPath.map {
                childFailureDetail(category: .invocation, childPath: $0)
            },
            abortedAtChildPath: abortedAtChildPath,
            children: children
        )
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
