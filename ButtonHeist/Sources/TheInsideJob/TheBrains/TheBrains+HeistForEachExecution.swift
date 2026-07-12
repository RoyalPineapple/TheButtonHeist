#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans

import TheScore

extension TheBrains {
    private struct ForEachLoopOutcome {
        let totalCount: Int
        let termination: ForEachLoopTermination
        let iterationChildren: HeistReceiptChildren

        var iterationCount: Int {
            iterationNodes.count
        }

        var iterationNodes: [HeistExecutionStepResult] {
            iterationChildren.children
        }

        var status: HeistExecutionStepStatus {
            termination.status
        }

        var failureReason: String? {
            termination.failureReason
        }

        var abortedAtChildPath: String? {
            iterationChildren.abortedAtChildPath
        }
    }

    private enum ForEachLoopTermination {
        case completed
        case childFailed(ForEachLoopChildFailure)
        case postObservationUnavailable(iterationIndex: Int)

        var status: HeistExecutionStepStatus {
            switch self {
            case .completed:
                return .passed
            case .childFailed, .postObservationUnavailable:
                return .failed
            }
        }

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

        var abortedAtChildPath: String? {
            switch self {
            case .completed, .postObservationUnavailable:
                return nil
            case .childFailed(let failure):
                return failure.childPath
            }
        }
    }

    private struct ForEachLoopChildFailure {
        let iterationIndex: Int
        let value: String?
        let childPath: String

        var reason: String {
            if let value {
                return "iteration \(iterationIndex) failed for value \"\(value)\" at \(childPath)"
            }
            return "iteration \(iterationIndex) failed at \(childPath)"
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
            matching: step.matching,
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

        let outcome = await forEachElementLoopOutcome(
            step: step,
            path: path,
            runtime: runtime,
            environment: environment,
            scope: scope,
            initialMatchSignature: matchSignature,
            initialObservedSequence: observation.event.sequence
        )

        return forEachElementResult(
            path: path,
            start: start,
            step: step,
            outcome: outcome
        )
    }

    private func forEachElementLoopOutcome(
        step: ForEachElementStep,
        path: String,
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment,
        scope: HeistExecutionScope,
        initialMatchSignature: ForEachMatchSignature,
        initialObservedSequence: SettledObservationSequence
    ) async -> ForEachLoopOutcome {
        var matchSignature = initialMatchSignature
        var iterationNodes: [HeistExecutionStepResult] = []
        var nextOrdinal = 0
        var observedSequence = initialObservedSequence
        let matchedCount = initialMatchSignature.count

        while iterationNodes.count < matchedCount {
            let iterationIndex = iterationNodes.count
            let iterationStart = CFAbsoluteTimeGetCurrent()
            let iterationPath = "\(path).for_each_element.iterations[\(iterationIndex)]"
            let currentElement = ElementTarget.predicate(step.matching, ordinal: nextOrdinal)
            let iterationEnvironment = environment.binding(target: currentElement, to: step.parameter)
            let iterationResults = await executeHeistSteps(
                step.body,
                runtime: runtime,
                environment: iterationEnvironment,
                scope: scope,
                path: "\(iterationPath).body"
            )

            let iterationChildren = HeistReceiptChildren(iterationResults)
            iterationNodes.append(forEachElementIterationResult(
                path: iterationPath,
                start: iterationStart,
                step: step,
                matchedCount: matchedCount,
                iterationIndex: iterationIndex,
                targetOrdinal: nextOrdinal,
                children: iterationChildren
            ))

            if let abortedAtChildPath = iterationChildren.abortedAtChildPath {
                return ForEachLoopOutcome(
                    totalCount: matchedCount,
                    termination: .childFailed(ForEachLoopChildFailure(
                        iterationIndex: iterationIndex,
                        value: nil,
                        childPath: abortedAtChildPath
                    )),
                    iterationChildren: HeistReceiptChildren(iterationNodes)
                )
            }

            guard iterationNodes.count < matchedCount else { break }
            guard let afterObservation = await runtime.observeSemanticState(
                .discovery,
                observedSequence,
                nil
            ) else {
                return ForEachLoopOutcome(
                    totalCount: matchedCount,
                    termination: .postObservationUnavailable(iterationIndex: iterationIndex),
                    iterationChildren: HeistReceiptChildren(iterationNodes)
                )
            }
            observedSequence = afterObservation.event.sequence
            let nextSignature = ForEachMatchSignature(
                matching: step.matching,
                elements: afterObservation.state.interface.projectedElements
            )
            if nextSignature == matchSignature {
                nextOrdinal += 1
            } else {
                matchSignature = nextSignature
                nextOrdinal = 0
            }
        }

        return ForEachLoopOutcome(
            totalCount: matchedCount,
            termination: .completed,
            iterationChildren: HeistReceiptChildren(iterationNodes)
        )
    }

