#if canImport(UIKit)
#if DEBUG
import Foundation

import ThePlans
import TheScore

extension TheBrains {

    internal struct InvocationResolution {
        internal let requestedName: HeistInvocationPath
        internal let resolvedPath: HeistInvocationPath
        internal let resolvedName: HeistInvocationPath
        internal let definition: HeistPlan?
    }

    internal struct InvocationExecutionContext {
        internal let invoke: HeistInvocationStep
        internal let path: HeistExecutionPath
        internal let start: RuntimeElapsed.Instant
        internal let requestedName: HeistInvocationPath

        internal init(
            invoke: HeistInvocationStep,
            path: HeistExecutionPath,
            start: RuntimeElapsed.Instant,
            requestedName: HeistInvocationPath
        ) {
            self.invoke = invoke
            self.path = path
            self.start = start
            self.requestedName = requestedName
        }

        internal var argumentSummary: String? {
            invoke.argument == .none ? nil : invoke.runHeistSummary
        }
    }

    internal struct InvocationExpectationContext {
        internal let input: ResolvedWaitRuntimeInput
        internal let currentState: Settlement.Result
    }

    private enum InvocationExpectationPreparation {
        case none
        case prepared(InvocationExpectationContext)
        case failed(HeistExecutionStepResult)
    }

    internal enum InvocationExpectationOutcome {
        case notEvaluated
        case matched(HeistSettlementEvidence)
        case failed(evidence: HeistSettlementEvidence, detail: HeistFailureDetail)

        internal var evidence: HeistSettlementEvidence? {
            switch self {
            case .notEvaluated:
                return nil
            case .matched(let evidence):
                return evidence
            case .failed(evidence: let evidence, detail: _):
                return evidence
            }
        }
    }

    internal func executeInvocationStep(
        _ invoke: HeistInvocationStep,
        index _: Int,
        path: HeistExecutionPath,
        start: RuntimeElapsed.Instant,
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment,
        scope: HeistExecutionScope
    ) async -> HeistExecutionStepResult {
        let resolution = resolveInvocation(invoke, scope: scope)
        let context = InvocationExecutionContext(
            invoke: invoke,
            path: path,
            start: start,
            requestedName: resolution.requestedName
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
                definitionPath: resolution.resolvedPath.components,
                invocationStack: scope.invocationStack.union([resolution.resolvedName])
            ),
            path: path.invocationBody()
        )
        let expectationOutcome = await evaluateInvocationExpectation(
            expectationContext,
            runtime: runtime,
            childExecution: children
        )
        return completedInvocationResult(
            context: context,
            childExecution: children,
            expectationOutcome: expectationOutcome
        )
    }

    private func resolveInvocation(
        _ invoke: HeistInvocationStep,
        scope: HeistExecutionScope
    ) -> InvocationResolution {
        let requestedName = invoke.path
        guard let firstComponent = invoke.path.components.first else {
            preconditionFailure("validated heist invocation path must not be empty")
        }
        let definitionPath = HeistDefinitionPath(
            first: firstComponent,
            remaining: Array(invoke.path.components.dropFirst())
        )
        let localDefinition = scope.plan.heistDefinition(at: definitionPath)
        let rootDefinition = invoke.path.components.count > 1
            ? scope.rootPlan.heistDefinition(at: definitionPath)
            : nil
        let resolvedComponents = localDefinition == nil && rootDefinition != nil
            ? invoke.path.components
            : scope.definitionPath + invoke.path.components
        guard let first = resolvedComponents.first else {
            preconditionFailure("validated heist invocation path must not be empty")
        }
        let resolvedPath = HeistInvocationPath(first: first, remaining: Array(resolvedComponents.dropFirst()))
        return InvocationResolution(
            requestedName: requestedName,
            resolvedPath: resolvedPath,
            resolvedName: resolvedPath,
            definition: localDefinition ?? rootDefinition
        )
    }

    private func prepareInvocationExpectation(
        context: InvocationExecutionContext,
        environment: HeistExecutionEnvironment,
        runtime: HeistExecutionRuntime
    ) async -> InvocationExpectationPreparation {
        guard let expectation = context.invoke.expectation else { return .none }
        let input: ResolvedWaitRuntimeInput
        do {
            input = try ResolvedWaitRuntimeInput(resolving: expectation, in: environment)
        } catch {
            return .failed(invocationExpectationResolutionFailureResult(
                context: context,
                expectation: expectation,
                error: error
            ))
        }
        let currentState = await runtime.settle(
            .currentState(scope: input.predicate.observationScope)
        )
        return .prepared(InvocationExpectationContext(
            input: input,
            currentState: currentState
        ))
    }

    private func evaluateInvocationExpectation(
        _ context: InvocationExpectationContext?,
        runtime: HeistExecutionRuntime,
        childExecution: HeistExecutedChildren
    ) async -> InvocationExpectationOutcome {
        guard case .passed = childExecution, let context else { return .notEvaluated }
        let baseline: Settlement.Baseline
        if let moment = context.currentState.evidence.handoff.event?.moment {
            baseline = .supplied(.init(moment: moment))
        } else if case .presence = context.input.predicate.core {
            baseline = .capture
        } else {
            baseline = .unavailable(.unavailable)
        }
        let settlement = await runtime.settle(Settlement.Command(
            observing: context.input,
            baseline: baseline
        ))
        let evidence = Settlement.ResultProjector.projectWait(settlement)
        guard let failure = invocationExpectationFailure(
            predicateExpression: context.input.predicateExpression,
            evidence: evidence
        ) else {
            return .matched(evidence)
        }
        return .failed(evidence: evidence, detail: failure)
    }

    private func invocationExpectationFailure(
        predicateExpression: AccessibilityPredicate,
        evidence: HeistSettlementEvidence
    ) -> HeistFailureDetail? {
        guard !evidence.actionResult.outcome.isSuccess || !evidence.expectation.met else { return nil }
        return HeistFailureDetail(
            category: .expectation,
            contract: "heist invocation expectation is met",
            observed: invocationExpectationObserved(evidence),
            expected: predicateExpression.description
        )
    }

    private func invocationExpectationObserved(_ evidence: HeistSettlementEvidence) -> String {
        [
            evidence.expectation.actual,
            evidence.actionResult.message,
            evidence.actionResult.outcome.failureKind.map { "failureKind=\($0.rawValue)" },
            evidence.actionResult.settled.map { "settled=\($0)" },
        ].compactMap { $0 }.joined(separator: "; ")
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
