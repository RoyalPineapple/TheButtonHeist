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
        guard let observation = await runtime.observePredicate(.fullSemanticExplore, nil, nil) else {
            return HeistExecutionStepResult(
                index: index,
                kind: .forEach,
                message: "Could not observe settled semantic hierarchy before evaluating for_each",
                durationMs: elapsedMilliseconds(since: start),
                stopsHeist: true,
                forEachResult: HeistForEachResult(
                    matchedCount: 0,
                    limit: step.limit,
                    iterationCount: 0,
                    failureReason: "semantic hierarchy unavailable"
                )
            )
        }

        let matchedCount = observation.state.interface.projectedElements.count { step.matching.matches($0) }
        if matchedCount > step.limit {
            let reason = "matched \(matchedCount) element(s), exceeding for_each limit \(step.limit)"
            return HeistExecutionStepResult(
                index: index,
                kind: .forEach,
                message: reason,
                durationMs: elapsedMilliseconds(since: start),
                stopsHeist: true,
                forEachResult: HeistForEachResult(
                    matchedCount: matchedCount,
                    limit: step.limit,
                    iterationCount: 0,
                    failureReason: reason
                )
            )
        }

        var childResults: [HeistExecutionStepResult] = []
        var failureReason: String?
        var iterationCount = 0

        for iterationIndex in 0..<matchedCount {
            let iterationResults = await executeHeistSteps(step.steps, runtime: runtime)
            iterationCount += 1

            for result in iterationResults {
                childResults.append(result.reindexed(childResults.count))
            }

            if iterationResults.contains(where: \.isFailure) {
                failureReason = "iteration \(iterationIndex) failed"
                break
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

#endif // DEBUG
#endif // canImport(UIKit)
