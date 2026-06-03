#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

extension TheBrains {
    func executeForEachStep(
        _ step: ForEachStep,
        index: Int,
        start: CFAbsoluteTime,
        runtime: HeistExecutionRuntime
    ) async -> HeistExecutionStepResult {
        guard let observation = await runtime.observeSemanticState(.discovery, nil, nil) else {
            return forEachUnavailableResult(index: index, start: start, limit: step.limit)
        }

        var matchSignature = ForEachMatchSignature(
            matching: step.matching,
            elements: observation.state.interface.projectedElements
        )
        let matchedCount = matchSignature.count
        if matchedCount > step.limit {
            return forEachLimitResult(index: index, start: start, matchedCount: matchedCount, limit: step.limit)
        }

        var childResults: [HeistExecutionStepResult] = []
        var failureReason: String?
        var iterationCount = 0
        var nextOrdinal = 0
        var observedSequence = observation.event.sequence

        while iterationCount < matchedCount {
            let currentElement = ElementTarget.predicate(step.matching, ordinal: nextOrdinal)
            let iterationSteps: [HeistStep]
            do {
                iterationSteps = try step.steps(for: currentElement)
            } catch {
                failureReason = "iteration \(iterationCount) body failed: \(error)"
                break
            }
            guard !iterationSteps.isEmpty else {
                failureReason = "iteration \(iterationCount) body produced no steps"
                break
            }
            guard !iterationSteps.containsRuntimeForEach else {
                failureReason = "iteration \(iterationCount) body contains unsupported nested runtime for_each"
                break
            }

            let iterationResults = await executeHeistSteps(iterationSteps, runtime: runtime)
            iterationCount += 1

            for result in iterationResults {
                childResults.append(result.reindexed(childResults.count))
            }

            if iterationResults.contains(where: \.isFailure) {
                failureReason = "iteration \(iterationCount - 1) failed"
                break
            }

            guard iterationCount < matchedCount else { break }
            guard let afterObservation = await runtime.observeSemanticState(
                .discovery,
                observedSequence,
                nil
            ) else {
                failureReason = "iteration \(iterationCount - 1) post-observation unavailable"
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
            kind: .forEach,
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
            childResults: childResults.isEmpty ? nil : childResults
        )
    }

    private func forEachUnavailableResult(
        index: Int,
        start: CFAbsoluteTime,
        limit: Int
    ) -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            index: index,
            kind: .forEach,
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
        start: CFAbsoluteTime,
        matchedCount: Int,
        limit: Int
    ) -> HeistExecutionStepResult {
        let reason = "matched \(matchedCount) element(s), exceeding for_each limit \(limit)"
        return HeistExecutionStepResult(
            index: index,
            kind: .forEach,
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
}

private extension Array where Element == HeistStep {
    var containsRuntimeForEach: Bool {
        contains { step in
            switch step {
            case .forEach:
                return true
            case .conditional(let conditional):
                return conditional.cases.contains { $0.steps.containsRuntimeForEach }
                    || conditional.elseSteps?.containsRuntimeForEach == true
            case .waitForCases(let waitForCases):
                return waitForCases.cases.contains { $0.steps.containsRuntimeForEach }
                    || waitForCases.elseSteps?.containsRuntimeForEach == true
            case .action, .wait, .warn, .fail:
                return false
            }
        }
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
