#if canImport(UIKit) && DEBUG
import UIKit

import TheScore
import ThePlans

extension ElementInflation {

    internal static var interactionComfortZone: CGRect {
        let bounds = ScreenMetrics.current.bounds
        return bounds.insetBy(dx: bounds.width * comfortMarginFraction, dy: bounds.height * comfortMarginFraction)
    }

    internal func stateAfterResolvedFreshTarget(
        _ inflatedTarget: InflatedElementTarget,
        didReveal: Bool,
        activationPointPolicy: ActivationPointPolicy,
        deadline: SemanticObservationDeadline
    ) async -> State {
        if activationPointPolicy == .liveObjectOnly {
            return await stateAfterStableLiveGeometry(
                inflatedTarget,
                requireOnscreenActivationPoint: false,
                deadline: deadline
            )
        }
        return .placing(inflatedTarget: inflatedTarget, didReveal: didReveal)
    }

    internal func stateAfterPlacement(
        _ inflatedTarget: InflatedElementTarget,
        didReveal: Bool,
        method: ActionMethod,
        deadline: SemanticObservationDeadline
    ) async -> State {
        let liveTarget = inflatedTarget.liveTarget
        if ScreenMetrics.current.bounds.contains(liveTarget.activationPoint) {
            return await stateAfterStableLiveGeometry(
                inflatedTarget,
                requireOnscreenActivationPoint: true,
                deadline: deadline
            )
        }
        if didReveal {
            return .failed(.geometryNotActionable(
                "target \(Navigation.ScrollTargetDescription(liveTarget.treeElement).description) "
                    + "did not become actionable after semantic reveal; "
                    + Self.liveGeometrySummary(liveTarget)
            ))
        }

        let treeElement = liveTarget.treeElement
        let description = Navigation.ScrollTargetDescription(treeElement).description
        let settledSequence = stash.latestSettledSemanticObservationEvent?.sequence
        let placement = await scrollActivationPointIntoBounds(
            liveTarget.activationPoint,
            in: stash.liveScrollView(for: treeElement),
            method: method,
            noScrollViewFailure: noScrollViewFailure(
                for: liveTarget,
                description: description,
                method: method
            ),
            unsafeProgrammaticScrollMessage: nil,
            scrollFailedMessage: "target \(description) activation point could not be brought on-screen"
        )
        switch placement {
        case .success(.alreadyInPosition):
            return await stateAfterStableLiveGeometry(
                inflatedTarget,
                requireOnscreenActivationPoint: true,
                deadline: deadline
            )
        case .success(.moved):
            switch await awaitLiveTargetRefresh(
                for: inflatedTarget.target,
                method: method,
                after: settledSequence,
                deadline: deadline
            ) {
            case .inflated(let refreshedTarget):
                return await stateAfterStableLiveGeometry(
                    refreshedTarget,
                    requireOnscreenActivationPoint: true,
                    deadline: deadline
                )
            case .failure(let failure):
                return .failed(failure)
            case .treeElement, .timedOut:
                return .failed(.geometryNotActionable(
                    "target \(description) did not become actionable before the action deadline"
                ))
            case .cancelled:
                return .failed(.cancelled(
                    "target \(description) placement wait was cancelled"
                ))
            }
        case .success(.unavailable):
            return .failed(.geometryNotActionable(
                "target \(description) activation point could not be brought on-screen"
            ))
        case .failure(let failure):
            return .failed(failure)
        }
    }

    internal func scrollActivationPointIntoBounds(
        _ activationPoint: CGPoint,
        in scrollView: UIScrollView?,
        method: ActionMethod,
        noScrollViewFailure: ElementInflationFailure,
        unsafeProgrammaticScrollMessage: String?,
        scrollFailedMessage: String
    ) async -> Result<TheSafecracker.ScrollPrimitiveResult, ElementInflationFailure> {
        if Self.interactionComfortZone.contains(activationPoint) {
            return .success(.alreadyInPosition)
        }
        guard let scrollView else {
            if ScreenMetrics.current.bounds.contains(activationPoint) {
                return .success(.alreadyInPosition)
            }
            return .failure(noScrollViewFailure)
        }
        if scrollView.bhIsUnsafeForProgrammaticScrolling,
           let unsafeProgrammaticScrollMessage {
            if ScreenMetrics.current.bounds.contains(activationPoint) {
                return .success(.alreadyInPosition)
            }
            return .failure(.geometryNotActionable(unsafeProgrammaticScrollMessage))
        }
        switch safecracker.scrollToMakeScreenPointVisible(
            activationPoint,
            in: scrollView,
            animated: false,
            preferredScreenRect: Self.interactionComfortZone,
            minimumScreenRect: ScreenMetrics.current.bounds
        ) {
        case .alreadyInPosition:
            return .success(.alreadyInPosition)
        case .unavailable:
            if ScreenMetrics.current.bounds.contains(activationPoint) {
                return .success(.alreadyInPosition)
            }
            return .failure(.geometryNotActionable(scrollFailedMessage))
        case .moved:
            await tripwire.yieldFrames(Self.postScrollLayoutFrames)
            return .success(.moved)
        }
    }

    internal struct LiveGeometrySample {
        internal let frame: CGRect
        internal let activationPoint: CGPoint

        internal init(frame: CGRect, activationPoint: CGPoint) {
            self.frame = frame
            self.activationPoint = activationPoint
        }

        fileprivate init(_ target: TheStash.LiveActionTarget) {
            frame = target.frame
            activationPoint = target.activationPoint
        }

        fileprivate func matches(_ other: LiveGeometrySample) -> Bool {
            frame.matchesForActionHandoff(other.frame)
                && activationPoint.matchesForActionHandoff(other.activationPoint)
        }
    }

