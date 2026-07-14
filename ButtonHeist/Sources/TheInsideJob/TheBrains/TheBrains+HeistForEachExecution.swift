#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans

import TheScore

extension TheBrains {
    private struct ForEachLoopOutcome {
        let totalCount: Int
        let termination: ForEachLoopTermination
        let iterationNodes: [HeistExecutionStepResult]

        var iterationCount: Int {
            iterationNodes.count
        }

        var failureReason: String? {
            termination.failureReason
        }
    }

    private enum ForEachLoopTermination {
        case completed
        case childFailed(ForEachLoopChildFailure)
        case postObservationUnavailable(iterationIndex: Int)

        var failureReason: String? {
            switch self {
            case .completed:
                return nil
            case .childFailed(let failure):
                return failure.reason
            case .postObservationUnavailable(let iterationIndex):
                return "iteration \(iterationIndex) post-observation unavailable"
            }
        }

    }

    private struct ForEachLoopContext {
        let totalCount: Int
        let iterationPathComponent: String
        let body: [HeistStep]
        let path: String
        let runtime: HeistExecutionRuntime
        let environment: HeistExecutionEnvironment
        let scope: HeistExecutionScope
    }

    private enum ForEachLoopNext<Item> {
        case item(Item)
        case terminated(ForEachLoopTermination)
    }

    private enum ForEachLoopItemIdentity {
        case element(ResolvedAccessibilityTarget)
        case string(String)
    }

    private struct ForEachElementItem {
        let target: ResolvedAccessibilityTarget
        let ordinal: Int
    }

    private struct ForEachLoopChildFailure {
        let iterationIndex: Int
        let identity: ForEachLoopItemIdentity
        let childPath: String

        var reason: String {
            switch identity {
            case .element:
                return "iteration \(iterationIndex) failed at \(childPath)"
            case .string(let value):
                return "iteration \(iterationIndex) failed for value \"\(value)\" at \(childPath)"
            }
        }
    }

    func executeForEachElementStep(
        _ step: ForEachElementStep,
        index: Int,
        path: String,
        start: CFAbsoluteTime,
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment,
        scope: HeistExecutionScope
    ) async -> HeistExecutionStepResult {
        let resolvedMatching: ElementPredicate
        do {
            resolvedMatching = try step.matching.resolve(in: environment)
        } catch {
            return forEachResolutionFailureResult(
                path: path,
                start: start,
                step: step,
                error: error
            )
        }
        guard let observation = await runtime.observeSemanticState(.discovery, nil, nil) else {
            return forEachUnavailableResult(
                index: index,
                path: path,
                start: start,
                parameter: step.parameter,
                matching: step.matching,
                limit: step.limit
            )
        }

        let matchSignature = ForEachMatchSignature(
            matching: resolvedMatching,
            elements: observation.state.interface.projectedElements
        )
        let matchedCount = matchSignature.count
        if matchedCount > step.limit {
            return forEachLimitResult(
                index: index,
                path: path,
                start: start,
                parameter: step.parameter,
                matching: step.matching,
                matchedCount: matchedCount,
                limit: step.limit
            )
        }

        var currentSignature = matchSignature
        var nextOrdinal = 0
        var observedSequence = observation.event.sequence
        let outcome = await runForEachLoop(
            context: ForEachLoopContext(
                totalCount: matchedCount,
                iterationPathComponent: "for_each_element",
                body: step.body,
                path: path,
                runtime: runtime,
                environment: environment,
                scope: scope
            ),
            nextItem: { iterationIndex in
                if iterationIndex > 0 {
                    guard let afterObservation = await runtime.observeSemanticState(
                        .discovery,
                        observedSequence,
                        nil
                    ) else {
                        return .terminated(.postObservationUnavailable(iterationIndex: iterationIndex - 1))
                    }
                    observedSequence = afterObservation.event.sequence
                    let nextSignature = ForEachMatchSignature(
                        matching: resolvedMatching,
                        elements: afterObservation.state.interface.projectedElements
                    )
                    if nextSignature == currentSignature {
                        nextOrdinal += 1
                    } else {
                        currentSignature = nextSignature
                        nextOrdinal = 0
                    }
                }
                return .item(ForEachElementItem(
                    target: .predicate(resolvedMatching, ordinal: nextOrdinal),
                    ordinal: nextOrdinal
                ))
            },
            bind: { environment, item in
                environment.binding(target: item.target, to: step.parameter)
            },
            identity: { .element($0.target) },
            iterationReceipt: { item, iterationIndex, iterationPath, iterationStart, children in
                self.forEachElementIterationResult(
                    path: iterationPath,
                    start: iterationStart,
                    step: step,
                    matchedCount: matchedCount,
                    iterationIndex: iterationIndex,
                    item: item,
                    children: children
                )
            }
        )

        return forEachElementResult(
            path: path,
            start: start,
            step: step,
            outcome: outcome
        )
    }

