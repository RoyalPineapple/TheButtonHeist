#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

private let defaultSemanticObservationTimeout: Double = 1

struct HeistSemanticObservation {
    let baseline: PostActionObservation.BeforeState
    let state: PostActionObservation.BeforeState
    let accessibilityTrace: AccessibilityTrace
    let delta: AccessibilityTrace.Delta?
    let summary: String
}

@MainActor
final class HeistSemanticObservations {
    private let stash: TheStash
    private let postActionObservation: PostActionObservation

    init(
        stash: TheStash,
        postActionObservation: PostActionObservation
    ) {
        self.stash = stash
        self.postActionObservation = postActionObservation
    }

    func observe(
        scope: SemanticObservationScope,
        baseline: PostActionObservation.BeforeState?,
        timeout: Double?
    ) async -> HeistSemanticObservation? {
        let baseline = baseline ?? latestSettledSemanticState()

        let observation: TheStash.SettledSemanticObservation?
        if timeout == 0 {
            observation = stash.latestSettledSemanticObservation.flatMap { latest in
                latest.scope >= scope ? latest : nil
            }
        } else {
            observation = await stash.settledSemanticObservation(
                scope: scope,
                after: baseline?.settledObservationSequence,
                timeout: timeout ?? defaultSemanticObservationTimeout
            )
        }

        guard let observation else { return nil }
        return semanticObservation(from: observation, baseline: baseline)
    }

    private func semanticObservation(
        from observation: TheStash.SettledSemanticObservation,
        baseline: PostActionObservation.BeforeState?
    ) -> HeistSemanticObservation {
        let current = postActionObservation.captureSemanticState(from: observation)
        let parent = baseline ?? current
        let trace = postActionObservation.makeClassifiedAccessibilityTrace(after: current, parent: parent)
        return HeistSemanticObservation(
            baseline: parent,
            state: current,
            accessibilityTrace: trace,
            delta: baseline == nil ? nil : trace.endpointDeltaProjection,
            summary: heistObservationSummary(current)
        )
    }

    func waitReceipt(for step: WaitStep) async -> HeistWaitReceipt {
        let start = CFAbsoluteTimeGetCurrent()
        let timeout = max(0, min(step.timeout, 30))
        var lastObservation: HeistSemanticObservation?
        var lastEvaluation = ExpectationResult(
            met: false,
            predicate: step.predicate,
            actual: "no settled semantic observation available"
        )

        if let initial = await observe(scope: step.predicate.observationScope, baseline: nil, timeout: 0) {
            lastObservation = initial
            lastEvaluation = evaluate(step.predicate, in: initial)
            if lastEvaluation.met {
                return waitReceipt(
                    for: step,
                    observation: initial,
                    expectation: lastEvaluation,
                    start: start,
                    success: true
                )
            }
        } else if timeout == 0 {
            return waitReceipt(
                for: step,
                observation: nil,
                expectation: lastEvaluation,
                start: start,
                success: false
            )
        }

        guard timeout > 0 else {
            return waitReceipt(
                for: step,
                observation: lastObservation,
                expectation: lastEvaluation,
                start: start,
                success: false
            )
        }

        let deadline = start + timeout
        var baseline = lastObservation?.state ?? latestSettledSemanticState()
        while CFAbsoluteTimeGetCurrent() < deadline {
            let remaining = max(0, deadline - CFAbsoluteTimeGetCurrent())
            guard let observation = await observe(
                scope: step.predicate.observationScope,
                baseline: baseline,
                timeout: min(remaining, defaultSemanticObservationTimeout)
            ) else {
                continue
            }

            baseline = observation.state
            lastObservation = observation
            lastEvaluation = evaluate(step.predicate, in: observation)
            if lastEvaluation.met {
                return waitReceipt(
                    for: step,
                    observation: observation,
                    expectation: lastEvaluation,
                    start: start,
                    success: true
                )
            }
        }

        return waitReceipt(
            for: step,
            observation: lastObservation,
            expectation: lastEvaluation,
            start: start,
            success: false
        )
    }

    func latestSettledSemanticState() -> PostActionObservation.BeforeState? {
        stash.latestSettledSemanticObservation.map(postActionObservation.captureSemanticState(from:))
    }

    func refreshDeliveredBaselineAfterStep() async -> Bool {
        latestSettledSemanticState() != nil
    }

    private func evaluate(
        _ predicate: AccessibilityPredicate,
        in observation: HeistSemanticObservation
    ) -> ExpectationResult {
        predicate.evaluate(
            currentElements: observation.state.interface.projectedElements,
            delta: observation.delta
        )
    }

    private func heistObservationSummary(_ state: PostActionObservation.BeforeState) -> String {
        var parts = ["known: \(state.interface.projectedElements.count) elements"]
        if let screenId = state.screenId {
            parts.insert("screen: \(screenId)", at: 0)
        }
        return parts.joined(separator: "; ")
    }

