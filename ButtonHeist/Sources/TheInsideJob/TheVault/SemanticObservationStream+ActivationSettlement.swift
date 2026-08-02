#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

@MainActor
extension Observation.Stream {
    internal struct RefusedActivationBoundary: Sendable, Equatable {
        internal let snapshot: Observation.Snapshot?
        internal let historyIndex: Int
    }

    internal enum RefusedActivationSettlement: Sendable, Equatable {
        case effectObserved
        case quiescent
        case unavailable
    }

    internal struct RefusedActivationQuiescence: Sendable {
        internal enum Reduction: Sendable, Equatable {
            case awaiting
            case effectObserved
            case quiescent
        }

        private static let requiredStableCaptures = 2
        private var previous: Observation.Snapshot?
        private var stableCaptureCount = 0

        internal init(boundary: RefusedActivationBoundary) {
            previous = boundary.snapshot
        }

        @MainActor
        internal mutating func reduce(snapshot: Observation.Snapshot) -> Reduction {
            guard let previous,
                  previous.hasSameObservedState(
                      as: snapshot,
                      geometryTolerance: CoarseFrameComparison.currentGeometryTolerance
                  )
            else {
                return .effectObserved
            }
            self.previous = snapshot
            stableCaptureCount += 1
            return stableCaptureCount >= Self.requiredStableCaptures
                ? .quiescent
                : .awaiting
        }
    }

    /// Captures the last admitted state immediately before accessibility
    /// activation. Later samples are judged only against this boundary.
    internal func refusedActivationBoundary() -> RefusedActivationBoundary {
        RefusedActivationBoundary(
            snapshot: vault.state.currentSnapshot,
            historyIndex: vault.state.history.endIndex
        )
    }

    /// Waits for observed evidence after a refused accessibility activation. A
    /// semantic or geometry change suppresses activation-point dispatch. A
    /// notification alone does not. Dispatch is allowed only after the named
    /// two consecutive captures observe the same state.
    internal func settleRefusedActivation(
        after boundary: RefusedActivationBoundary,
        deadline: SemanticObservationDeadline
    ) async -> RefusedActivationSettlement {
        guard boundary.snapshot != nil else { return .unavailable }
        var historyIndex = boundary.historyIndex
        var quiescence = RefusedActivationQuiescence(boundary: boundary)

        while deadline.hasTimeRemaining(at: RuntimeElapsed.now) {
            guard let current = await nextObservation(
                scope: .visible,
                after: historyIndex,
                boundary: .externalDeadline(deadline)
            ) else { return .unavailable }
            historyIndex = vault.state.history.endIndex
            switch quiescence.reduce(snapshot: current.snapshot) {
            case .awaiting:
                continue
            case .effectObserved:
                return .effectObserved
            case .quiescent:
                return .quiescent
            }
        }
        return .unavailable
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
