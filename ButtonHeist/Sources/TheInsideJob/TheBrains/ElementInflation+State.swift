#if canImport(UIKit) && DEBUG
import UIKit

import TheScore
import ThePlans

extension ElementInflation {

    internal struct InflatedElementTarget {
        internal let target: AccessibilityTarget
        internal let treeElement: InterfaceTree.Element
        internal let liveTarget: TheStash.LiveActionTarget

        internal init(
            target: AccessibilityTarget,
            treeElement: InterfaceTree.Element,
            liveTarget: TheStash.LiveActionTarget
        ) {
            self.target = target
            self.treeElement = treeElement
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
        case visible(InterfaceTree.Element)
        case known(InterfaceTree.Element)
    }

    internal enum RetryReason: String, CustomStringConvertible, Sendable, Equatable {
        case objectDeallocated
        case staleTarget

        internal var description: String {
            rawValue
        }

        internal var failureDescription: String {
            switch self {
            case .objectDeallocated:
                return "the live object was deallocated"
            case .staleTarget:
                return "the live target no longer matched"
            }
        }
    }

    internal enum State: CustomStringConvertible {
        case resolving
        case revealing(treeElement: InterfaceTree.Element)
        case refreshing(
            target: AccessibilityTarget,
            treeElement: InterfaceTree.Element,
            didReveal: Bool
        )
        case placing(inflatedTarget: InflatedElementTarget, didReveal: Bool)
        case inflated(InflatedElementTarget)
        case failed(ElementInflationFailure)

        internal var description: String {
            switch self {
            case .resolving:
                return "resolving"
            case .revealing(let treeElement):
                return "revealing(element: \(treeElement.heistId))"
            case .refreshing(_, let treeElement, let didReveal):
                return "refreshing(element: \(treeElement.heistId), didReveal: \(didReveal))"
            case .placing(let inflatedTarget, let didReveal):
                return "placing(element: \(inflatedTarget.treeElement.heistId), didReveal: \(didReveal))"
            case .inflated(let inflatedTarget):
                return "inflated(element: \(inflatedTarget.treeElement.heistId))"
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

    internal enum TargetRefreshTerminal {
        case treeElement(InterfaceTree.Element, didReveal: Bool)
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
            element: TheStash.WireConversion.convert(treeElement.element)
        )
    }
}

#endif // canImport(UIKit) && DEBUG
