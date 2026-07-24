#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

extension TheBrains {
    internal func actionResolutionFailureResult(
        _ failure: HeistActionResolutionFailure,
        path: HeistExecutionPath,
        start: RuntimeElapsed.Instant
    ) -> HeistExecutionStepResult {
        let detail = HeistFailureDetail(
            category: .targetResolution,
            contract: "action command resolves before dispatch",
            observed: "could not resolve heist action command: \(failure.errorDescription)",
            expected: failure.command.reportTarget.map(String.init(describing:))
        )
        let execution = HeistActionExecution.failed(
            command: failure.command,
            evidence: .init(admitted: .commandResolutionFailure),
            failure: detail
        )
        return actionFailureResult(
            execution: execution,
            path: path,
            start: start
        )
    }

    internal func expectationResolutionFailureResult(
        _ failure: HeistExpectationResolutionFailure,
        command: HeistActionCommand,
        actionResult: ActionResult,
        path: HeistExecutionPath,
        start: RuntimeElapsed.Instant
    ) -> HeistExecutionStepResult {
        let observed = "could not resolve heist expectation: \(failure.errorDescription)"
        let expectation = ExpectationResult.Unmet(predicate: nil, actual: observed)
        let evidence = HeistActionEvidence.completed(
            result: actionResult,
            expectation: expectation.result
        )
        let execution = HeistActionExecution.failed(
            command: command,
            evidence: .init(admitted: evidence),
            failure: HeistFailureDetail(
                category: .expectation,
                contract: "action expectation predicate resolves before evaluation",
                observed: observed,
                expected: failure.wait.predicate.description
            )
        )
        return actionFailureResult(
            execution: execution,
            path: path,
            start: start
        )
    }

    internal func standaloneWaitResolutionFailureResult(
        _ failure: HeistStandaloneWaitResolutionFailure,
        path: HeistExecutionPath,
        start: RuntimeElapsed.Instant
    ) -> HeistExecutionStepResult {
        let durationMs = elapsedMilliseconds(since: start)
        return .wait(
            path: path,
            durationMs: durationMs,
            predicate: failure.wait.predicate,
            timeout: failure.wait.timeout,
            completion: .failed(
                evidence: .unavailable,
                failure: HeistFailureDetail(
                    category: .wait,
                    contract: "wait predicate resolves before evaluation",
                    observed: "could not resolve heist wait predicate: \(failure.errorDescription)",
                    expected: failure.wait.predicate.description
                )
            )
        )
    }

    internal func actionDispatchFailureDetail(
        command: HeistActionCommand,
        result: ActionResult
    ) -> HeistFailureDetail {
        HeistFailureDetail(
            category: result.outcome.failureKind == .elementNotFound ? .targetResolution : .action,
            contract: "action dispatch succeeds",
            observed: actionObserved(result, command: command),
            expected: command.reportTarget.map(String.init(describing:))
        )
    }

    internal func actionExpectationFailureDetail(
        wait: WaitStep,
        evidence: HeistActionEvidence
    ) -> HeistFailureDetail {
        let result = evidence.result
        let observed = [
            evidence.expectation?.actual,
            result?.message,
            result?.outcome.failureKind.map { "failureKind=\($0.rawValue)" },
            result?.settled.map { "settled=\($0)" },
        ].compactMap { $0 }.joined(separator: "; ")
        return HeistFailureDetail(
            category: .expectation,
            contract: "post-action expectation is met",
            observed: observed,
            expected: wait.predicate.description
        )
    }

    internal func standaloneWaitFailureDetail(
        wait: WaitStep,
        evidence: HeistSettlementEvidence
    ) -> HeistFailureDetail {
        HeistFailureDetail(
            category: .wait,
            contract: "wait predicate is met before timeout",
            observed: expectationObserved(evidence),
            expected: wait.predicate.description
        )
    }

    internal func childFailureDetail(
        category: HeistFailureCategory,
        childPath: HeistExecutionPath
    ) -> HeistFailureDetail {
        HeistFailureDetail(
            category: category,
            contract: "child execution completes without failure",
            observed: "child failed at \(childPath)",
            expected: "all executed child steps pass"
        )
    }

    internal func failureScreenshotDetail(for result: ActionResult) -> HeistFailureDetail {
        HeistFailureDetail(
            category: .action,
            contract: "failure screenshot action captures visible screen",
            observed: result.message ?? "screenshot action failed",
            expected: HeistActionCommandType.takeScreenshot.rawValue
        )
    }

    private func actionFailureResult(
        execution: HeistActionExecution,
        path: HeistExecutionPath,
        start: RuntimeElapsed.Instant
    ) -> HeistExecutionStepResult {
        let durationMs = elapsedMilliseconds(since: start)
        return .action(
            path: path,
            durationMs: durationMs,
            execution: execution
        )
    }

    private func actionObserved(_ result: ActionResult, command: HeistActionCommand) -> String {
        [
            result.message,
            result.outcome.failureKind.map { "failureKind=\($0.rawValue)" },
            result.settled.map { "settled=\($0)" },
            failureInterfaceSuggestion(for: command, result: result),
        ].compactMap { $0 }.joined(separator: "; ")
    }

    private func failureInterfaceSuggestion(
        for command: HeistActionCommand,
        result: ActionResult
    ) -> String? {
        guard result.outcome.failureKind == .elementNotFound,
              let target = command.reportTarget,
              let elements = result.accessibilityTrace?.captures.last?.interface.projectedElements else {
            return nil
        }
        guard let predicate = failureSuggestionPredicate(for: target) else { return nil }
        return TheVault.Diagnostics.failureInterfaceSuggestion(for: predicate, elements: elements)
    }

    private func failureSuggestionPredicate(for target: AccessibilityTarget) -> ElementPredicate? {
        switch target {
        case .predicate(let template, _):
            return try? template.resolve(in: .empty)
        case .within(_, let target):
            return failureSuggestionPredicate(for: target)
        case .container, .ref:
            return nil
        }
    }

    private func expectationObserved(_ evidence: HeistSettlementEvidence) -> String {
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