    private func runForEachLoop<Item>(
        context: ForEachLoopContext,
        nextItem: (Int) async -> ForEachLoopNext<Item>,
        bind: (HeistExecutionEnvironment, Item) -> HeistExecutionEnvironment,
        identity: (Item) -> ForEachLoopItemIdentity,
        iterationReceipt: (
            Item,
            Int,
            String,
            CFAbsoluteTime,
            [HeistExecutionStepResult]
        ) -> HeistExecutionStepResult
    ) async -> ForEachLoopOutcome {
        var iterationNodes: [HeistExecutionStepResult] = []

        while iterationNodes.count < context.totalCount {
            let iterationIndex = iterationNodes.count
            let item: Item
            switch await nextItem(iterationIndex) {
            case .item(let nextItem):
                item = nextItem
            case .terminated(let termination):
                return ForEachLoopOutcome(
                    totalCount: context.totalCount,
                    termination: termination,
                    iterationNodes: iterationNodes
                )
            }
            let iterationStart = CFAbsoluteTimeGetCurrent()
            let iterationPath = "\(context.path).\(context.iterationPathComponent).iterations[\(iterationIndex)]"
            let iterationResults = await executeHeistSteps(
                context.body,
                runtime: context.runtime,
                environment: bind(context.environment, item),
                scope: context.scope,
                path: "\(iterationPath).body"
            )

            iterationNodes.append(iterationReceipt(
                item,
                iterationIndex,
                iterationPath,
                iterationStart,
                iterationResults
            ))

            if let abortedAtChildPath = iterationResults.firstFailedStep?.path {
                return ForEachLoopOutcome(
                    totalCount: context.totalCount,
                    termination: .childFailed(ForEachLoopChildFailure(
                        iterationIndex: iterationIndex,
                        identity: identity(item),
                        childPath: abortedAtChildPath
                    )),
                    iterationNodes: iterationNodes
                )
            }
        }

        return ForEachLoopOutcome(
            totalCount: context.totalCount,
            termination: .completed,
            iterationNodes: iterationNodes
        )
    }

    private func forEachElementIterationResult(
        path: String,
        start: CFAbsoluteTime,
        step: ForEachElementStep,
        matchedCount: Int,
        iterationIndex: Int,
        item: ForEachElementItem,
        children: [HeistExecutionStepResult]
    ) -> HeistExecutionStepResult {
        let evidence = HeistStepEvidence.forEachElement(HeistForEachElementEvidence(
            parameter: step.parameter,
            matching: step.matching,
            limit: step.limit,
            matchedCount: matchedCount,
            iterationCount: iterationIndex + 1,
            iterationOrdinal: iterationIndex,
            targetOrdinal: item.ordinal,
            targetSummary: item.target.description,
            failureReason: children.firstFailedStep.map { "child failed at \($0.path)" }
        ))
        return heistReceipt(.init(
            path: path,
            kind: .forEachIteration,
            durationMs: elapsedMilliseconds(since: start),
            intent: .forEachElement(parameter: step.parameter, matching: step.matching, limit: step.limit),
            evidence: evidence,
            children: children,
            childFailure: { childPath in
                self.childFailureDetail(category: .loop, childPath: childPath)
            }
        ))
    }

