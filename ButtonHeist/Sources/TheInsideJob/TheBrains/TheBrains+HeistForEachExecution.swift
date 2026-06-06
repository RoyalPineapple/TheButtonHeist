#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

extension TheBrains {
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

        var matchSignature = ForEachMatchSignature(
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

        var iterationNodes: [HeistExecutionStepResult] = []
        var failureReason: String?
        var iterationCount = 0
        var nextOrdinal = 0
        var observedSequence = observation.event.sequence

        while iterationCount < matchedCount {
            let iterationIndex = iterationCount
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
            iterationCount += 1

            let abortedAtChildPath = iterationResults.firstFailedStep?.path
            iterationNodes.append(forEachElementIterationResult(
                path: iterationPath,
                start: iterationStart,
                step: step,
                matchedCount: matchedCount,
                iterationIndex: iterationIndex,
                targetOrdinal: nextOrdinal,
                abortedAtChildPath: abortedAtChildPath,
                children: iterationResults
            ))

            if let abortedAtChildPath {
                failureReason = "iteration \(iterationIndex) failed at \(abortedAtChildPath)"
                break
            }

            guard iterationCount < matchedCount else { break }
            guard let afterObservation = await runtime.observeSemanticState(
                .discovery,
                observedSequence,
                nil
            ) else {
                failureReason = "iteration \(iterationIndex) post-observation unavailable"
                break
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

        return forEachElementResult(
            path: path,
            start: start,
            step: step,
            matchedCount: matchedCount,
            iterationCount: iterationCount,
            failureReason: failureReason,
            iterationNodes: iterationNodes
        )
    }

    private func forEachElementIterationResult(
        path: String,
        start: CFAbsoluteTime,
        step: ForEachElementStep,
        matchedCount: Int,
        iterationIndex: Int,
        targetOrdinal: Int,
        abortedAtChildPath: String?,
        children: [HeistExecutionStepResult]
    ) -> HeistExecutionStepResult {
        let currentElement = ElementTarget.predicate(step.matching, ordinal: targetOrdinal)
        HeistExecutionStepResult(
            path: path,
            kind: .forEachIteration,
            status: abortedAtChildPath == nil ? .passed : .failed,
            durationMs: elapsedMilliseconds(since: start),
            intent: .forEachElement(parameter: step.parameter, matching: step.matching.description, limit: step.limit),
            evidence: .forEachElement(HeistForEachElementEvidence(
                parameter: step.parameter,
                matching: step.matching,
                limit: step.limit,
                matchedCount: matchedCount,
                iterationCount: iterationIndex + 1,
                iterationOrdinal: iterationIndex,
                targetOrdinal: targetOrdinal,
                targetSummary: currentElement.description,
                failureReason: abortedAtChildPath.map { "child failed at \($0)" }
            )),
            failure: abortedAtChildPath.map {
                childFailureDetail(category: .loop, childPath: $0)
            },
            abortedAtChildPath: abortedAtChildPath,
            children: children
        )
    }

    private func forEachElementResult(
        path: String,
        start: CFAbsoluteTime,
        step: ForEachElementStep,
        matchedCount: Int,
        iterationCount: Int,
        failureReason: String?,
        iterationNodes: [HeistExecutionStepResult]
    ) -> HeistExecutionStepResult {
        let abortedAtChildPath = iterationNodes.firstFailedStep?.path
        return HeistExecutionStepResult(
            path: path,
            kind: .forEachElement,
            status: failureReason == nil ? .passed : .failed,
            durationMs: elapsedMilliseconds(since: start),
            intent: .forEachElement(parameter: step.parameter, matching: step.matching.description, limit: step.limit),
            evidence: .forEachElement(HeistForEachElementEvidence(
                parameter: step.parameter,
                matching: step.matching,
                limit: step.limit,
                matchedCount: matchedCount,
                iterationCount: iterationCount,
                failureReason: failureReason
            )),
            failure: failureReason.map {
                HeistFailureDetail(
                    category: .loop,
                    contract: "for_each_element completes all matched iterations",
                    observed: $0,
                    expected: "\(matchedCount) iteration(s)"
                )
            },
            abortedAtChildPath: abortedAtChildPath,
            children: iterationNodes
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
        var iterationNodes: [HeistExecutionStepResult] = []
        var failureReason: String?
        var iterationCount = 0

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
            iterationCount += 1

            let abortedAtChildPath = iterationResults.firstFailedStep?.path
            iterationNodes.append(HeistExecutionStepResult(
                path: iterationPath,
                kind: .forEachIteration,
                status: abortedAtChildPath == nil ? .passed : .failed,
                durationMs: elapsedMilliseconds(since: iterationStart),
                intent: .forEachString(parameter: step.parameter, count: step.values.count),
                evidence: .forEachString(HeistForEachStringEvidence(
                    parameter: step.parameter,
                    count: step.values.count,
                    iterationCount: iterationCount,
                    iterationOrdinal: valueIndex,
                    value: value,
                    failureReason: abortedAtChildPath.map { "child failed at \($0)" }
                )),
                failure: abortedAtChildPath.map {
                    childFailureDetail(category: .loop, childPath: $0)
                },
                abortedAtChildPath: abortedAtChildPath,
                children: iterationResults
            ))

            if let abortedAtChildPath {
                failureReason = "iteration \(valueIndex) failed for value \"\(value)\" at \(abortedAtChildPath)"
                break
            }
        }

        let abortedAtChildPath = iterationNodes.firstFailedStep?.path
        return HeistExecutionStepResult(
            path: path,
            kind: .forEachString,
            status: failureReason == nil ? .passed : .failed,
            durationMs: elapsedMilliseconds(since: start),
            intent: .forEachString(parameter: step.parameter, count: step.values.count),
            evidence: .forEachString(HeistForEachStringEvidence(
                parameter: step.parameter,
                count: step.values.count,
                iterationCount: iterationCount,
                failureReason: failureReason
            )),
            failure: failureReason.map {
                HeistFailureDetail(
                    category: .loop,
                    contract: "for_each_string completes all values",
                    observed: $0,
                    expected: "\(step.values.count) value(s)"
                )
            },
            abortedAtChildPath: abortedAtChildPath,
            children: iterationNodes
        )
    }

    private func forEachUnavailableResult(
        index _: Int,
        path: String,
        start: CFAbsoluteTime,
        parameter: String,
        matching: ElementPredicate,
        limit: Int
    ) -> HeistExecutionStepResult {
        let observed = "could not observe settled semantic hierarchy before evaluating for_each_element"
        return HeistExecutionStepResult(
            path: path,
            kind: .forEachElement,
            status: .failed,
            durationMs: elapsedMilliseconds(since: start),
            intent: .forEachElement(parameter: parameter, matching: matching.description, limit: limit),
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
        parameter: String,
        matching: ElementPredicate,
        matchedCount: Int,
        limit: Int
    ) -> HeistExecutionStepResult {
        let observed = "matched \(matchedCount) element(s), exceeding for_each_element limit \(limit)"
        return HeistExecutionStepResult(
            path: path,
            kind: .forEachElement,
            status: .failed,
            durationMs: elapsedMilliseconds(since: start),
            intent: .forEachElement(parameter: parameter, matching: matching.description, limit: limit),
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
        keys = elements
            .filter { matching.matches($0) }
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

private extension Array where Element == HeistExecutionStepResult {
    var firstFailedStep: HeistExecutionStepResult? {
        for step in self {
            if let failed = step.firstFailedStep {
                return failed
            }
        }
        return nil
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
