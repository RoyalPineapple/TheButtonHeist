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
    let scrollView: UIScrollView
    let visualOrigin: CGPoint
}

extension ElementInflation {

    @MainActor
    internal final class RevealTransaction {
        private var movements: [ObjectIdentifier: RevealMovement] = [:]
        private var movementOrder: [ObjectIdentifier] = []
        private var phase = RevealTransactionPhase.active

        internal func captureScrollableHierarchy(in stash: TheStash) {
            stash.scrollableContainerViewsByPath.values.forEach(recordHierarchy(from:))
        }

        internal func record(_ scrollView: UIScrollView) {
            guard phase == .active else { return }
            let identifier = ObjectIdentifier(scrollView)
            guard movements[identifier] == nil else { return }
            movements[identifier] = RevealMovement(
                scrollView: scrollView,
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
                Navigation.visualOrigin(in: movement.scrollView) != movement.visualOrigin
            }
        }

        internal func rollBack() {
            guard phase == .active else { return }
            phase = .rolledBack
            movementOrder.reversed().forEach { identifier in
                guard let movement = movements[identifier] else { return }
                let currentOrigin = Navigation.visualOrigin(in: movement.scrollView)
                guard currentOrigin != movement.visualOrigin else { return }
                Navigation.restoreVisualOrigin(movement.visualOrigin, in: movement.scrollView)
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
        internal let liveTarget: TheStash.LiveActionTarget
        internal let deadline: SemanticObservationDeadline
        internal let resolution: ActionSubjectResolution

        internal init(
            target: ResolvedAccessibilityTarget,
            treeElement: InterfaceTree.Element,
            liveTarget: TheStash.LiveActionTarget,
            deadline: SemanticObservationDeadline,
            resolution: ActionSubjectResolution
        ) {
            self.target = target
            self.treeElement = treeElement
            self.liveTarget = liveTarget
            self.deadline = deadline
            self.resolution = resolution
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

        internal var phase: StatePhase {
            switch self {
            case .resolving:
                return .resolving
            case .revealing:
                return .revealing
            case .refreshing:
                return .refreshing
            case .placing:
                return .placing
            case .inflated:
                return .inflated
            case .failed:
                return .failed
            }
        }

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

    internal enum StatePhase: String, CaseIterable, Equatable, Sendable {
        case resolving
        case revealing
        case refreshing
        case placing
        case inflated
        case failed
    }

    internal enum StateEvent: Equatable, Sendable {
        case advance(to: StatePhase)
        case cancelled
    }

    internal enum StateEffect: Equatable, Sendable {}

    internal struct StateTransitionRejection: Error, Equatable, Sendable, CustomStringConvertible {
        internal let state: StatePhase
        internal let event: StateEvent

        internal var description: String {
            switch event {
            case .advance(let next):
                return "cannot transition from \(state.rawValue) to \(next.rawValue)"
            case .cancelled:
                return "cannot cancel terminal \(state.rawValue) state"
            }
        }
    }

    internal struct StateMachine: SimpleStateMachine {
        internal func advance(
            _ state: StatePhase,
            with event: StateEvent
        ) -> StateChange<StatePhase, StateEffect, StateTransitionRejection> {
            switch event {
            case .cancelled:
                switch state {
                case .resolving, .revealing, .refreshing, .placing:
                    return .changed(to: .failed)
                case .inflated, .failed:
                    return .rejected(.init(state: state, event: event), stayingIn: state)
                }

            case .advance(let next):
                switch (state, next) {
                case (.resolving, .revealing),
                     (.resolving, .refreshing),
                     (.resolving, .failed),
                     (.revealing, .refreshing),
                     (.revealing, .failed),
                     (.refreshing, .placing),
                     (.refreshing, .inflated),
                     (.refreshing, .failed),
                     (.placing, .inflated),
                     (.placing, .failed):
                    return .changed(to: next)

                case (.resolving, .resolving),
                     (.resolving, .placing),
                     (.resolving, .inflated),
                     (.revealing, .resolving),
                     (.revealing, .revealing),
                     (.revealing, .placing),
                     (.revealing, .inflated),
                     (.refreshing, .resolving),
                     (.refreshing, .revealing),
                     (.refreshing, .refreshing),
                     (.placing, .resolving),
                     (.placing, .revealing),
                     (.placing, .refreshing),
                     (.placing, .placing),
                     (.inflated, _),
                     (.failed, _):
                    return .rejected(.init(state: state, event: event), stayingIn: state)
                }
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
            element: TheStash.WireConversion.convert(treeElement.element),
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
