#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans

import TheScore

extension TheBrains {
    private enum ForEachLoopOutcome {
        case completed(totalCount: Int, iterations: HeistPassingChildren)
        case childFailed(totalCount: Int, failure: ForEachLoopChildFailure, iterations: HeistAbortedChildren)
        case postObservationUnavailable(
            totalCount: Int,
            iterationIndex: Int,
            iterations: HeistPassingChildren
        )

        var totalCount: Int {
            switch self {
            case .completed(let totalCount, _),
                 .childFailed(let totalCount, _, _),
                 .postObservationUnavailable(let totalCount, _, _):
                totalCount
            }
        }

        var iterationCount: Int {
            switch self {
            case .completed(_, let iterations), .postObservationUnavailable(_, _, let iterations):
                iterations.values.count
            case .childFailed(_, _, let iterations):
                iterations.values.count
            }
        }

        var failureReason: String? {
            switch self {
            case .completed:
                nil
            case .childFailed(_, let failure, _):
                failure.reason
            case .postObservationUnavailable(_, let iterationIndex, _):
                "iteration \(iterationIndex) post-observation unavailable"
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
        case postObservationUnavailable(iterationIndex: Int)
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
        start: RuntimeElapsed.Instant,
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
        guard let event = await runtime.settledEvent(.discovery, nil, nil) else {
            return forEachUnavailableResult(
                index: index,
                path: path,
                start: start,
                step: step
            )
        }

        let matchSignature = ForEachMatchSignature(
            matching: resolvedMatching,
            elements: event.moment.capture.interface.projectedElements
        )
        let matchedCount = matchSignature.count
        if matchedCount > step.limit {
            return forEachLimitResult(
                index: index,
                path: path,
                start: start,
                matchedCount: matchedCount,
                step: step
            )
        }

        var currentSignature = matchSignature
        var nextOrdinal = 0
        var observedSequence = event.sequence
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
                    guard let nextEvent = await runtime.settledEvent(
                        .discovery,
                        observedSequence,
                        nil
                    ) else {
                        return .postObservationUnavailable(iterationIndex: iterationIndex - 1)
                    }
                    observedSequence = nextEvent.sequence
                    let nextSignature = ForEachMatchSignature(
                        matching: resolvedMatching,
                        elements: nextEvent.moment.capture.interface.projectedElements
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
            iterationResult: { item, iterationIndex, iterationPath, iterationStart, children in
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
        iterationResult: (
            Item,
            Int,
            HeistExecutionPath,
            RuntimeElapsed.Instant,
            HeistExecutedChildren
        ) -> HeistExecutionStepResult
    ) async -> ForEachLoopOutcome {
        var iterationNodes = HeistPassingChildren.empty

        while iterationNodes.values.count < context.totalCount {
            let iterationIndex = iterationNodes.values.count
            let item: Item
            switch await nextItem(iterationIndex) {
            case .item(let nextItem):
                item = nextItem
            case .postObservationUnavailable(let failedIterationIndex):
                return .postObservationUnavailable(
                    totalCount: context.totalCount,
                    iterationIndex: failedIterationIndex,
                    iterations: iterationNodes
                )
            }
            let iterationStart = RuntimeElapsed.now
            let iterationPath = context.kind.iterationPath(from: context.path, at: iterationIndex)
            let iterationResults = await executeHeistSteps(
                context.body,
                runtime: context.runtime,
                environment: bind(context.environment, item),
                scope: context.scope,
                path: iterationPath.iterationBody()
            )

            let iterationNode = iterationResult(
                item,
                iterationIndex,
                iterationPath,
                iterationStart,
                iterationResults
            )
            switch iterationNodes.appending(iterationNode) {
            case .passed(let passingIterations):
                iterationNodes = passingIterations
            case .aborted(let abortedIterations):
                return .childFailed(
                    totalCount: context.totalCount,
                    failure: ForEachLoopChildFailure(
                        iterationIndex: iterationIndex,
                        identity: identity(item),
                        childPath: abortedIterations.abortedAtPath
                    ),
                    iterations: abortedIterations
                )
            }
        }

        return .completed(totalCount: context.totalCount, iterations: iterationNodes)
    }

    private func forEachElementIterationResult(
        path: HeistExecutionPath,
        start: RuntimeElapsed.Instant,
        step: ForEachElementStep,
        matchedCount: Int,
        iterationIndex: Int,
        item: ForEachElementItem,
        children: HeistExecutedChildren
    ) -> HeistExecutionStepResult {
        let durationMs = elapsedMilliseconds(since: start)
        let failureReason = children.abortedAtPath.map { "child failed at \($0)" }
        let evidence = HeistForEachElementEvidence.executedIteration(
            matchedCount: matchedCount,
            iterationCount: iterationIndex + 1,
            iterationOrdinal: iterationIndex,
            targetOrdinal: item.ordinal,
            targetSummary: item.target.description,
            failureReason: failureReason
        )
        let completion = forEachIterationCompletion(
            evidence: evidence,
            children: children,
            admitPassed: { HeistPassedForEachElementEvidence(admitted: $0) },
            admitFailed: { HeistFailedForEachElementEvidence(admitted: $0) },
            failureReason: failureReason,
            failure: forEachIterationFailure
        )
        return .forEachElementIteration(
            path: path,
            durationMs: durationMs,
            declaration: HeistForEachElementDeclaration(step),
            completion: completion
        )
    }

    private func forEachElementResult(
        path: HeistExecutionPath,
        start: RuntimeElapsed.Instant,
        step: ForEachElementStep,
        outcome: ForEachLoopOutcome
    ) -> HeistExecutionStepResult {
        let durationMs = elapsedMilliseconds(since: start)
        let evidence = HeistForEachElementEvidence.executedSummary(
            matchedCount: outcome.totalCount,
            iterationCount: outcome.iterationCount,
            failureReason: outcome.failureReason
        )
        let completion = forEachCompletion(
            evidence: evidence,
            outcome: outcome,
            admitPassed: { HeistPassedForEachElementEvidence(admitted: $0) },
            admitFailed: { HeistFailedForEachElementEvidence(admitted: $0) },
            failure: loopFailure(
                contract: "for_each_element completes all matched iterations",
                expected: "\(outcome.totalCount) iteration(s)"
            )
        )
        return .forEachElement(
            path: path,
            durationMs: durationMs,
            declaration: HeistForEachElementDeclaration(step),
            completion: completion
        )
    }

    func executeForEachStringStep(
        _ step: ForEachStringStep,
        index _: Int,
        path: HeistExecutionPath,
        start: RuntimeElapsed.Instant,
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
            iterationResult: { value, iterationIndex, iterationPath, iterationStart, children in
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
        start: RuntimeElapsed.Instant,
        step: ForEachStringStep,
        iterationIndex: Int,
        value: String,
        children: HeistExecutedChildren
    ) -> HeistExecutionStepResult {
        let durationMs = elapsedMilliseconds(since: start)
        let failureReason = children.abortedAtPath.map { "child failed at \($0)" }
        let evidence = HeistForEachStringEvidence.executedIteration(
            iterationCount: iterationIndex + 1,
            iterationOrdinal: iterationIndex,
            value: value,
            failureReason: failureReason
        )
        let completion = forEachIterationCompletion(
            evidence: evidence,
            children: children,
            admitPassed: { HeistPassedForEachStringEvidence(admitted: $0) },
            admitFailed: { HeistFailedForEachStringEvidence(admitted: $0) },
            failureReason: failureReason,
            failure: forEachIterationFailure
        )
        return .forEachStringIteration(
            path: path,
            durationMs: durationMs,
            declaration: HeistForEachStringDeclaration(step),
            completion: completion
        )
    }

    private func forEachStringResult(
        path: HeistExecutionPath,
        start: RuntimeElapsed.Instant,
        step: ForEachStringStep,
        outcome: ForEachLoopOutcome
    ) -> HeistExecutionStepResult {
        let durationMs = elapsedMilliseconds(since: start)
        let evidence = HeistForEachStringEvidence.executedSummary(
            iterationCount: outcome.iterationCount,
            failureReason: outcome.failureReason
        )
        let completion = forEachCompletion(
            evidence: evidence,
            outcome: outcome,
            admitPassed: { HeistPassedForEachStringEvidence(admitted: $0) },
            admitFailed: { HeistFailedForEachStringEvidence(admitted: $0) },
            failure: loopFailure(
                contract: "for_each_string completes all values",
                expected: "\(outcome.totalCount) value(s)"
            )
        )
        return .forEachString(
            path: path,
            durationMs: durationMs,
            declaration: HeistForEachStringDeclaration(step),
            completion: completion
        )
    }

    private func forEachIterationCompletion<Evidence, Passed, Failed>(
        evidence: Evidence,
        children: HeistExecutedChildren,
        admitPassed: (Evidence) -> Passed,
        admitFailed: (Evidence) -> Failed,
        failureReason: String?,
        failure: (_ observed: String, _ childPath: HeistExecutionPath?) -> HeistFailureDetail
    ) -> HeistExecutionCompletion<Passed, HeistEvidenceAvailability<Failed>, Failed>
    where Passed: Sendable & Equatable, Failed: Codable & Sendable & Equatable {
        switch children {
        case .passed(let children):
            return .passed(evidence: admitPassed(evidence), children: children)
        case .aborted(let children):
            return .childAborted(
                evidence: admitFailed(evidence),
                failure: failure(
                    failureReason ?? "child failed at \(children.abortedAtPath)",
                    children.abortedAtPath
                ),
                children: children
            )
        }
    }

    private func forEachCompletion<Evidence, Passed, Failed>(
        evidence: Evidence,
        outcome: ForEachLoopOutcome,
        admitPassed: (Evidence) -> Passed,
        admitFailed: (Evidence) -> Failed,
        failure: (_ observed: String, _ childPath: HeistExecutionPath?) -> HeistFailureDetail
    ) -> HeistExecutionCompletion<Passed, HeistEvidenceAvailability<Failed>, Failed>
    where Passed: Sendable & Equatable, Failed: Codable & Sendable & Equatable {
        switch outcome {
        case .completed(_, let children):
            return .passed(evidence: admitPassed(evidence), children: children)
        case .childFailed(_, let childFailure, let children):
            return .childAborted(
                evidence: admitFailed(evidence),
                failure: failure(childFailure.reason, childFailure.childPath),
                children: children
            )
        case .postObservationUnavailable(_, let iterationIndex, let children):
            let observed = "iteration \(iterationIndex) post-observation unavailable"
            return .failed(
                evidence: .observed(admitFailed(evidence)),
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
        start: RuntimeElapsed.Instant,
        step: ForEachElementStep
    ) -> HeistExecutionStepResult {
        let observed = "could not observe settled semantic hierarchy before evaluating for_each_element"
        let durationMs = elapsedMilliseconds(since: start)
        let evidence = HeistFailedForEachElementEvidence(admitted: .executedSummary(
            matchedCount: 0,
            iterationCount: 0,
            failureReason: observed
        ))
        return .forEachElement(
            path: path,
            durationMs: durationMs,
            declaration: HeistForEachElementDeclaration(step),
            completion: .failed(evidence: .observed(evidence), failure: HeistFailureDetail(
                category: .runtimeUnavailable,
                contract: "settled semantic hierarchy is observable before for_each_element matching",
                observed: observed
            ))
        )
    }

    private func forEachResolutionFailureResult(
        path: HeistExecutionPath,
        start: RuntimeElapsed.Instant,
        step: ForEachElementStep,
        error: Error
    ) -> HeistExecutionStepResult {
        let observed = "could not resolve for_each_element matcher: \(error)"
        let durationMs = elapsedMilliseconds(since: start)
        let evidence = HeistFailedForEachElementEvidence(admitted: .executedSummary(
            matchedCount: 0,
            iterationCount: 0,
            failureReason: observed
        ))
        return .forEachElement(
            path: path,
            durationMs: durationMs,
            declaration: HeistForEachElementDeclaration(step),
            completion: .failed(evidence: .observed(evidence), failure: HeistFailureDetail(
                category: .targetResolution,
                contract: "for_each_element matcher resolves before evaluation",
                observed: observed,
                expected: step.matching.description
            ))
        )
    }

    private func forEachLimitResult(
        index _: Int,
        path: HeistExecutionPath,
        start: RuntimeElapsed.Instant,
        matchedCount: Int,
        step: ForEachElementStep
    ) -> HeistExecutionStepResult {
        let observed = "matched \(matchedCount) element(s), exceeding for_each_element limit \(step.limit)"
        let durationMs = elapsedMilliseconds(since: start)
        let evidence = HeistFailedForEachElementEvidence(admitted: .executedSummary(
            matchedCount: matchedCount,
            iterationCount: 0,
            failureReason: observed
        ))
        return .forEachElement(
            path: path,
            durationMs: durationMs,
            declaration: HeistForEachElementDeclaration(step),
            completion: .failed(evidence: .observed(evidence), failure: HeistFailureDetail(
                category: .loop,
                contract: "for_each_element matched count does not exceed limit",
                observed: observed,
                expected: "at most \(step.limit) element(s)"
            ))
        )
    }
}

private struct ForEachMatchSignature: Equatable {
    let identities: [[AccessibilityMatcherFact]]

    var count: Int { identities.count }

    init(matching: ElementPredicate, elements: [HeistElement]) {
        identities = AccessibilityTargetMatchGraph(elements: elements)
            .resolve(matching)
            .elements
            .map(AccessibilityPolicy.matcherIdentityFacts(for:))
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
