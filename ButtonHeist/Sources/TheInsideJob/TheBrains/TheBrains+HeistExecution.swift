#if canImport(UIKit)
#if DEBUG
import Foundation

import ThePlans
import TheScore

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

    @MainActor
    protocol HeistExecutionRuntime {
        func execute(_ command: RuntimeActionMessage) async -> ActionResult
        func wait(
            _ waitStep: ResolvedWaitStep,
            _ initialTrace: AccessibilityTrace?,
            _ afterSequence: SettledObservationSequence?
        ) async -> HeistWaitReceipt
        func selectPredicateCase(_ cases: [ResolvedPredicateCase], _ timeout: Double) async -> HeistCaseSelectionResult
        func observeSemanticState(
            _ scope: SemanticObservationScope,
            _ sequence: SettledObservationSequence?,
            _ timeout: Double?
        ) async -> HeistSemanticObservation?
    }

    struct LiveHeistExecutionRuntime: HeistExecutionRuntime {
        let brains: TheBrains

        func execute(_ command: RuntimeActionMessage) async -> ActionResult {
            await brains.executeRuntimeAction(command)
        }

        func wait(
            _ waitStep: ResolvedWaitStep,
            _ initialTrace: AccessibilityTrace?,
            _ afterSequence: SettledObservationSequence?
        ) async -> HeistWaitReceipt {
            await brains.interactionObservation.waitForPredicate(
                waitStep,
                initialTrace: initialTrace,
                after: afterSequence
            )
        }

        func selectPredicateCase(_ cases: [ResolvedPredicateCase], _ timeout: Double) async -> HeistCaseSelectionResult {
            await brains.interactionObservation.waitForPredicateCases(cases, timeout: timeout)
        }

        func observeSemanticState(
            _ scope: SemanticObservationScope,
            _ sequence: SettledObservationSequence?,
            _ timeout: Double?
        ) async -> HeistSemanticObservation? {
            await brains.interactionObservation.observeSemanticState(scope: scope, after: sequence, timeout: timeout)
        }
    }

    struct ClosureHeistExecutionRuntime: HeistExecutionRuntime {
        let executeAction: @MainActor (RuntimeActionMessage) async -> ActionResult
        let waitForPredicate: @MainActor (ResolvedWaitStep, AccessibilityTrace?, SettledObservationSequence?) async -> HeistWaitReceipt
        let selectCase: @MainActor ([ResolvedPredicateCase], Double) async -> HeistCaseSelectionResult
        let observeState: @MainActor (SemanticObservationScope, SettledObservationSequence?, Double?) async -> HeistSemanticObservation?

        init(
            execute: @escaping @MainActor (RuntimeActionMessage) async -> ActionResult,
            wait: @escaping @MainActor (ResolvedWaitStep, AccessibilityTrace?, SettledObservationSequence?) async -> HeistWaitReceipt,
            selectPredicateCase: @escaping @MainActor ([ResolvedPredicateCase], Double) async -> HeistCaseSelectionResult,
            observeSemanticState: @escaping @MainActor (SemanticObservationScope, SettledObservationSequence?, Double?) async -> HeistSemanticObservation?
        ) {
            self.executeAction = execute
            self.waitForPredicate = wait
            self.selectCase = selectPredicateCase
            self.observeState = observeSemanticState
        }

        func execute(_ command: RuntimeActionMessage) async -> ActionResult {
            await executeAction(command)
        }

        func wait(
            _ waitStep: ResolvedWaitStep,
            _ initialTrace: AccessibilityTrace?,
            _ afterSequence: SettledObservationSequence?
        ) async -> HeistWaitReceipt {
            await waitForPredicate(waitStep, initialTrace, afterSequence)
        }

        func selectPredicateCase(_ cases: [ResolvedPredicateCase], _ timeout: Double) async -> HeistCaseSelectionResult {
            await selectCase(cases, timeout)
        }

        func observeSemanticState(
            _ scope: SemanticObservationScope,
            _ sequence: SettledObservationSequence?,
            _ timeout: Double?
        ) async -> HeistSemanticObservation? {
            await observeState(scope, sequence, timeout)
        }
    }

    private enum HeistStepFlow {
        case running
        case skippingAfterFailure

        var shouldExecuteNextStep: Bool {
            switch self {
            case .running:
                return true
            case .skippingAfterFailure:
                return false
            }
        }

        mutating func record(_ result: HeistExecutionStepResult) {
            if result.isFailure {
                self = .skippingAfterFailure
            }
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

    func executeHeistPlan(_ plan: HeistPlan, argument: HeistArgument = .none) async -> ActionResult {
        guard semanticObservationIsActive else {
            return runtimeInactiveResult(method: .heistPlan)
        }
        return await executeHeistPlan(plan, argument: argument, runtime: LiveHeistExecutionRuntime(brains: self))
    }

    func executeHeistPlanForTest(
        _ plan: HeistPlan,
        argument: HeistArgument = .none,
        runtime: any HeistExecutionRuntime
    ) async -> ActionResult {
        await executeHeistPlan(plan, argument: argument, runtime: runtime)
    }

    private func executeHeistPlan(
        _ plan: HeistPlan,
        argument: HeistArgument,
        runtime: any HeistExecutionRuntime
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
        runtime: any HeistExecutionRuntime,
        failedPath: String
    ) async -> HeistExecutionStepResult? {
        let start = CFAbsoluteTimeGetCurrent()
        let result = await runtime.execute(.takeScreenshot)
        guard result.method == .takeScreenshot else { return nil }
        let command = HeistActionCommand.takeScreenshot
        return HeistExecutionStepResult(
            path: "\(failedPath).failure.actions[0]",
            kind: .action,
            status: result.success ? .passed : .failed,
            durationMs: elapsedMilliseconds(since: start),
            intent: .action(command: command.wireType.rawValue, target: nil),
            evidence: .action(HeistActionEvidence(command: command, actionResult: result)),
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
        runtime: any HeistExecutionRuntime,
        environment: HeistExecutionEnvironment,
        scope: HeistExecutionScope,
        path: String = "$.body"
    ) async -> [HeistExecutionStepResult] {
        var stepResults: [HeistExecutionStepResult] = []
        var flow = HeistStepFlow.running

        for (index, step) in steps.enumerated() {
            let stepPath = "\(path)[\(index)]"
            guard flow.shouldExecuteNextStep else {
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
            flow.record(stepResult)
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
        runtime: any HeistExecutionRuntime,
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
        runtime: any HeistExecutionRuntime,
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
        runtime: any HeistExecutionRuntime,
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
        return HeistExecutionStepResult(
            path: context.path,
            kind: .invoke,
            status: .failed,
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
        return HeistExecutionStepResult(
            path: context.path,
            kind: .invoke,
            status: .failed,
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
        return HeistExecutionStepResult(
            path: context.path,
            kind: .invoke,
            status: .failed,
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
        runtime: any HeistExecutionRuntime
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
            ResolvedWaitStep(predicate: resolved.predicate, timeout: immediateTimeout),
            nil,
            nil
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
        let expectationActionResult = ActionResult(
            success: false,
            method: .wait,
            message: observed,
            errorKind: .actionFailed
        )
        let expectationResult = ExpectationResult(
            met: false,
            predicate: nil,
            actual: observed
        )
        return HeistExecutionStepResult(
            path: context.path,
            kind: .invoke,
            status: .failed,
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
        runtime: any HeistExecutionRuntime,
        childFailed: Bool
    ) async -> HeistWaitReceipt? {
        guard !childFailed, let context else { return nil }
        return await runtime.wait(
            context.resolved,
            context.baseline.actionResult.accessibilityTrace,
            context.baseline.observedSequence
        )
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
        HeistExecutionStepResult(
            path: context.path,
            kind: .invoke,
            status: failure == nil ? .passed : .failed,
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
            failure: failure,
            abortedAtChildPath: abortedAtChildPath,
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
