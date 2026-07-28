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
    }

    internal struct InvocationExpectationContext {
        internal let predicate: HeistExecution.Predicate
        internal let timeout: WaitTimeout
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
        host: HeistExecution.Host,
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
        switch await prepareInvocationExpectation(context: context, environment: environment, host: host) {
        case .none:
            expectationContext = nil
        case .prepared(let prepared):
            expectationContext = prepared
        case .failed(let result):
            return result
        }

        let children = await executeHeistSteps(
            definition.body,
            host: host,
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
            host: host,
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
        host: HeistExecution.Host
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
        let predicate = HeistExecution.Predicate(
            authored: expectation.predicate,
            resolved: resolved.predicate
        )
        return .prepared(InvocationExpectationContext(
            predicate: predicate,
            timeout: resolved.timeout
        ))
    }

    private func evaluateInvocationExpectation(
        _ context: InvocationExpectationContext?,
        host: HeistExecution.Host,
        childExecution: HeistExecutedChildren
    ) async -> InvocationExpectationOutcome {
        guard case .passed = childExecution, let context else { return .notEvaluated }
        let settlement = await host.execute(HeistExecution.Command(
            observing: context.predicate.authored,
            resolved: context.predicate.resolved,
            timeout: context.timeout
        ))
        let evidence = HeistExecution.ResultProjector.projectWait(settlement)
        guard let failure = invocationExpectationFailure(
            predicateExpression: context.predicate.authored,
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
