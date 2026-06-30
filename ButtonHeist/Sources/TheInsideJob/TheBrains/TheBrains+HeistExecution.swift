#if canImport(UIKit)
#if DEBUG
import Foundation

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
                    await brains.interactionObservation.waitForPredicate(
                        request.step,
                        initialTrace: request.initialTrace,
                        after: request.afterSequence
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

    private enum HeistExecutionPhase: Equatable {
        case ready
        case executing(path: String)
        case aborted(failedPath: String)
        case completed
    }

    private struct HeistExecutionState {
        private(set) var phase: HeistExecutionPhase = .ready

        mutating func beginStep(at path: String) -> HeistExecutionStepDecision {
            switch phase {
            case .ready:
                phase = .executing(path: path)
                return .execute
            case .aborted(let failedPath):
                return .skip(abortedPath: failedPath)
            case .executing(let activePath):
                preconditionFailure(
                    "Cannot begin heist step \(path) while \(activePath) is executing"
                )
            case .completed:
                preconditionFailure("Cannot begin heist step \(path) after execution completed")
            }
        }

        mutating func finishStep(_ result: HeistExecutionStepResult) {
            guard case .executing = phase else {
                preconditionFailure(
                    "Cannot finish heist step \(result.path) while execution phase is \(phase)"
                )
            }
            phase = result.isFailure ? .aborted(failedPath: result.path) : .ready
        }

        mutating func finishPlan() -> HeistExecutionCompletion {
            switch phase {
            case .ready:
                phase = .completed
                return HeistExecutionCompletion(abortedPath: nil)
            case .aborted(let failedPath):
                phase = .completed
                return HeistExecutionCompletion(abortedPath: failedPath)
            case .executing(let activePath):
                preconditionFailure("Cannot complete heist plan while \(activePath) is executing")
            case .completed:
                preconditionFailure("Cannot complete heist plan twice")
            }
        }
    }

    private enum HeistExecutionStepDecision: Equatable {
        case execute
        case skip(abortedPath: String)
    }

    private struct HeistExecutionCompletion: Equatable {
        let abortedPath: String?
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
        var stepResults = await executeHeistSteps(
            plan.body,
            runtime: runtime,
            environment: environment,
            scope: HeistExecutionScope(plan: plan),
            path: "$.body"
        )
        let abortedAtPath = stepResults.firstFailedStep?.path
        if let abortedAtPath,
           let failureScreenshotStep = await failureScreenshotStep(
               runtime: runtime,
               failedPath: abortedAtPath
           ) {
            stepResults.append(failureScreenshotStep)
        }
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

    private func failureScreenshotStep(
        runtime: HeistExecutionRuntime,
        failedPath: String
    ) async -> HeistExecutionStepResult? {
        let start = CFAbsoluteTimeGetCurrent()
        let result = await runtime.execute(.takeScreenshot)
        guard result.method == .takeScreenshot else { return nil }
        let command = HeistActionCommand.takeScreenshot
        return heistActionReceipt(
            path: "\(failedPath).failure.actions[0]",
            durationMs: elapsedMilliseconds(since: start),
            intent: .action(command: command.wireType.rawValue, target: nil),
            evidence: HeistActionEvidence(command: command, actionResult: result),
            failure: failureScreenshotDetail(for: result)
        )
    }

    private func failureScreenshotDetail(for result: ActionResult) -> HeistFailureDetail? {
        guard !result.success else { return nil }
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
        var stepResults: [HeistExecutionStepResult] = []
        var executionState = HeistExecutionState()

        for (index, step) in steps.enumerated() {
            let stepPath = "\(path)[\(index)]"

            switch executionState.beginStep(at: stepPath) {
            case .skip:
                stepResults.append(skippedHeistStep(step, path: stepPath, scope: scope))
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
                stepResults.append(stepResult)
                executionState.finishStep(stepResult)
            }
        }

        _ = executionState.finishPlan()
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
        heistWarningReceipt(
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
        heistExplicitFailureReceipt(
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
        return heistChildParentReceipt(
            path: path,
            kind: .heist,
            durationMs: elapsedMilliseconds(since: start),
            intent: .heist(name: plan.name),
            evidence: .invocation(HeistInvocationEvidence(
                name: plan.name.map { "heist \($0)" } ?? "inline heist",
                childFailedPath: children.firstFailedStep?.path
            )),
            childFailureCategory: .invocation,
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
        let abortedAtChildPath = children.firstFailedStep?.path
        let expectationReceipt = await evaluateInvocationExpectation(
            expectationContext,
            runtime: runtime,
            childFailed: abortedAtChildPath != nil
        )
        let failure = invocationFailure(
            abortedAtChildPath: abortedAtChildPath,
            expectationContext: expectationContext,
            expectationReceipt: expectationReceipt
        )
        return completedInvocationResult(
            context: context,
            children: children,
            abortedAtChildPath: abortedAtChildPath,
            expectationReceipt: expectationReceipt,
            failure: failure
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
            path: invocationName,
            argument: invoke.argument == .none ? nil : invoke.runHeistSummary
        )
    }

    private func recursiveInvocationResult(
        context: InvocationExecutionContext,
        resolvedInvocationName: String
    ) -> HeistExecutionStepResult {
        let observed = "recursive heist run \(resolvedInvocationName)"
        return heistFailedReceipt(
            path: context.path,
            kind: .invoke,
            durationMs: elapsedMilliseconds(since: context.start),
            intent: context.intent,
            evidence: .invocation(HeistInvocationEvidence(invocation: context.invoke, name: context.requestedName)),
            failure: HeistFailureDetail(
                category: .invocation,
                contract: "heist invocation must not recurse",
                observed: observed
            )
        )
    }

    private func unknownInvocationResult(
        context: InvocationExecutionContext
    ) -> HeistExecutionStepResult {
        let observed = "unknown heist run \(context.requestedName)"
        return heistFailedReceipt(
            path: context.path,
            kind: .invoke,
            durationMs: elapsedMilliseconds(since: context.start),
            intent: context.intent,
            evidence: .invocation(HeistInvocationEvidence(invocation: context.invoke, name: context.requestedName)),
            failure: HeistFailureDetail(
                category: .invocation,
                contract: "heist invocation path resolves to a definition",
                observed: observed,
                expected: context.requestedName
            )
        )
    }

    private func invocationBindingFailureResult(
        context: InvocationExecutionContext,
        error: Error
    ) -> HeistExecutionStepResult {
        let observed = "could not bind heist run argument: \(error)"
        return heistFailedReceipt(
            path: context.path,
            kind: .invoke,
            durationMs: elapsedMilliseconds(since: context.start),
            intent: context.intent,
            evidence: .invocation(HeistInvocationEvidence(
                invocation: context.invoke,
                name: context.requestedName
            )),
            failure: HeistFailureDetail(
                category: .validation,
                contract: "heist invocation argument binds to the target parameter",
                observed: observed
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
        var builder = ActionResultBuilder(method: .wait)
        builder.message = observed
        let expectationActionResult = builder.failure(errorKind: .actionFailed)
        let expectationResult = ExpectationResult(
            met: false,
            predicate: nil,
            actual: observed
        )
        return heistFailedReceipt(
            path: context.path,
            kind: .invoke,
            durationMs: elapsedMilliseconds(since: context.start),
            intent: context.intent,
            evidence: .invocation(HeistInvocationEvidence(
                invocation: context.invoke,
                name: context.requestedName,
                argument: context.argumentSummary,
                expectationActionResult: expectationActionResult,
                expectation: expectationResult
            )),
            failure: HeistFailureDetail(
                category: .expectation,
                contract: "heist invocation expectation predicate resolves before evaluation",
                observed: observed,
                expected: expectation.predicate.description
            )
        )
    }

    private func evaluateInvocationExpectation(
        _ context: InvocationExpectationContext?,
        runtime: HeistExecutionRuntime,
        childFailed: Bool
    ) async -> HeistWaitReceipt? {
        guard !childFailed, let context else { return nil }
        if let observedSequence = context.baseline.observedSequence {
            return await runtime.wait(.afterObservation(
                context.resolved,
                baselineTrace: context.baseline.actionResult.accessibilityTrace,
                sequence: observedSequence
            ))
        }
        return await runtime.wait(.baselineTraceOnly(
            context.resolved,
            trace: context.baseline.actionResult.accessibilityTrace
        ))
    }

    private func invocationFailure(
        abortedAtChildPath: String?,
        expectationContext: InvocationExpectationContext?,
        expectationReceipt: HeistWaitReceipt?
    ) -> HeistFailureDetail? {
        if let abortedAtChildPath {
            return childFailureDetail(category: .invocation, childPath: abortedAtChildPath)
        }
        guard let expectationContext, let expectationReceipt else { return nil }
        return invocationExpectationFailure(expectation: expectationContext.source, receipt: expectationReceipt)
    }

    private func completedInvocationResult(
        context: InvocationExecutionContext,
        children: [HeistExecutionStepResult],
        abortedAtChildPath: String?,
        expectationReceipt: HeistWaitReceipt?,
        failure: HeistFailureDetail?
    ) -> HeistExecutionStepResult {
        heistChildParentReceipt(
            path: context.path,
            kind: .invoke,
            durationMs: elapsedMilliseconds(since: context.start),
            intent: context.intent,
            evidence: .invocation(HeistInvocationEvidence(
                invocation: context.invoke,
                name: context.requestedName,
                argument: context.argumentSummary,
                childFailedPath: abortedAtChildPath,
                expectationActionResult: expectationReceipt?.actionResult,
                expectation: expectationReceipt?.expectation
            )),
            childFailureCategory: .invocation,
            failure: failure,
            children: children
        )
    }

    private func invocationExpectationFailure(
        expectation: WaitStep,
        receipt: HeistWaitReceipt
    ) -> HeistFailureDetail? {
        guard !receipt.actionResult.success || !receipt.expectation.met else { return nil }
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
            receipt.actionResult.errorKind.map { "errorKind=\($0.rawValue)" },
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
