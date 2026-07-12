#if canImport(UIKit) && DEBUG
import UIKit

import ThePlans
import TheScore

extension ElementInflation {

    internal enum ElementActionTargetResolutionFailure: Error, Equatable, CustomStringConvertible {
        case containerTarget
        case unresolvedReference(HeistReferenceName)

        internal var description: String {
            switch self {
            case .containerTarget:
                return "container targets are not valid for element actions"
            case .unresolvedReference(let reference):
                return "target reference \(reference) was not resolved before element action dispatch"
            }
        }
    }

    internal enum ElementInflationFailureStep: String {
        case targetResolution
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
        internal let targetResolutionFailure: ElementActionTargetResolutionFailure?

        internal static func targetResolution(
            _ failure: ElementActionTargetResolutionFailure
        ) -> ElementInflationFailure {
            .init(
                .targetResolution,
                failureKind: .targetUnavailable,
                message: failure.description,
                targetResolutionFailure: failure
            )
        }

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
            message: String,
            targetResolutionFailure: ElementActionTargetResolutionFailure? = nil
        ) {
            failedStep = step
            self.failureKind = failureKind
            self.targetResolutionFailure = targetResolutionFailure
            self.message = message.contains("[\(step.rawValue)]")
                ? message
                : "element inflation failed [\(step.rawValue)]: \(message)"
        }
    }

    internal func staleRefreshFailure(reason: RetryReason) -> ElementInflationFailure {
        .staleRefresh(
            "target refresh reached the action deadline after \(reason.failureDescription)",
            failureKind: .targetUnavailable
        )
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

extension AccessibilityTarget {
    internal func validatedForElementAction() throws(
        ElementInflation.ElementActionTargetResolutionFailure
    ) -> AccessibilityTarget {
        switch self {
        case .predicate:
            return self
        case .container:
            throw .containerTarget
        case .ref(let reference):
            throw .unresolvedReference(reference)
        case .within(_, let target):
            _ = try target.validatedForElementAction()
            return self
        }
    }
}

#endif // canImport(UIKit) && DEBUG
