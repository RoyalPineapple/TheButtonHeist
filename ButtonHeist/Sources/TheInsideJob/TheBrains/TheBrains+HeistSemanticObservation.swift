#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

struct HeistSemanticObservation {
    let baseline: PostActionObservation.BeforeState
    let state: PostActionObservation.BeforeState
    let accessibilityTrace: AccessibilityTrace
    let delta: AccessibilityTrace.Delta?
    let summary: String
}

enum HeistSemanticObservationScope: Equatable {
    case visibleRefresh
    case revealTargets([ElementTarget])
    case fullSemanticExplore

    func merged(with other: HeistSemanticObservationScope) -> HeistSemanticObservationScope {
        switch (self, other) {
        case (.fullSemanticExplore, _), (_, .fullSemanticExplore):
            return .fullSemanticExplore
        case (.revealTargets(let left), .revealTargets(let right)):
            return .revealTargets(left + right)
        case (.revealTargets, .visibleRefresh):
            return self
        case (.visibleRefresh, .revealTargets):
            return other
        case (.visibleRefresh, .visibleRefresh):
            return .visibleRefresh
        }
    }
}

@MainActor
final class HeistSemanticObservations {
    private let stash: TheStash
    private let tripwire: TheTripwire
    private let navigation: Navigation
    private let postActionObservation: PostActionObservation

    init(
        stash: TheStash,
        tripwire: TheTripwire,
        navigation: Navigation,
        postActionObservation: PostActionObservation
    ) {
        self.stash = stash
        self.tripwire = tripwire
        self.navigation = navigation
        self.postActionObservation = postActionObservation
    }

    func observe(
        scope: HeistSemanticObservationScope,
        baseline: PostActionObservation.BeforeState?,
        timeout: Double?
    ) async -> HeistSemanticObservation? {
        let observationBaseline: PostActionObservation.BeforeState
        var current: PostActionObservation.BeforeState
        if let observedBaseline = baseline {
            observationBaseline = observedBaseline
            guard let settled = await postActionObservation.settledSemanticState(after: observedBaseline, timeout: timeout) else {
                return nil
            }
            current = settled
        } else {
            guard let observed = await postActionObservation.currentSemanticState() else {
                return nil
            }
            observationBaseline = observed
            current = observed
        }

        switch scope {
        case .visibleRefresh:
            break
        case .fullSemanticExplore:
            _ = await navigation.exploreAndPrune()
            current = postActionObservation.captureSemanticState()
        case .revealTargets(let targets):
            let needsExplore = await revealHeistObservationTargets(targets)
            if needsExplore {
                _ = await navigation.exploreAndPrune()
                current = postActionObservation.captureSemanticState()
            } else if !targets.isEmpty,
                      let refreshed = await postActionObservation.settledSemanticState(after: current, timeout: timeout) {
                current = refreshed
            }
        }

        let trace = postActionObservation.makeClassifiedAccessibilityTrace(after: current, parent: observationBaseline)
        return HeistSemanticObservation(
            baseline: observationBaseline,
            state: current,
            accessibilityTrace: trace,
            delta: trace.endpointDeltaProjection,
            summary: heistObservationSummary(current)
        )
    }

    func waitReceipt(for step: WaitStep) async -> HeistWaitReceipt {
        let start = CFAbsoluteTimeGetCurrent()
        let timeout = max(0, min(step.timeout, 30))
        let deadline = start + timeout
        var baseline: PostActionObservation.BeforeState?
        var lastObservation: HeistSemanticObservation?
        var lastEvaluation = ExpectationResult(
            met: false,
            predicate: step.predicate,
            actual: "no settled accessibility state observed"
        )

        repeat {
            let remaining = max(0, deadline - CFAbsoluteTimeGetCurrent())
            let observation = await observe(
                scope: step.predicate.observationScope,
                baseline: baseline,
                timeout: min(remaining, 1.0)
            )

            guard let observation else {
                if timeout == 0 { break }
                continue
            }

            baseline = observation.state
            lastObservation = observation
            lastEvaluation = step.predicate.evaluate(
                currentElements: observation.state.interface.projectedElements,
                delta: observation.delta
            )

            if lastEvaluation.met {
                return waitReceipt(
                    for: step,
                    observation: observation,
                    expectation: lastEvaluation,
                    start: start,
                    success: true
                )
            }

            if timeout == 0 { break }
        } while CFAbsoluteTimeGetCurrent() < deadline

        return waitReceipt(
            for: step,
            observation: lastObservation,
            expectation: lastEvaluation,
            start: start,
            success: false
        )
    }

    func refreshDeliveredBaselineAfterStep() async -> Bool {
        _ = await tripwire.waitForAllClear(timeout: 0.5)
        return stash.recordVisibleSemanticObservation() != nil
    }

    private func revealHeistObservationTargets(_ targets: [ElementTarget]) async -> Bool {
        var needsExplore = false
        for target in targets {
            switch stash.resolveTarget(target) {
            case .resolved:
                _ = await navigation.executeScrollToVisible(elementTarget: target)
            case .ambiguous:
                continue
            case .notFound:
                needsExplore = true
            }
        }
        return needsExplore
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
            ? "predicate met after \(elapsedSeconds(since: start))s"
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

    private func unavailableWaitReceipt(for step: WaitStep) -> HeistWaitReceipt {
        var builder = ActionResultBuilder(method: .wait)
        builder.message = "Could not observe settled accessibility state before evaluating wait predicate"
        let actionResult = builder.failure(errorKind: .actionFailed)
        return HeistWaitReceipt(
            actionResult: actionResult,
            expectation: ExpectationResult(
                met: false,
                predicate: step.predicate,
                actual: builder.message
            )
        )
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
            "last observed: \(observation?.summary ?? "no settled accessibility state")",
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
    var observationScope: HeistSemanticObservationScope {
        cases
            .map(\.predicate.observationScope)
            .reduce(.visibleRefresh) { $0.merged(with: $1) }
    }
}

extension WaitForCasesStep {
    var observationScope: HeistSemanticObservationScope {
        cases
            .map(\.predicate.observationScope)
            .reduce(.visibleRefresh) { $0.merged(with: $1) }
    }
}

extension AccessibilityPredicate {
    var observationScope: HeistSemanticObservationScope {
        switch self {
        case .state(let state):
            return state.observationScope
        case .changed(let change):
            return change.observationScope
        }
    }
}

private extension AccessibilityPredicate.State {
    var observationScope: HeistSemanticObservationScope {
        switch self {
        case .present(let predicate), .absent(let predicate):
            return .revealTargets([.predicate(predicate)])
        case .presentTarget(let target), .absentTarget(let target):
            return .revealTargets([target])
        case .all(let states):
            return states
                .map(\.observationScope)
                .reduce(.visibleRefresh) { $0.merged(with: $1) }
        }
    }
}

private extension AccessibilityPredicate.Change {
    var observationScope: HeistSemanticObservationScope {
        switch self {
        case .screen(let state):
            return state?.observationScope ?? .visibleRefresh
        case .elements:
            return .visibleRefresh
        case .appeared:
            return .fullSemanticExplore
        case .disappeared(let predicate):
            return .revealTargets([.predicate(predicate)])
        case .updated(let update):
            guard let predicate = update.element else { return .visibleRefresh }
            return .revealTargets([.predicate(predicate)])
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
