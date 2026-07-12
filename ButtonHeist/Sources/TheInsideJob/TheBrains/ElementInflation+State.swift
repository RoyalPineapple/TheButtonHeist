#if canImport(UIKit) && DEBUG
import UIKit

import TheScore
import ThePlans

extension ElementInflation {

    internal struct InflatedElementTarget {
        internal let target: AccessibilityTarget
        internal let screenElement: TheStash.ScreenElement
        internal let liveTarget: TheStash.LiveActionTarget

        internal init(
            target: AccessibilityTarget,
            screenElement: TheStash.ScreenElement,
            liveTarget: TheStash.LiveActionTarget
        ) {
            self.target = target
            self.screenElement = screenElement
            self.liveTarget = liveTarget
        }
    }

    internal enum ElementInflationResult {
        case inflated(InflatedElementTarget)
        case failed(ElementInflationFailure)
    }

    internal enum ActivationPointPolicy {
        case requireOnscreen
        case liveObjectOnly
    }

    internal enum TreeTargetMatch {
        case visible(TheStash.ScreenElement)
        case known(TheStash.ScreenElement)
    }

    internal enum RetryReason: String, CustomStringConvertible, Sendable, Equatable {
        case objectDeallocated
        case staleTarget
        case activationPointOffscreen

        internal var description: String {
            rawValue
        }

        internal var failureDescription: String {
            switch self {
            case .objectDeallocated:
                return "the live object was deallocated"
            case .staleTarget:
                return "the live target no longer matched"
            case .activationPointOffscreen:
                return "the activation point stayed off-screen"
            }
        }
    }

    internal enum ResolutionPass: Sendable, Equatable {
        case initial
        case afterRetry(attempt: Int, reason: RetryReason)

        internal var attempt: Int {
            switch self {
            case .initial:
                return 0
            case .afterRetry(let attempt, _):
                return attempt
            }
        }

        internal var allowsKnownFallback: Bool {
            switch self {
            case .initial, .afterRetry(_, .objectDeallocated):
                return true
            case .afterRetry(_, .staleTarget), .afterRetry(_, .activationPointOffscreen):
                return false
            }
        }
    }

    internal enum State: CustomStringConvertible {
        case resolving(ResolutionPass)
        case revealing(treeElement: TheStash.ScreenElement, attempt: Int)
        case refreshing(
            target: AccessibilityTarget,
            screenElement: TheStash.ScreenElement,
            attempt: Int,
            didReveal: Bool
        )
        case placing(inflatedTarget: InflatedElementTarget, attempt: Int, didReveal: Bool)
        case retrying(failedAttempt: Int, reason: RetryReason)
        case inflated(InflatedElementTarget)
        case failed(ElementInflationFailure)

        internal var description: String {
            switch self {
            case .resolving:
                return "resolving"
            case .revealing(let treeElement, let attempt):
                return "revealing(element: \(treeElement.heistId), attempt: \(attempt))"
            case .refreshing(_, let screenElement, let attempt, let didReveal):
                return "refreshing(element: \(screenElement.heistId), didReveal: \(didReveal), attempt: \(attempt))"
            case .placing(let inflatedTarget, let attempt, let didReveal):
                return "placing(element: \(inflatedTarget.screenElement.heistId), didReveal: \(didReveal), attempt: \(attempt))"
            case .retrying(let failedAttempt, let reason):
                return "retrying(failedAttempt: \(failedAttempt), reason: \(reason.description))"
            case .inflated(let inflatedTarget):
                return "inflated(element: \(inflatedTarget.screenElement.heistId))"
            case .failed(let failure):
                return "failed(step: \(failure.failedStep.rawValue))"
            }
        }
    }

    internal enum FreshElementTargetResolution {
        case success(InflatedElementTarget)
        case retry(RetryReason)
        case failure(ElementInflationFailure)
    }

    internal enum TargetRefreshGraceTerminal {
        case screenElement(TheStash.ScreenElement, didReveal: Bool)
        case inflated(InflatedElementTarget)
        case failure(ElementInflationFailure)
        case timedOut
        case cancelled
    }
}

extension ElementInflation.InflatedElementTarget {
    @MainActor
    internal func subjectEvidence(source: ActionSubjectEvidence.Source) -> ActionSubjectEvidence {
        ActionSubjectEvidence(
            source: source,
            target: target,
            element: TheStash.WireConversion.convert(screenElement.element)
        )
    }
}

#endif // canImport(UIKit) && DEBUG