    internal enum LiveGeometryStabilizationEvent {
        case sample(LiveGeometrySample, viewport: CGRect)
        case deadlineExpired
        case cancelled
    }

    internal enum LiveGeometryStabilizationReduction {
        case awaiting(LiveGeometryStabilization)
        case stable
        case offscreen
        case timedOut
        case cancelled
    }

    internal struct LiveGeometryStabilization {
        private let previous: LiveGeometrySample
        private let requiresOnscreen: Bool

        internal init(initial: LiveGeometrySample, requiresOnscreen: Bool) {
            previous = initial
            self.requiresOnscreen = requiresOnscreen
        }

        internal func reduce(
            _ event: LiveGeometryStabilizationEvent
        ) -> LiveGeometryStabilizationReduction {
            switch event {
            case .sample(let current, let viewport):
                guard !requiresOnscreen || viewport.contains(current.activationPoint) else {
                    return .offscreen
                }
                guard current.matches(previous) else {
                    return .awaiting(Self(initial: current, requiresOnscreen: requiresOnscreen))
                }
                return .stable
            case .deadlineExpired:
                return .timedOut
            case .cancelled:
                return .cancelled
            }
        }
    }

    private func stateAfterStableLiveGeometry(
        _ inflatedTarget: InflatedElementTarget,
        requireOnscreenActivationPoint: Bool,
        deadline: SemanticObservationDeadline
    ) async -> State {
        var stableTarget = inflatedTarget
        var stabilization = LiveGeometryStabilization(
            initial: LiveGeometrySample(inflatedTarget.liveTarget),
            requiresOnscreen: requireOnscreenActivationPoint
        )

        while deadline.hasTimeRemaining(at: CFAbsoluteTimeGetCurrent()) {
            guard !Task.isCancelled else {
                return stateAfterGeometryReduction(
                    stabilization.reduce(.cancelled),
                    target: stableTarget
                )
            }
            await tripwire.yieldRealFrames(1)
            guard !Task.isCancelled else {
                return stateAfterGeometryReduction(
                    stabilization.reduce(.cancelled),
                    target: stableTarget
                )
            }
            guard stash.refreshLiveCapture() != nil else { continue }
            switch visibleTargetResolution(inflatedTarget.target) {
            case .success(let currentTreeElement)?:
                guard let currentTarget = stableActionTarget(
                    target: inflatedTarget.target,
                    treeElement: currentTreeElement
                ) else {
                    return .failed(.staleRefresh(
                        "target \(Navigation.ScrollTargetDescription(currentTreeElement).description) "
                            + "could not be proven against the current live capture"
                    ))
                }
                stableTarget = currentTarget
                switch stabilization.reduce(.sample(
                    LiveGeometrySample(currentTarget.liveTarget),
                    viewport: ScreenMetrics.current.bounds
                )) {
                case .awaiting(let next):
                    stabilization = next
                case .stable:
                    return .inflated(currentTarget)
                case .offscreen:
                    return .failed(.geometryNotActionable(
                        "target \(Navigation.ScrollTargetDescription(currentTreeElement).description) "
                            + "activation point stayed off-screen after placement; "
                            + Self.liveGeometrySummary(currentTarget.liveTarget)
                    ))
                case .timedOut, .cancelled:
                    preconditionFailure("A geometry sample cannot reduce to timeout or cancellation")
                }
            case .failure(let failure)?:
                return .failed(failure)
            case nil:
                continue
            }
        }

        return stateAfterGeometryReduction(
            stabilization.reduce(.deadlineExpired),
            target: stableTarget
        )
    }

    private func stateAfterGeometryReduction(
        _ reduction: LiveGeometryStabilizationReduction,
        target: InflatedElementTarget
    ) -> State {
        switch reduction {
        case .timedOut:
            return .failed(.geometryNotActionable(
                "target \(Navigation.ScrollTargetDescription(target.treeElement).description) "
                    + "live geometry did not settle before the action deadline; "
                    + Self.liveGeometrySummary(target.liveTarget)
            ))
        case .cancelled:
            return .failed(.cancelled(
                "live geometry stabilization was cancelled for target "
                    + Navigation.ScrollTargetDescription(target.treeElement).description
            ))
        case .awaiting, .stable, .offscreen:
            preconditionFailure("Only terminal deadline events are handled here")
        }
    }

    private func stableActionTarget(
        target: AccessibilityTarget,
        treeElement: InterfaceTree.Element
    ) -> InflatedElementTarget? {
        guard case .resolved(let liveTarget) = stash.resolveLiveActionTarget(for: treeElement),
              retainedInterfaceElement(treeElement, matches: target)
        else { return nil }
        let semanticLiveTarget = TheStash.LiveActionTarget(
            treeElement: treeElement,
            object: liveTarget.object,
            frame: liveTarget.frame,
            activationPoint: liveTarget.activationPoint
        )
        return InflatedElementTarget(
            target: target,
            treeElement: treeElement,
            liveTarget: semanticLiveTarget
        )
    }
}

extension CGRect {
    fileprivate func matchesForActionHandoff(_ other: CGRect) -> Bool {
        origin.matchesForActionHandoff(other.origin)
            && size.matchesForActionHandoff(other.size)
    }
}

extension CGPoint {
    fileprivate func matchesForActionHandoff(_ other: CGPoint) -> Bool {
        abs(x - other.x) < 0.5
            && abs(y - other.y) < 0.5
    }
}

extension CGSize {
    fileprivate func matchesForActionHandoff(_ other: CGSize) -> Bool {
        abs(width - other.width) < 0.5
            && abs(height - other.height) < 0.5
    }
}

#endif // canImport(UIKit) && DEBUG
