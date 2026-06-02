#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

struct HeistPredicateObservation {
    let state: PostActionObservation.BeforeState
    let delta: AccessibilityTrace.Delta?
    let summary: String
}

enum HeistPredicateObservationScope: Equatable {
    case visibleRefresh
    case revealTargets([ElementTarget])
    case fullSemanticExplore

    func merged(with other: HeistPredicateObservationScope) -> HeistPredicateObservationScope {
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

extension TheBrains {
    func observeHeistPredicate(
        scope: HeistPredicateObservationScope,
        baseline: PostActionObservation.BeforeState?,
        timeout: Double?
    ) async -> HeistPredicateObservation? {
        let baseline = baseline ?? postActionObservation.captureSemanticState()
        guard var current = await settledVisibleState(after: baseline, timeout: timeout) else {
            return nil
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
            } else if !targets.isEmpty, let refreshed = await settledVisibleState(after: current, timeout: timeout) {
                current = refreshed
            }
        }

        let trace = postActionObservation.makeClassifiedAccessibilityTrace(after: current, parent: baseline)
        return HeistPredicateObservation(
            state: current,
            delta: trace.endpointDeltaProjection,
            summary: heistObservationSummary(current)
        )
    }

    private func settledVisibleState(
        after baseline: PostActionObservation.BeforeState,
        timeout: Double?
    ) async -> PostActionObservation.BeforeState? {
        let settleSession = SettleSession.live(
            stash: stash,
            tripwire: tripwire,
            timeoutMs: heistObservationTimeoutMs(timeout)
        )
        let settle = await settleSession.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: baseline.tripwireSignal
        )
        guard settle.outcome.didSettleCleanly else { return nil }
        if let screen = settle.finalScreen {
            stash.commitSettledVisibleObservation(screen)
        } else if stash.commitVisibleObservation() == nil {
            return nil
        }
        return await postActionObservation.semanticStateAfterVisibleRefresh(baseline: baseline)
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

    private func heistObservationTimeoutMs(_ timeout: Double?) -> Int {
        guard let timeout, timeout > 0 else { return SettleSession.defaultTimeoutMs }
        return max(1, Int(min(timeout, 1.0) * 1000))
    }

    private func heistObservationSummary(_ state: PostActionObservation.BeforeState) -> String {
        var parts = ["known: \(state.interface.projectedElements.count) elements"]
        if let screenId = state.screenId {
            parts.insert("screen: \(screenId)", at: 0)
        }
        return parts.joined(separator: "; ")
    }
}

extension ConditionalStep {
    var observationScope: HeistPredicateObservationScope {
        cases
            .map(\.predicate.observationScope)
            .reduce(.visibleRefresh) { $0.merged(with: $1) }
    }
}

extension WaitForCasesStep {
    var observationScope: HeistPredicateObservationScope {
        cases
            .map(\.predicate.observationScope)
            .reduce(.visibleRefresh) { $0.merged(with: $1) }
    }
}

private extension AccessibilityPredicate {
    var observationScope: HeistPredicateObservationScope {
        switch self {
        case .state(let state):
            return state.observationScope
        case .changed(let change):
            return change.observationScope
        }
    }
}

private extension AccessibilityPredicate.State {
    var observationScope: HeistPredicateObservationScope {
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
    var observationScope: HeistPredicateObservationScope {
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
