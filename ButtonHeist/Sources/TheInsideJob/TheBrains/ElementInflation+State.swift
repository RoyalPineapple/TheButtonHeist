#if canImport(UIKit) && DEBUG
import UIKit

import ButtonHeistSupport
import TheScore
import ThePlans

private enum RevealTransactionPhase {
    case active
    case committed
    case rolledBack
}

private struct RevealMovement {
    let target: Navigation.ScrollableTarget
    let visualOrigin: CGPoint
}

extension ElementInflation {

    @MainActor
    internal final class RevealTransaction {
        private unowned let vault: TheVault
        private var movements: [ObjectIdentifier: RevealMovement] = [:]
        private var movementOrder: [ObjectIdentifier] = []
        private var phase = RevealTransactionPhase.active

        internal init(vault: TheVault) {
            self.vault = vault
        }

        internal func captureScrollableHierarchy() {
            vault.scrollableContainerViewsByPath.values.forEach(recordHierarchy(from:))
        }

        internal func record(_ scrollView: UIScrollView) {
            guard phase == .active else { return }
            let identifier = ObjectIdentifier(scrollView)
            guard movements[identifier] == nil else { return }
            guard let target = Navigation.ScrollableTarget.programmatic(scrollView, in: vault) else { return }
            movements[identifier] = RevealMovement(
                target: target,
                visualOrigin: Navigation.visualOrigin(in: scrollView)
            )
            movementOrder.append(identifier)
        }

        internal func commit() {
            guard phase == .active else { return }
            phase = .committed
        }

        internal var didMove: Bool {
            movements.values.contains { movement in
                movement.target.dispatchOnFreshScrollView(in: vault) { scrollView in
                    Navigation.visualOrigin(in: scrollView) != movement.visualOrigin
                } ?? false
            }
        }

        internal func rollBack(using moveViewport: MoveViewport) async {
            guard phase == .active else { return }
            phase = .rolledBack
            for identifier in movementOrder.reversed() {
                guard let movement = movements[identifier] else { continue }
                guard let currentOrigin = movement.target.dispatchOnFreshScrollView(
                    in: vault,
                    operation: Navigation.visualOrigin
                ) else { continue }
                guard currentOrigin != movement.visualOrigin else { continue }
                _ = await moveViewport(.restoreVisualOrigin(
                    movement.visualOrigin,
                    in: movement.target
                ))
            }
        }

        private func recordHierarchy(from view: UIView) {
            if let scrollView = view as? UIScrollView {
                record(scrollView)
            }
            view.subviews.forEach(recordHierarchy(from:))
        }
    }

    internal struct InflatedElementTarget {
        internal let target: ResolvedAccessibilityTarget
        internal let treeElement: InterfaceTree.Element
        internal let liveTarget: TheVault.LiveActionTarget
        internal let deadline: SemanticObservationDeadline
        internal let resolution: ActionSubjectResolution

        internal func replacingLiveTarget(_ liveTarget: TheVault.LiveActionTarget) -> Self {
            Self(
                target: target,
                treeElement: liveTarget.treeElement,
                liveTarget: liveTarget,
                deadline: deadline,
                resolution: resolution
            )
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
        case visible(InterfaceTree.Element, ActionSubjectResolution)
        case known(InterfaceTree.Element, ActionSubjectResolution)
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

        internal var adjustment: ActionSubjectResolution.Adjustment {
            switch self {
            case .objectDeallocated:
                return .objectDeallocationRefresh
            case .staleTarget:
                return .staleTargetRefresh
            }
        }
    }

    internal enum State: CustomStringConvertible {
        case resolving
        case revealing(
            target: ResolvedAccessibilityTarget,
            treeElement: InterfaceTree.Element,
            deadline: SemanticObservationDeadline,
            resolution: ActionSubjectResolution
        )
        case refreshing(
            target: ResolvedAccessibilityTarget,
            treeElement: InterfaceTree.Element,
            deadline: SemanticObservationDeadline,
            resolution: ActionSubjectResolution
        )
        case placing(InflatedElementTarget)
        case inflated(InflatedElementTarget)
        case failed(ElementInflationFailure)

        internal var isCancellationFailure: Bool {
            guard case .failed(let failure) = self,
                  case .cancelled = failure.failedStep
            else { return false }
            return true
        }

        internal var description: String {
            switch self {
            case .resolving:
                return "resolving"
            case .revealing(_, let treeElement, _, _):
                return "revealing(element: \(treeElement.heistId))"
            case .refreshing(_, let treeElement, _, _):
                return "refreshing(element: \(treeElement.heistId))"
            case .placing(let inflatedTarget):
                return "placing(element: \(inflatedTarget.treeElement.heistId))"
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
        case treeElement(InterfaceTree.Element, ActionSubjectResolution)
        case inflated(InflatedElementTarget)
        case failure(ElementInflationFailure)
        case timedOut
        case cancelled
    }
}

extension ElementInflation.InflatedElementTarget {
    internal func adding(
        _ adjustment: ActionSubjectResolution.Adjustment
    ) -> ElementInflation.InflatedElementTarget {
        ElementInflation.InflatedElementTarget(
            target: target,
            treeElement: treeElement,
            liveTarget: liveTarget,
            deadline: deadline,
            resolution: resolution.adding(adjustment)
        )
    }

    @MainActor
    internal func subjectEvidence(source: ActionSubjectEvidence.Source) -> ActionSubjectEvidence {
        ActionSubjectEvidence(
            source: source,
            target: target,
            element: TheVault.WireConversion.convert(treeElement.element),
            resolution: resolution
        )
    }
}

extension ActionSubjectResolution {
    internal func adding(_ adjustment: Adjustment) -> ActionSubjectResolution {
        ActionSubjectResolution(
            origin: origin,
            adjustments: adjustments.union([adjustment])
        )
    }
}

#endif // canImport(UIKit) && DEBUG
