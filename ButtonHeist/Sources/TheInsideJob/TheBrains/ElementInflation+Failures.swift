#if canImport(UIKit) && DEBUG
import UIKit

import TheScore

extension ElementInflation {

    internal enum ElementInflationFailureStep: String {
        case notFound
        case ambiguous
        case noRevealPath
        case staleRefresh
        case cancelled
        case geometryNotActionable
    }

    internal struct ElementInflationFailure: Error {
        internal let failedStep: ElementInflationFailureStep
        internal let failureKind: TheSafecracker.FailureKind
        internal let message: String

        internal static func notFound(_ message: String) -> ElementInflationFailure {
            .init(.notFound, failureKind: .targetUnavailable, message: message)
        }

        internal static func ambiguous(_ message: String) -> ElementInflationFailure {
            .init(.ambiguous, failureKind: .targetUnavailable, message: message)
        }

        internal static func noRevealPath(_ message: String) -> ElementInflationFailure {
            .init(.noRevealPath, failureKind: .actionFailed, message: message)
        }

        internal static func staleRefresh(
            _ message: String,
            failureKind: TheSafecracker.FailureKind = .actionFailed
        ) -> ElementInflationFailure {
            .init(.staleRefresh, failureKind: failureKind, message: message)
        }

        internal static func cancelled(_ message: String) -> ElementInflationFailure {
            .init(.cancelled, failureKind: .actionFailed, message: message)
        }

        internal static func geometryNotActionable(
            _ message: String,
            failureKind: TheSafecracker.FailureKind = .actionFailed
        ) -> ElementInflationFailure {
            .init(.geometryNotActionable, failureKind: failureKind, message: message)
        }

        internal func actionDispatchOutcome(commandMethod: ActionMethod) -> TheSafecracker.ActionDispatchOutcome {
            .failure(commandMethod, message: message, failureKind: failureKind)
        }

        private init(
            _ step: ElementInflationFailureStep,
            failureKind: TheSafecracker.FailureKind,
            message: String
        ) {
            failedStep = step
            self.failureKind = failureKind
            self.message = message.contains("[\(step.rawValue)]")
                ? message
                : "element inflation failed [\(step.rawValue)]: \(message)"
        }
    }

    internal func retryExhaustedFailure(
        reason: RetryReason,
        maxAttempts: Int
    ) -> ElementInflationFailure {
        let message = "inflation exhausted \(maxAttempts) retry attempts after \(reason.failureDescription)"
        switch reason {
        case .objectDeallocated, .staleTarget:
            return .staleRefresh(message, failureKind: .targetUnavailable)
        case .activationPointOffscreen:
            return .geometryNotActionable(message)
        }
    }

    internal func noScrollViewFailure(
        for liveTarget: TheStash.LiveActionTarget,
        description: String,
        method: ActionMethod
    ) -> ElementInflationFailure {
        if ScreenMetrics.current.bounds.intersects(liveTarget.frame) {
            return .geometryNotActionable(
                "target \(description) has an activation point outside the screen; "
                    + Self.liveGeometrySummary(liveTarget)
            )
        }
        return .noRevealPath(
            "target \(description) has no live scrollable ancestor to make activation point actionable"
        )
    }
}

#endif // canImport(UIKit) && DEBUG
