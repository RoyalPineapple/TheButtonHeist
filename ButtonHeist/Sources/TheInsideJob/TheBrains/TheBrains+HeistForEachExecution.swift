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
            return forEachUnavailableResult(index: index, path: path, start: start, limit: step.limit)
        }

        var matchSignature = ForEachMatchSignature(
            matching: step.matching,
            elements: observation.state.interface.projectedElements
        )
        let matchedCount = matchSignature.count
        if matchedCount > step.limit {
            return forEachLimitResult(index: index, path: path, start: start, matchedCount: matchedCount, limit: step.limit)
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

            let iterationFailed = iterationResults.contains(where: \.isFailure)
            iterationNodes.append(HeistExecutionStepResult(
                index: iterationIndex,
                path: iterationPath,
                kind: .forEachIteration,
                message: "iteration \(iterationIndex) target ordinal \(nextOrdinal)",
                durationMs: elapsedMilliseconds(since: iterationStart),
                stopsHeist: iterationFailed,
                children: iterationResults
            ))

            if iterationFailed {
                failureReason = "iteration \(iterationIndex) failed"
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

        return HeistExecutionStepResult(
            index: index,
            path: path,
            kind: .forEachElement,
            message: forEachMessage(
                matchedCount: matchedCount,
                iterationCount: iterationCount,
                failureReason: failureReason
            ),
            durationMs: elapsedMilliseconds(since: start),
            stopsHeist: failureReason != nil,
            forEachResult: HeistForEachResult(
                matchedCount: matchedCount,
                limit: step.limit,
                iterationCount: iterationCount,
                failureReason: failureReason
            ),
            children: iterationNodes
        )
    }

    func executeForEachStringStep(
        _ step: ForEachStringStep,
        index: Int,
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

            let iterationFailed = iterationResults.contains(where: \.isFailure)
            iterationNodes.append(HeistExecutionStepResult(
                index: valueIndex,
                path: iterationPath,
                kind: .forEachIteration,
                message: "iteration \(valueIndex) value \"\(value)\"",
                durationMs: elapsedMilliseconds(since: iterationStart),
                stopsHeist: iterationFailed,
                children: iterationResults
            ))

            if iterationFailed {
                failureReason = "iteration \(valueIndex) failed for value \"\(value)\""
                break
            }
        }

        return HeistExecutionStepResult(
            index: index,
            path: path,
            kind: .forEachString,
            message: forEachStringMessage(
                valueCount: step.values.count,
                iterationCount: iterationCount,
                failureReason: failureReason
            ),
            durationMs: elapsedMilliseconds(since: start),
            stopsHeist: failureReason != nil,
            forEachResult: HeistForEachResult(
                matchedCount: step.values.count,
                limit: step.values.count,
                iterationCount: iterationCount,
                failureReason: failureReason
            ),
            children: iterationNodes
        )
    }

    private func forEachUnavailableResult(
        index: Int,
        path: String,
        start: CFAbsoluteTime,
        limit: Int
    ) -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            index: index,
            path: path,
            kind: .forEachElement,
            message: "Could not observe settled semantic hierarchy before evaluating for_each",
            durationMs: elapsedMilliseconds(since: start),
            stopsHeist: true,
            forEachResult: HeistForEachResult(
                matchedCount: 0,
                limit: limit,
                iterationCount: 0,
                failureReason: "semantic hierarchy unavailable"
            )
        )
    }

    private func forEachLimitResult(
        index: Int,
        path: String,
        start: CFAbsoluteTime,
        matchedCount: Int,
        limit: Int
    ) -> HeistExecutionStepResult {
        let reason = "matched \(matchedCount) element(s), exceeding for_each limit \(limit)"
        return HeistExecutionStepResult(
            index: index,
            path: path,
            kind: .forEachElement,
            message: reason,
            durationMs: elapsedMilliseconds(since: start),
            stopsHeist: true,
            forEachResult: HeistForEachResult(
                matchedCount: matchedCount,
                limit: limit,
                iterationCount: 0,
                failureReason: reason
            )
        )
    }

    private func forEachMessage(
        matchedCount: Int,
        iterationCount: Int,
        failureReason: String?
    ) -> String {
        if let failureReason {
            return "for_each stopped after \(iterationCount) of \(matchedCount) iteration(s): \(failureReason)"
        }
        return "for_each completed \(iterationCount) iteration(s) from \(matchedCount) matched element(s)"
    }

    private func forEachStringMessage(
        valueCount: Int,
        iterationCount: Int,
        failureReason: String?
    ) -> String {
        if let failureReason {
            return "for_each_string stopped after \(iterationCount) of \(valueCount) iteration(s): \(failureReason)"
        }
        return "for_each_string completed \(iterationCount) iteration(s) from \(valueCount) value(s)"
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

#endif // DEBUG
#endif // canImport(UIKit)
