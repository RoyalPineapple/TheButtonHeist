#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

@MainActor
extension Observation.Stream {
    internal struct RefusedActivationBoundary: Sendable, Equatable {
        internal let snapshot: Observation.Snapshot
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
        private let boundary: Observation.Snapshot
        private var candidate: Observation.Snapshot?
        private var stableCaptureCount = 0

        internal init(boundary: RefusedActivationBoundary) {
            self.boundary = boundary.snapshot
        }

        @MainActor
        internal mutating func reduce(snapshot: Observation.Snapshot) -> Reduction {
            if let candidate,
               candidate.hasSameObservedState(
                   as: snapshot,
                   geometryTolerance: CoarseFrameComparison.currentGeometryTolerance
               ) {
                stableCaptureCount += 1
            } else {
                candidate = snapshot
                stableCaptureCount = 1
            }
            guard stableCaptureCount >= Self.requiredStableCaptures else { return .awaiting }
            return boundary.hasSameObservedState(
                as: snapshot,
                geometryTolerance: CoarseFrameComparison.currentGeometryTolerance
            )
                ? .quiescent
                : .effectObserved
        }
    }

    /// Captures the last admitted state immediately before accessibility
    /// activation. Later samples need two post-action captures before being
    /// compared with this boundary.
    internal func refusedActivationBoundary() -> RefusedActivationBoundary? {
        guard let snapshot = vault.state.currentSnapshot else { return nil }
        return RefusedActivationBoundary(
            snapshot: snapshot,
            historyIndex: vault.state.history.endIndex
        )
    }

    /// Waits for observed evidence after a refused accessibility activation.
    /// Two post-action captures must agree before their state is compared with
    /// the boundary: a stable semantic or geometry change suppresses
    /// activation-point dispatch, while a notification alone does not.
    internal func settleRefusedActivation(
        after boundary: RefusedActivationBoundary,
        deadline: SemanticObservationDeadline
    ) async -> RefusedActivationSettlement {
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
