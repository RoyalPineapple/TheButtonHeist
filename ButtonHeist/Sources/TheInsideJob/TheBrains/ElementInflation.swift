#if canImport(UIKit) && DEBUG
import UIKit

import ButtonHeistSupport
import TheScore
import ThePlans

/// Converts a semantic target into a fresh live target that can receive the
/// requested accessibility action.
///
/// Invariant: the tree is the map; viewport movement updates the map; actions
/// resolve one map entry to a fresh live object with an on-screen activation point.
///
/// It owns reveal, bounded viewport movement, and live geometry acquisition.
/// It does not choose matchers, dispatch actions, or evaluate post-action
/// expectations.
@MainActor
internal final class ElementInflation {

    internal struct Exploration {
        internal var discoverTarget: @MainActor (AccessibilityTarget) async -> Navigation.ExploredScreen?
        internal var revealKnownTarget: @MainActor (HeistId) async -> Navigation.ExploredScreen?
    }

    internal let stash: TheStash
    internal let safecracker: TheSafecracker
    internal let tripwire: TheTripwire
    internal var exploration: Exploration

    internal static let comfortMarginFraction: CGFloat = 1.0 / 6.0
    internal static let operationTimeout = SemanticObservationTiming.defaultTimeout * 2
    internal static var postScrollLayoutFrames: Int { Navigation.postScrollLayoutFrames }

    internal init(
        stash: TheStash,
        safecracker: TheSafecracker,
        tripwire: TheTripwire,
        exploration: Exploration
    ) {
        self.stash = stash
        self.safecracker = safecracker
        self.tripwire = tripwire
        self.exploration = exploration
    }

    internal func inflate(
        for target: AccessibilityTarget,
        method: ActionMethod,
        deallocatedBoundary: String,
        activationPointPolicy: ActivationPointPolicy = .requireOnscreen
    ) async -> ElementInflationResult {
        guard !Task.isCancelled else {
            return .failed(.cancelled("element inflation was cancelled before resolution"))
        }
        let deadline = SemanticObservationDeadline(
            start: CFAbsoluteTimeGetCurrent(),
            timeoutSeconds: Self.operationTimeout
        )
        return await inflateBeforeDeadline(
            for: target,
            method: method,
            deallocatedBoundary: deallocatedBoundary,
            activationPointPolicy: activationPointPolicy,
            deadline: deadline
        )
    }

    private func inflateBeforeDeadline(
        for target: AccessibilityTarget,
        method: ActionMethod,
        deallocatedBoundary: String,
        activationPointPolicy: ActivationPointPolicy,
        deadline: SemanticObservationDeadline
    ) async -> ElementInflationResult {
        let resolvedTarget: AccessibilityTarget
        do {
            resolvedTarget = try target.validatedForElementAction()
        } catch {
            return .failed(.targetResolution(error))
        }
        var state: State = .resolving

        while true {
            switch state {
            case .resolving:
                let nextState: State = switch await findTargetInTree(resolvedTarget) {
                case .success(.visible(let treeElement)):
                    .refreshing(
                        target: resolvedTarget,
                        treeElement: treeElement,
                        didReveal: false
                    )
                case .success(.known(let treeElement)):
                    .revealing(treeElement: treeElement)
                case .failure(let failure):
                    .failed(failure)
                }
                if let failure = transition(&state, to: nextState) {
                    return .failed(failure)
                }

            case .revealing(let treeElement):
                let nextState = await stateAfterReveal(
                    treeElement,
                    target: resolvedTarget,
                    deadline: deadline
                )
                if let failure = transition(&state, to: nextState) {
                    return .failed(failure)
                }

            case .refreshing(let target, let treeElement, let didReveal):
                let nextState = await stateAfterRefresh(
                    target: target,
                    treeElement: treeElement,
                    didReveal: didReveal,
                    method: method,
                    deallocatedBoundary: deallocatedBoundary,
                    activationPointPolicy: activationPointPolicy,
                    deadline: deadline
                )
                if let failure = transition(&state, to: nextState) {
                    return .failed(failure)
                }

            case .placing(let inflatedTarget, let didReveal):
                let nextState = await stateAfterPlacement(
                    inflatedTarget,
                    didReveal: didReveal,
                    method: method,
                    deadline: deadline
                )
                if let failure = transition(&state, to: nextState) {
                    return .failed(failure)
                }

            case .inflated(let result):
                return .inflated(result)

            case .failed(let failure):
                return .failed(failure)
            }
        }
    }

    internal func inflateAfterActivationRefresh(
        for target: AccessibilityTarget
    ) async -> ElementInflationResult {
        refreshLiveCaptureForActivation()
        return await inflate(
            for: target,
            method: .activate,
            deallocatedBoundary: "activation refresh"
        )
    }

    private func transition(
        _ state: inout State,
        to proposedState: State
    ) -> ElementInflationFailure? {
        let nextState: State
        let event: StateEvent
        if proposedState.isCancellationFailure {
            nextState = proposedState
            event = .cancelled
        } else if Task.isCancelled {
            nextState = .failed(.cancelled(
                "element inflation was cancelled while \(state.phase.rawValue)"
            ))
            event = .cancelled
        } else {
            nextState = proposedState
            event = .advance(to: nextState.phase)
        }

        switch StateMachine().advance(state.phase, with: event) {
        case .rejected(let rejection, _):
            return .invalidTransition(rejection)
        case .changed(let expectedPhase, _):
            guard expectedPhase == nextState.phase else {
                return .invalidTransition(.init(state: state.phase, event: event))
            }

            let currentDescription = state.description
            let nextDescription = nextState.description
            insideJobLogger.debug(
                "inflation: \(currentDescription, privacy: .public) -> \(nextDescription, privacy: .public)"
            )
            state = nextState
            return nil
        }
    }

    private func refreshLiveCaptureForActivation() {
        stash.refreshLiveCapture()
    }
}

#endif // canImport(UIKit) && DEBUG