    private func forEachElementIterationResult(
        path: String,
        start: CFAbsoluteTime,
        step: ForEachElementStep,
        matchedCount: Int,
        iterationIndex: Int,
        targetOrdinal: Int,
        children: HeistReceiptChildren
    ) -> HeistExecutionStepResult {
        let currentElement = ElementTarget.predicate(step.matching, ordinal: targetOrdinal)
        let evidence = HeistStepEvidence.forEachElement(HeistForEachElementEvidence(
            parameter: step.parameter,
            matching: step.matching,
            limit: step.limit,
            matchedCount: matchedCount,
            iterationCount: iterationIndex + 1,
            iterationOrdinal: iterationIndex,
            targetOrdinal: targetOrdinal,
            targetSummary: currentElement.description,
            failureReason: children.abortedAtChildPath.map { "child failed at \($0)" }
        ))
        return heistLoopReceipt(
            path: path,
            kind: .forEachIteration,
            durationMs: elapsedMilliseconds(since: start),
            intent: .forEachElement(parameter: step.parameter, matching: step.matching, limit: step.limit),
            evidence: evidence,
            children: children,
            childFailure: { childPath in
                childFailureDetail(category: .loop, childPath: childPath)
            }
        )
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
        return forEachLoopReceipt(
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
        let outcome = await forEachStringLoopOutcome(
            step: step,
            path: path,
            runtime: runtime,
            environment: environment,
            scope: scope
        )
        return forEachStringResult(
            path: path,
            start: start,
            step: step,
            outcome: outcome
        )
    }

    private func forEachStringLoopOutcome(
        step: ForEachStringStep,
        path: String,
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment,
        scope: HeistExecutionScope
    ) async -> ForEachLoopOutcome {
        var iterationNodes: [HeistExecutionStepResult] = []

        for (valueIndex, value) in step.values.enumerated() {
            let iterationStart = CFAbsoluteTimeGetCurrent()
            let iterationPath = "\(path).for_each_string.iterations[\(valueIndex)]"
            let iterationEnvironment = environment.binding(string: value, to: step.parameter)
            let iterationResults = await executeHeistSteps(
                step.body,
                runtime: runtime,
                environment: iterationEnvironment,
                scope: scope,
                path: "\(iterationPath).body"
            )

            let iterationChildren = HeistReceiptChildren(iterationResults)
            let evidence = HeistStepEvidence.forEachString(HeistForEachStringEvidence(
                parameter: step.parameter,
                count: step.values.count,
                iterationCount: valueIndex + 1,
                iterationOrdinal: valueIndex,
                value: value,
                failureReason: iterationChildren.abortedAtChildPath.map { "child failed at \($0)" }
            ))
            iterationNodes.append(heistLoopReceipt(
                path: iterationPath,
                kind: .forEachIteration,
                durationMs: elapsedMilliseconds(since: iterationStart),
                intent: .forEachString(parameter: step.parameter, count: step.values.count),
                evidence: evidence,
                children: iterationChildren,
                childFailure: { childPath in
                    childFailureDetail(category: .loop, childPath: childPath)
                }
            ))

            if let abortedAtChildPath = iterationChildren.abortedAtChildPath {
                return ForEachLoopOutcome(
                    totalCount: step.values.count,
                    termination: .childFailed(ForEachLoopChildFailure(
                        iterationIndex: valueIndex,
                        value: value,
                        childPath: abortedAtChildPath
                    )),
                    iterationChildren: HeistReceiptChildren(iterationNodes)
                )
            }
        }

        return ForEachLoopOutcome(
            totalCount: step.values.count,
            termination: .completed,
            iterationChildren: HeistReceiptChildren(iterationNodes)
        )
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
        return forEachLoopReceipt(
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

    private func forEachLoopReceipt(
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
        return heistLoopReceipt(
            path: path,
            kind: kind,
            durationMs: durationMs,
            intent: intent,
            evidence: evidence,
            failure: receiptFailure,
            children: outcome.iterationChildren,
            childFailure: childFailure
        )
    }

    private func forEachUnavailableResult(
        index _: Int,
        path: String,
        start: CFAbsoluteTime,
        parameter: HeistReferenceName,
        matching: ElementPredicate,
        limit: Int
    ) -> HeistExecutionStepResult {
        let observed = "could not observe settled semantic hierarchy before evaluating for_each_element"
        return heistFailedReceipt(
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
            failure: HeistFailureDetail(
                category: .runtimeUnavailable,
                contract: "settled semantic hierarchy is observable before for_each_element matching",
                observed: observed
            )
        )
    }

    private func forEachLimitResult(
        index _: Int,
        path: String,
        start: CFAbsoluteTime,
        parameter: HeistReferenceName,
        matching: ElementPredicate,
        matchedCount: Int,
        limit: Int
    ) -> HeistExecutionStepResult {
        let observed = "matched \(matchedCount) element(s), exceeding for_each_element limit \(limit)"
        return heistFailedReceipt(
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
            failure: HeistFailureDetail(
                category: .loop,
                contract: "for_each_element matched count does not exceed limit",
                observed: observed,
                expected: "at most \(limit) element(s)"
            )
        )
    }
}

private struct ForEachMatchSignature: Equatable {
    let keys: [String]

    var count: Int { keys.count }

    init(matching: ElementPredicate, elements: [HeistElement]) {
        keys = ElementMatchGraph(elements: elements)
            .resolve(matching)
            .elements
            .map(Self.key)
    }

    private static func key(for element: HeistElement) -> String {
        AccessibilityPolicy.matcherIdentityFacts(for: element)
            .map(factKey)
            .joined(separator: "\u{1F}")
    }

    private static func factKey(_ fact: AccessibilityMatcherFact) -> String {
        switch fact {
        case .identifier(let identifier):
            return "identifier=\(identifier)"
        case .label(let label):
            return "label=\(label)"
        case .value(let value):
            return "value=\(value)"
        case .trait(let trait):
            return "trait=\(trait.rawValue)"
        case .excludedTrait(let trait):
            return "excludeTrait=\(trait.rawValue)"
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