    private func waitReceipt(
        for step: WaitStep,
        observation: HeistSemanticObservation?,
        expectation: ExpectationResult,
        start: CFAbsoluteTime,
        success: Bool
    ) -> HeistWaitReceipt {
        var builder = ActionResultBuilder(method: .wait)
        builder.accessibilityTrace = observation?.accessibilityTrace
        builder.message = success
            ? waitSuccessMessage(for: step.predicate, start: start)
            : waitTimeoutMessage(
                for: step,
                expectation: expectation,
                observation: observation,
                start: start
            )

        let actionResult = success
            ? builder.success()
            : builder.failure(errorKind: .timeout)
        return HeistWaitReceipt(actionResult: actionResult, expectation: expectation)
    }

    private func waitSuccessMessage(
        for predicate: AccessibilityPredicate,
        start: CFAbsoluteTime
    ) -> String {
        let elapsed = elapsedSeconds(since: start)
        switch predicate {
        case .state(.present):
            return elapsed == "0.0" ? "matched immediately" : "matched after \(elapsed)s"
        case .state(.absent):
            return "absent confirmed after \(elapsed)s"
        default:
            return "predicate met after \(elapsed)s"
        }
    }

    private func waitTimeoutMessage(
        for step: WaitStep,
        expectation: ExpectationResult,
        observation: HeistSemanticObservation?,
        start: CFAbsoluteTime
    ) -> String {
        let elapsed = elapsedSeconds(since: start)
        if let presenceMessage = presenceWaitTimeoutMessage(for: step.predicate, elapsed: elapsed) {
            return presenceMessage
        }

        return [
            "timed out after \(elapsed)s waiting for heist predicate",
            "expected: \(step.predicate.description)",
            "last result: \(expectation.actual ?? "not met")",
            "last observed: \(observation?.summary ?? "no settled semantic observation available")",
        ].joined(separator: "; ")
    }

    private func presenceWaitTimeoutMessage(
        for predicate: AccessibilityPredicate,
        elapsed: String
    ) -> String? {
        let target: ElementTarget
        let absent: Bool
        switch predicate {
        case .state(.present(let elementPredicate)):
            target = .predicate(elementPredicate, ordinal: 0)
            absent = false
        case .state(.absent(let elementPredicate)):
            target = .predicate(elementPredicate, ordinal: 0)
            absent = true
        default:
            return nil
        }

        let resolution = stash.resolveTarget(target)
        let expected = absent ? "element to disappear" : "element to appear"
        let reason = absent ? "element still present" : "element not found"
        let diagnostics = resolution.diagnostics
        var parts = [
            "timed out after \(elapsed)s waiting for \(expected)",
            "expected: \(waitForTargetDescription(target))",
            "known: \(stash.knownElementCount) elements",
        ]
        if let screenId = stash.lastScreenId {
            parts.append("screen: \(screenId)")
        }
        if diagnostics.isEmpty {
            parts.append("last result: \(reason)")
        } else {
            parts.append("last result: \(reason): \(diagnostics)")
        }
        parts.append(
            "Next: get_interface() to inspect current elements, " +
                "then retry wait with an exact predicate."
        )
        return parts.joined(separator: "; ")
    }

    private func waitForTargetDescription(_ target: ElementTarget) -> String {
        switch target {
        case .predicate(let predicate, let ordinal):
            var description = TheStash.Diagnostics.formatMatcher(predicate)
            if let ordinal {
                description += " ordinal=\(ordinal)"
            }
            return description
        }
    }

    private func elapsedSeconds(since start: CFAbsoluteTime) -> String {
        String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
    }
}

extension ConditionalStep {
    var observationScope: SemanticObservationScope {
        cases
            .map(\.predicate.observationScope)
            .max() ?? .visible
    }
}

extension WaitForCasesStep {
    var observationScope: SemanticObservationScope {
        cases
            .map(\.predicate.observationScope)
            .max() ?? .visible
    }
}

extension AccessibilityPredicate {
    var observationScope: SemanticObservationScope {
        switch self {
        case .state(let state):
            return state.observationScope
        case .changed(let change):
            return change.observationScope
        }
    }
}

private extension AccessibilityPredicate.State {
    var observationScope: SemanticObservationScope {
        switch self {
        case .present, .absent, .presentTarget, .absentTarget:
            return .visible
        case .all(let states):
            return states
                .map(\.observationScope)
                .max() ?? .visible
        }
    }
}

private extension AccessibilityPredicate.Change {
    var observationScope: SemanticObservationScope {
        switch self {
        case .screen(let state):
            return state?.observationScope ?? .visible
        case .elements:
            return .visible
        case .appeared:
            return .discovery
        case .disappeared, .updated:
            return .visible
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
