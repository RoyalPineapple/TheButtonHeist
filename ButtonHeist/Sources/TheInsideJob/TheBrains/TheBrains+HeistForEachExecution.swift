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
        let kind: ForEachLoopKind
        let body: [HeistStep]
        let path: HeistExecutionPath
        let runtime: HeistExecutionRuntime
        let environment: HeistExecutionEnvironment
        let scope: HeistExecutionScope
    }

    private enum ForEachLoopKind {
        case element
        case string

        func iterationPath(from path: HeistExecutionPath, at index: Int) -> HeistExecutionPath {
            switch self {
            case .element: path.forEachElementIteration(at: index)
            case .string: path.forEachStringIteration(at: index)
            }
        }
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
        let childPath: HeistExecutionPath

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
        path: HeistExecutionPath,
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
                kind: .element,
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
            HeistExecutionPath,
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
            let iterationPath = context.kind.iterationPath(from: context.path, at: iterationIndex)
            let iterationResults = await executeHeistSteps(
                context.body,
                runtime: context.runtime,
                environment: bind(context.environment, item),
                scope: context.scope,
                path: iterationPath.iterationBody()
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
        path: HeistExecutionPath,
        start: CFAbsoluteTime,
        step: ForEachElementStep,
        matchedCount: Int,
        iterationIndex: Int,
        item: ForEachElementItem,
        children: [HeistExecutionStepResult]
    ) -> HeistExecutionStepResult {
        let durationMs = elapsedMilliseconds(since: start)
        let evidence = HeistForEachElementEvidence(
            matchedCount: matchedCount,
            iterationCount: iterationIndex + 1,
            iterationOrdinal: iterationIndex,
            targetOrdinal: item.ordinal,
            targetSummary: item.target.description,
            failureReason: children.firstFailedStep.map { "child failed at \($0.path)" }
        )
        let termination = children.firstFailedStep.map {
            ForEachLoopTermination.childFailed(.init(
                iterationIndex: iterationIndex,
                identity: .element(item.target),
                childPath: $0.path
            ))
        } ?? .completed
        let construction = evidence.flatMap { evidence in
            forEachCompletion(
                evidence: evidence,
                termination: termination,
                children: children,
                admitPassed: HeistPassedForEachElementEvidence.init,
                admitFailed: HeistFailedForEachElementEvidence.init,
                failure: forEachIterationFailure
            ).map { completion in
                HeistExecutionStepResult.construct(
                    path: path,
                    durationMs: durationMs,
                    node: .forEachElementIteration(
                        declaration: HeistForEachElementDeclaration(step),
                        completion: completion
                    )
                )
            }
        } ?? .failure(.evidenceConstructionFailed)
        return receiptResult(
            construction,
            path: path,
            durationMs: durationMs,
            children: children
        )
    }

    private func forEachElementResult(
        path: HeistExecutionPath,
        start: CFAbsoluteTime,
        step: ForEachElementStep,
        outcome: ForEachLoopOutcome
    ) -> HeistExecutionStepResult {
        let durationMs = elapsedMilliseconds(since: start)
        let evidence = HeistForEachElementEvidence(
            matchedCount: outcome.totalCount,
            iterationCount: outcome.iterationCount,
            failureReason: outcome.failureReason
        )
        let construction = evidence.flatMap { evidence in
            forEachCompletion(
                evidence: evidence,
                termination: outcome.termination,
                children: outcome.iterationNodes,
                admitPassed: HeistPassedForEachElementEvidence.init,
                admitFailed: HeistFailedForEachElementEvidence.init,
                failure: loopFailure(
                    contract: "for_each_element completes all matched iterations",
                    expected: "\(outcome.totalCount) iteration(s)"
                )
            ).map { completion in
                HeistExecutionStepResult.construct(
                    path: path,
                    durationMs: durationMs,
                    node: .forEachElement(
                        declaration: HeistForEachElementDeclaration(step),
                        completion: completion
                    )
                )
            }
        } ?? .failure(.evidenceConstructionFailed)
        return receiptResult(
            construction,
            path: path,
            durationMs: durationMs,
            children: outcome.iterationNodes
        )
    }

    func executeForEachStringStep(
        _ step: ForEachStringStep,
        index _: Int,
        path: HeistExecutionPath,
        start: CFAbsoluteTime,
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment,
        scope: HeistExecutionScope
    ) async -> HeistExecutionStepResult {
        let outcome = await runForEachLoop(
            context: ForEachLoopContext(
                totalCount: step.values.count,
                kind: .string,
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
        path: HeistExecutionPath,
        start: CFAbsoluteTime,
        step: ForEachStringStep,
        iterationIndex: Int,
        value: String,
        children: [HeistExecutionStepResult]
    ) -> HeistExecutionStepResult {
        let durationMs = elapsedMilliseconds(since: start)
        let evidence = HeistForEachStringEvidence(
            iterationCount: iterationIndex + 1,
            iterationOrdinal: iterationIndex,
            value: value,
            failureReason: children.firstFailedStep.map { "child failed at \($0.path)" }
        )
        let termination = children.firstFailedStep.map {
            ForEachLoopTermination.childFailed(.init(
                iterationIndex: iterationIndex,
                identity: .string(value),
                childPath: $0.path
            ))
        } ?? .completed
        let construction = evidence.flatMap { evidence in
            forEachCompletion(
                evidence: evidence,
                termination: termination,
                children: children,
                admitPassed: HeistPassedForEachStringEvidence.init,
                admitFailed: HeistFailedForEachStringEvidence.init,
                failure: forEachIterationFailure
            ).map { completion in
                HeistExecutionStepResult.construct(
                    path: path,
                    durationMs: durationMs,
                    node: .forEachStringIteration(
                        declaration: HeistForEachStringDeclaration(step),
                        completion: completion
                    )
                )
            }
        } ?? .failure(.evidenceConstructionFailed)
        return receiptResult(
            construction,
            path: path,
            durationMs: durationMs,
            children: children
        )
    }

    private func forEachStringResult(
        path: HeistExecutionPath,
        start: CFAbsoluteTime,
        step: ForEachStringStep,
        outcome: ForEachLoopOutcome
    ) -> HeistExecutionStepResult {
        let durationMs = elapsedMilliseconds(since: start)
        let evidence = HeistForEachStringEvidence(
            iterationCount: outcome.iterationCount,
            failureReason: outcome.failureReason
        )
        let construction = evidence.flatMap { evidence in
            forEachCompletion(
                evidence: evidence,
                termination: outcome.termination,
                children: outcome.iterationNodes,
                admitPassed: HeistPassedForEachStringEvidence.init,
                admitFailed: HeistFailedForEachStringEvidence.init,
                failure: loopFailure(
                    contract: "for_each_string completes all values",
                    expected: "\(outcome.totalCount) value(s)"
                )
            ).map { completion in
                HeistExecutionStepResult.construct(
                    path: path,
                    durationMs: durationMs,
                    node: .forEachString(
                        declaration: HeistForEachStringDeclaration(step),
                        completion: completion
                    )
                )
            }
        } ?? .failure(.evidenceConstructionFailed)
        return receiptResult(
            construction,
            path: path,
            durationMs: durationMs,
            children: outcome.iterationNodes
        )
    }

    private func forEachCompletion<Evidence, Passed, Failed>(
        evidence: Evidence,
        termination: ForEachLoopTermination,
        children: [HeistExecutionStepResult],
        admitPassed: (Evidence) -> Passed?,
        admitFailed: (Evidence) -> Failed?,
        failure: (_ observed: String, _ childPath: HeistExecutionPath?) -> HeistFailureDetail
    ) -> HeistExecutionCompletion<Passed, HeistEvidenceAvailability<Failed>, Failed>?
    where Passed: Sendable & Equatable, Failed: Codable & Sendable & Equatable {
        switch termination {
        case .completed:
            guard let evidence = admitPassed(evidence),
                  case .passed(let children) = HeistExecutedChildren(children) else { return nil }
            return .passed(evidence: evidence, children: children)
        case .childFailed(let childFailure):
            guard let evidence = admitFailed(evidence),
                  case .aborted(let children) = HeistExecutedChildren(children) else { return nil }
            return .childAborted(
                evidence: evidence,
                failure: failure(childFailure.reason, childFailure.childPath),
                children: children
            )
        case .postObservationUnavailable(let iterationIndex):
            let observed = "iteration \(iterationIndex) post-observation unavailable"
            guard let evidence = admitFailed(evidence),
                  case .passed(let children) = HeistExecutedChildren(children) else { return nil }
            return .failed(
                evidence: .observed(evidence),
                failure: failure(observed, nil),
                children: children
            )
        }
    }

    private func loopFailure(
        contract: String,
        expected: String
    ) -> (String, HeistExecutionPath?) -> HeistFailureDetail {
        { observed, _ in
            HeistFailureDetail(
                category: .loop,
                contract: contract,
                observed: observed,
                expected: expected
            )
        }
    }

    private func forEachIterationFailure(
        observed: String,
        childPath: HeistExecutionPath?
    ) -> HeistFailureDetail {
        childPath.map { childFailureDetail(category: .loop, childPath: $0) }
            ?? HeistFailureDetail(
                category: .runtimeUnavailable,
                contract: "for_each iteration remains observable",
                observed: observed
            )
    }

    private func forEachUnavailableResult(
        index _: Int,
        path: HeistExecutionPath,
        start: CFAbsoluteTime,
        parameter: HeistReferenceName,
        matching: ElementPredicateTemplate,
        limit: Int
    ) -> HeistExecutionStepResult {
        let observed = "could not observe settled semantic hierarchy before evaluating for_each_element"
        let durationMs = elapsedMilliseconds(since: start)
        let evidence = HeistForEachElementEvidence(
            matchedCount: 0,
            iterationCount: 0,
            failureReason: observed
        ).flatMap(HeistFailedForEachElementEvidence.init)
        let declaration = HeistForEachElementDeclaration(
            parameter: parameter,
            matching: matching,
            limit: limit
        )
        let construction = declaration.flatMap { declaration in
            evidence.flatMap { evidence in
                HeistExecutionStepResult.construct(
                    path: path,
                    durationMs: durationMs,
                    node: .forEachElement(
                        declaration: declaration,
                        completion: .failed(evidence: .observed(evidence), failure: HeistFailureDetail(
                            category: .runtimeUnavailable,
                            contract: "settled semantic hierarchy is observable before for_each_element matching",
                            observed: observed
                        ))
                    )
                )
            }
        } ?? .failure(.evidenceConstructionFailed)
        return receiptResult(
            construction,
            path: path,
            durationMs: durationMs
        )
    }

    private func forEachResolutionFailureResult(
        path: HeistExecutionPath,
        start: CFAbsoluteTime,
        step: ForEachElementStep,
        error: Error
    ) -> HeistExecutionStepResult {
        let observed = "could not resolve for_each_element matcher: \(error)"
        let durationMs = elapsedMilliseconds(since: start)
        let evidence = HeistForEachElementEvidence(
            matchedCount: 0,
            iterationCount: 0,
            failureReason: observed
        ).flatMap(HeistFailedForEachElementEvidence.init)
        let construction = evidence.map { evidence in
            HeistExecutionStepResult.construct(
                path: path,
                durationMs: durationMs,
                node: .forEachElement(
                    declaration: HeistForEachElementDeclaration(step),
                    completion: .failed(evidence: .observed(evidence), failure: HeistFailureDetail(
                        category: .targetResolution,
                        contract: "for_each_element matcher resolves before evaluation",
                        observed: observed,
                        expected: step.matching.description
                    ))
                )
            )
        } ?? .failure(.evidenceConstructionFailed)
        return receiptResult(
            construction,
            path: path,
            durationMs: durationMs
        )
    }

    private func forEachLimitResult(
        index _: Int,
        path: HeistExecutionPath,
        start: CFAbsoluteTime,
        parameter: HeistReferenceName,
        matching: ElementPredicateTemplate,
        matchedCount: Int,
        limit: Int
    ) -> HeistExecutionStepResult {
        let observed = "matched \(matchedCount) element(s), exceeding for_each_element limit \(limit)"
        let durationMs = elapsedMilliseconds(since: start)
        let evidence = HeistForEachElementEvidence(
            matchedCount: matchedCount,
            iterationCount: 0,
            failureReason: observed
        ).flatMap(HeistFailedForEachElementEvidence.init)
        let declaration = HeistForEachElementDeclaration(
            parameter: parameter,
            matching: matching,
            limit: limit
        )
        let construction = declaration.flatMap { declaration in
            evidence.flatMap { evidence in
                HeistExecutionStepResult.construct(
                    path: path,
                    durationMs: durationMs,
                    node: .forEachElement(
                        declaration: declaration,
                        completion: .failed(evidence: .observed(evidence), failure: HeistFailureDetail(
                            category: .loop,
                            contract: "for_each_element matched count does not exceed limit",
                            observed: observed,
                            expected: "at most \(limit) element(s)"
                        ))
                    )
                )
            }
        } ?? .failure(.evidenceConstructionFailed)
        return receiptResult(
            construction,
            path: path,
            durationMs: durationMs
        )
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
