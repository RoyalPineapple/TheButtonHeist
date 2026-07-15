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

    internal struct KnownTargetRevealRequest {
        internal let heistId: HeistId
        internal let deadline: SemanticObservationDeadline
    }

    internal typealias MoveViewport = @MainActor (
        Navigation.ViewportMovementIntent
    ) async -> Navigation.ViewportTransition

    internal struct Exploration {
        internal var discoverTarget: @MainActor (ResolvedAccessibilityTarget) async -> Navigation.ExploredScreen?
        internal var revealKnownTarget: @MainActor (KnownTargetRevealRequest) async -> Navigation.ExploredScreen?
        internal var moveViewport: MoveViewport
    }

    internal struct GeometryEnvironment {
        internal let now: @MainActor () -> CFAbsoluteTime
        internal let awaitFrame: @MainActor () async -> Void
    }

    internal struct CommittedElementTarget {
        private let sourceTarget: ResolvedAccessibilityTarget
        private let resolvedHeistId: HeistId
        private let resolution: ActionSubjectResolution

        internal init(_ inflatedTarget: InflatedElementTarget) {
            sourceTarget = inflatedTarget.target
            resolvedHeistId = inflatedTarget.treeElement.heistId
            resolution = inflatedTarget.resolution
        }

        internal var target: ResolvedAccessibilityTarget { sourceTarget }
        internal var heistId: HeistId { resolvedHeistId }
        internal var subjectResolution: ActionSubjectResolution { resolution }
    }

    internal let stash: TheStash
    internal let safecracker: TheSafecracker
    internal let tripwire: TheTripwire
    internal var exploration: Exploration
    internal var geometryEnvironment: GeometryEnvironment

    internal static let comfortMarginFraction: CGFloat = 1.0 / 6.0
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
        geometryEnvironment = GeometryEnvironment(
            now: CFAbsoluteTimeGetCurrent,
            awaitFrame: { await tripwire.yieldRealFrames(1) }
        )
    }

    internal func inflate(
        for target: ResolvedAccessibilityTarget,
        method: ActionMethod,
        activationPointPolicy: ActivationPointPolicy = .requireOnscreen
    ) async -> ElementInflationResult {
        guard !Task.isCancelled else {
            return .failed(.cancelled("element inflation was cancelled before resolution"))
        }
        let validatedTarget: ResolvedAccessibilityTarget
        do {
            validatedTarget = try target.validatedForElementAction()
        } catch {
            return .failed(.targetResolution(error))
        }
        return await runInflation(
            for: validatedTarget,
            method: method,
            activationPointPolicy: activationPointPolicy
        )
    }

    private func runInflation(
        for target: ResolvedAccessibilityTarget,
        method: ActionMethod,
        activationPointPolicy: ActivationPointPolicy,
        initialState: State = .resolving
    ) async -> ElementInflationResult {
        var state = initialState
        let revealTransaction = RevealTransaction()
        revealTransaction.captureScrollableHierarchy(in: stash)

        while true {
            switch state {
            case .resolving:
                let nextState: State
                switch await findTargetInTree(target) {
                case .success(.visible(let treeElement, let resolution)):
                    nextState = .refreshing(
                        target: target,
                        treeElement: treeElement,
                        deadline: handoffDeadline(for: treeElement),
                        resolution: resolution
                    )
                case .success(.known(let treeElement, let resolution)):
                    nextState = .revealing(
                        target: target,
                        treeElement: treeElement,
                        deadline: handoffDeadline(for: treeElement),
                        resolution: resolution
                    )
                case .failure(let failure):
                    nextState = .failed(failure)
                }
                if let failure = transition(&state, to: nextState) {
                    await revealTransaction.rollBack(using: exploration.moveViewport)
                    return .failed(failure)
                }

            case .revealing(let target, let treeElement, let deadline, let resolution):
                let nextState = await stateAfterReveal(
                    treeElement,
                    target: target,
                    deadline: deadline,
                    resolution: resolution,
                    transaction: revealTransaction
                )
                if let failure = transition(&state, to: nextState) {
                    await revealTransaction.rollBack(using: exploration.moveViewport)
                    return .failed(failure)
                }

            case .refreshing(let target, let treeElement, let deadline, let resolution):
                let nextState = await stateAfterRefresh(
                    target: target,
                    treeElement: treeElement,
                    resolution: resolution,
                    method: method,
                    activationPointPolicy: activationPointPolicy,
                    deadline: deadline
                )
                if let failure = transition(&state, to: nextState) {
                    await revealTransaction.rollBack(using: exploration.moveViewport)
                    return .failed(failure)
                }

            case .placing(let inflatedTarget):
                let nextState = await stateAfterPlacement(
                    inflatedTarget,
                    method: method,
                    transaction: revealTransaction
                )
                if let failure = transition(&state, to: nextState) {
                    await revealTransaction.rollBack(using: exploration.moveViewport)
                    return .failed(failure)
                }

            case .inflated(let result):
                revealTransaction.commit()
                return .inflated(result)

            case .failed(let failure):
                await revealTransaction.rollBack(using: exploration.moveViewport)
                return .failed(failure)
            }
        }
    }

    internal func refreshCommittedTarget(
        _ target: CommittedElementTarget,
        method: ActionMethod
    ) async -> ElementInflationResult {
        guard !Task.isCancelled else {
            return .failed(.cancelled("element inflation was cancelled before committed target refresh"))
        }
        stash.refreshLiveCapture()
        guard let treeElement = stash.interfaceElement(heistId: target.heistId) else {
            return .failed(.staleRefresh(
                "committed target \(target.heistId) disappeared before \(method.rawValue) refresh",
                failureKind: .targetUnavailable
            ))
        }
        let deadline = handoffDeadline(for: treeElement)
        let initialState: State = stash.liveContains(heistId: target.heistId)
            ? .refreshing(
                target: target.target,
                treeElement: treeElement,
                deadline: deadline,
                resolution: target.subjectResolution
            )
            : .revealing(
                target: target.target,
                treeElement: treeElement,
                deadline: deadline,
                resolution: target.subjectResolution
            )
        return await runInflation(
            for: target.target,
            method: method,
            activationPointPolicy: .requireOnscreen,
            initialState: initialState
        )
    }

    internal static func handoffTickCount(
        for treeElement: InterfaceTree.Element,
        in tree: InterfaceTree
    ) -> Int {
        var visited = Set<TreePath>()
        var containerPath = treeElement.scrollMembership?.containerPath
        while let path = containerPath, visited.insert(path).inserted {
            containerPath = tree.containers[path]?.scrollMembership?.containerPath
        }
        return max(2, visited.count + 1)
    }

    internal func handoffDeadline(
        for treeElement: InterfaceTree.Element
    ) -> SemanticObservationDeadline {
        let tickCount = Self.handoffTickCount(for: treeElement, in: stash.interfaceTree)
        return SemanticObservationDeadline(
            start: geometryEnvironment.now(),
            timeoutSeconds: Double(tickCount) * SemanticObservationTiming.defaultTimeout
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
}

extension ElementInflation.InflatedElementTarget {
    internal var committedTarget: ElementInflation.CommittedElementTarget {
        ElementInflation.CommittedElementTarget(self)
    }
}

#endif // canImport(UIKit) && DEBUG
