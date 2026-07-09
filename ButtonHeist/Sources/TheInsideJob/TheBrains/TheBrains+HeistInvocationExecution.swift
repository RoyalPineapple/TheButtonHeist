#if canImport(UIKit)
#if DEBUG
import Foundation

import ThePlans
import TheScore

extension TheBrains {

    internal struct InvocationResolution {
        internal let requestedName: String
        internal let resolvedPath: [String]
        internal let resolvedName: String
        internal let definition: HeistPlan?

        internal init(
            requestedName: String,
            resolvedPath: [String],
            resolvedName: String,
            definition: HeistPlan?
        ) {
            self.requestedName = requestedName
            self.resolvedPath = resolvedPath
            self.resolvedName = resolvedName
            self.definition = definition
        }
    }

    internal struct InvocationExecutionContext {
        internal let invoke: HeistInvocationStep
        internal let path: String
        internal let start: CFAbsoluteTime
        internal let requestedName: String
        internal let intent: HeistStepIntent

        internal init(
            invoke: HeistInvocationStep,
            path: String,
            start: CFAbsoluteTime,
            requestedName: String,
            intent: HeistStepIntent
        ) {
            self.invoke = invoke
            self.path = path
            self.start = start
            self.requestedName = requestedName
            self.intent = intent
        }

        internal var argumentSummary: String? {
            invoke.argument == .none ? nil : invoke.runHeistSummary
        }
    }

    internal struct InvocationExpectationContext {
        internal let source: WaitStep
        internal let resolved: ResolvedWaitStep
        internal let baseline: HeistWaitReceipt

        internal init(
            source: WaitStep,
            resolved: ResolvedWaitStep,
            baseline: HeistWaitReceipt
        ) {
            self.source = source
            self.resolved = resolved
            self.baseline = baseline
        }
    }

    private enum InvocationExpectationPreparation {
        case none
        case prepared(InvocationExpectationContext)
        case failed(HeistExecutionStepResult)
    }

    internal enum InvocationExpectationOutcome {
        case notEvaluated
        case matched(HeistWaitReceipt)
        case failed(receipt: HeistWaitReceipt, detail: HeistFailureDetail)

        internal var receipt: HeistWaitReceipt? {
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

    internal func executeInvocationStep(
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

    private func invocationExpectationFailure(
        expectation: WaitStep,
        receipt: HeistWaitReceipt
    ) -> HeistFailureDetail? {
        guard !receipt.actionResult.outcome.isSuccess || !receipt.expectation.met else { return nil }
        return HeistFailureDetail(
            category: .expectation,
            contract: "heist invocation expectation is met",
            observed: invocationExpectationObserved(receipt),
            expected: expectation.predicate.description
        )
    }

    private func invocationExpectationObserved(_ receipt: HeistWaitReceipt) -> String {
        [
            receipt.expectation.actual,
            receipt.actionResult.message,
            receipt.actionResult.outcome.errorKind.map { "errorKind=\($0.rawValue)" },
            receipt.actionResult.settled.map { "settled=\($0)" },
        ].compactMap { $0 }.joined(separator: "; ")
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