    private func forEachElementResult(
        path: String,
        start: CFAbsoluteTime,
        step: ForEachElementStep,
        outcome: ForEachLoopOutcome
    ) -> HeistExecutionStepResult {
        let evidence = HeistStepEvidence.forEachElement(HeistForEachElementEvidence(
            parameter: step.parameter,
            matching: step.matching,
            limit: step.limit,
            matchedCount: outcome.totalCount,
            iterationCount: outcome.iterationCount,
            failureReason: outcome.failureReason
        ))
        return forEachReceipt(
            path: path,
            kind: .forEachElement,
            durationMs: elapsedMilliseconds(since: start),
            intent: .forEachElement(parameter: step.parameter, matching: step.matching, limit: step.limit),
            evidence: evidence,
            outcome: outcome,
            contract: "for_each_element completes all matched iterations",
            expected: "\(outcome.totalCount) iteration(s)"
        )
    }

    func executeForEachStringStep(
        _ step: ForEachStringStep,
        index _: Int,
        path: String,
        start: CFAbsoluteTime,
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment,
        scope: HeistExecutionScope
    ) async -> HeistExecutionStepResult {
        let outcome = await runForEachLoop(
            context: ForEachLoopContext(
                totalCount: step.values.count,
                iterationPathComponent: "for_each_string",
                body: step.body,
                path: path,
                runtime: runtime,
                environment: environment,
                scope: scope
            ),
            nextItem: { .item(step.values[$0]) },
            bind: { environment, value in
                environment.binding(string: value, to: step.parameter)
            },
            identity: { .string($0) },
            iterationReceipt: { value, iterationIndex, iterationPath, iterationStart, children in
                self.forEachStringIterationResult(
                    path: iterationPath,
                    start: iterationStart,
                    step: step,
                    iterationIndex: iterationIndex,
                    value: value,
                    children: children
                )
            }
        )
        return forEachStringResult(
            path: path,
            start: start,
            step: step,
            outcome: outcome
        )
    }

    private func forEachStringIterationResult(
        path: String,
        start: CFAbsoluteTime,
        step: ForEachStringStep,
        iterationIndex: Int,
        value: String,
        children: [HeistExecutionStepResult]
    ) -> HeistExecutionStepResult {
        let evidence = HeistStepEvidence.forEachString(HeistForEachStringEvidence(
            parameter: step.parameter,
            count: step.values.count,
            iterationCount: iterationIndex + 1,
            iterationOrdinal: iterationIndex,
            value: value,
            failureReason: children.firstFailedStep.map { "child failed at \($0.path)" }
        ))
        return heistReceipt(.init(
            path: path,
            kind: .forEachIteration,
            durationMs: elapsedMilliseconds(since: start),
            intent: .forEachString(parameter: step.parameter, count: step.values.count),
            evidence: evidence,
            children: children,
            childFailure: { childPath in
                self.childFailureDetail(category: .loop, childPath: childPath)
            }
        ))
    }

    private func forEachStringResult(
        path: String,
        start: CFAbsoluteTime,
        step: ForEachStringStep,
        outcome: ForEachLoopOutcome
    ) -> HeistExecutionStepResult {
        let evidence = HeistStepEvidence.forEachString(HeistForEachStringEvidence(
            parameter: step.parameter,
            count: outcome.totalCount,
            iterationCount: outcome.iterationCount,
            failureReason: outcome.failureReason
        ))
        return forEachReceipt(
            path: path,
            kind: .forEachString,
            durationMs: elapsedMilliseconds(since: start),
            intent: .forEachString(parameter: step.parameter, count: outcome.totalCount),
            evidence: evidence,
            outcome: outcome,
            contract: "for_each_string completes all values",
            expected: "\(outcome.totalCount) value(s)"
        )
    }

    private func forEachReceipt(
        path: String,
        kind: HeistExecutionStepKind,
        durationMs: Int,
        intent: HeistStepIntent,
        evidence: HeistStepEvidence,
        outcome: ForEachLoopOutcome,
        contract: String,
        expected: String
    ) -> HeistExecutionStepResult {
        func failure(observed: String) -> HeistFailureDetail {
            HeistFailureDetail(
                category: .loop,
                contract: contract,
                observed: observed,
                expected: expected
            )
        }
        let receiptFailure: HeistFailureDetail?
        let childFailure: (String) -> HeistFailureDetail
        switch outcome.termination {
        case .completed:
            receiptFailure = nil
            childFailure = { childPath in
                failure(observed: "child failed at \(childPath)")
            }
        case .childFailed(let childFailureInfo):
            receiptFailure = failure(observed: childFailureInfo.reason)
            childFailure = { _ in
                failure(observed: childFailureInfo.reason)
            }
        case .postObservationUnavailable(let iterationIndex):
            let observed = "iteration \(iterationIndex) post-observation unavailable"
            receiptFailure = failure(observed: observed)
            childFailure = { _ in
                failure(observed: observed)
            }
        }
        return heistReceipt(.init(
            path: path,
            kind: kind,
            durationMs: durationMs,
            intent: intent,
            evidence: evidence,
            completion: receiptFailure.map(HeistReceiptRequest.Completion.failed) ?? .passed,
            children: outcome.iterationNodes,
            childFailure: childFailure
        ))
    }

    private func forEachUnavailableResult(
        index _: Int,
        path: String,
        start: CFAbsoluteTime,
        parameter: HeistReferenceName,
        matching: ElementPredicateTemplate,
        limit: Int
    ) -> HeistExecutionStepResult {
        let observed = "could not observe settled semantic hierarchy before evaluating for_each_element"
        return heistReceipt(.init(
            path: path,
            kind: .forEachElement,
            durationMs: elapsedMilliseconds(since: start),
            intent: .forEachElement(parameter: parameter, matching: matching, limit: limit),
            evidence: .forEachElement(HeistForEachElementEvidence(
                parameter: parameter,
                matching: matching,
                limit: limit,
                matchedCount: 0,
                iterationCount: 0,
                failureReason: observed
            )),
            completion: .failed(HeistFailureDetail(
                category: .runtimeUnavailable,
                contract: "settled semantic hierarchy is observable before for_each_element matching",
                observed: observed
            ))
        ))
    }

    private func forEachResolutionFailureResult(
        path: String,
        start: CFAbsoluteTime,
        step: ForEachElementStep,
        error: Error
    ) -> HeistExecutionStepResult {
        let observed = "could not resolve for_each_element matcher: \(error)"
        return heistReceipt(.init(
            path: path,
            kind: .forEachElement,
            durationMs: elapsedMilliseconds(since: start),
            intent: .forEachElement(parameter: step.parameter, matching: step.matching, limit: step.limit),
            evidence: .forEachElement(HeistForEachElementEvidence(
                parameter: step.parameter,
                matching: step.matching,
                limit: step.limit,
                matchedCount: 0,
                iterationCount: 0,
                failureReason: observed
            )),
            completion: .failed(HeistFailureDetail(
                category: .targetResolution,
                contract: "for_each_element matcher resolves before evaluation",
                observed: observed,
                expected: step.matching.description
            ))
        ))
    }

    private func forEachLimitResult(
        index _: Int,
        path: String,
        start: CFAbsoluteTime,
        parameter: HeistReferenceName,
        matching: ElementPredicateTemplate,
        matchedCount: Int,
        limit: Int
    ) -> HeistExecutionStepResult {
        let observed = "matched \(matchedCount) element(s), exceeding for_each_element limit \(limit)"
        return heistReceipt(.init(
            path: path,
            kind: .forEachElement,
            durationMs: elapsedMilliseconds(since: start),
            intent: .forEachElement(parameter: parameter, matching: matching, limit: limit),
            evidence: .forEachElement(HeistForEachElementEvidence(
                parameter: parameter,
                matching: matching,
                limit: limit,
                matchedCount: matchedCount,
                iterationCount: 0,
                failureReason: observed
            )),
            completion: .failed(HeistFailureDetail(
                category: .loop,
                contract: "for_each_element matched count does not exceed limit",
                observed: observed,
                expected: "at most \(limit) element(s)"
            ))
        ))
    }
}

private struct ForEachMatchSignature: Equatable {
    let identities: [[AccessibilityMatcherFact]]

    var count: Int { identities.count }

    init(matching: ElementPredicate, elements: [HeistElement]) {
        identities = ElementMatchGraph(elements: elements)
            .resolve(matching)
            .elements
            .map(AccessibilityPolicy.matcherIdentityFacts(for:))
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
