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
        activationPointPolicy: ActivationPointPolicy
    ) async -> State {
        if activationPointPolicy == .liveObjectOnly {
            return await stateAfterStableLiveGeometry(
                inflatedTarget,
                requireOnscreenActivationPoint: false
            )
        }
        return .placing(inflatedTarget)
    }

    internal func stateAfterPlacement(
        _ inflatedTarget: InflatedElementTarget,
        method: ActionMethod,
        transaction: RevealTransaction
    ) async -> State {
        let liveTarget = inflatedTarget.liveTarget
        if ScreenMetrics.current.bounds.contains(liveTarget.activationPoint) {
            return await stateAfterStableLiveGeometry(
                inflatedTarget,
                requireOnscreenActivationPoint: true
            )
        }
        if inflatedTarget.resolution.adjustments.contains(.semanticReveal) {
            return .failed(.geometryNotActionable(
                "target \(Navigation.ScrollTargetDescription(liveTarget.treeElement).description) "
                    + "did not become actionable after semantic reveal; "
                    + Self.liveGeometrySummary(liveTarget)
            ))
        }

        let treeElement = liveTarget.treeElement
        let description = Navigation.ScrollTargetDescription(treeElement).description
        let settledSequence = vault.semanticObservationStream.latestCommittedEvent?.sequence
        let placement = await scrollActivationPointIntoBounds(
            liveTarget.activationPoint,
            in: vault.liveScrollView(for: treeElement),
            method: method,
            noScrollViewFailure: noScrollViewFailure(
                for: liveTarget,
                description: description,
                method: method
            ),
            unsafeProgrammaticScrollMessage: nil,
            scrollFailedMessage: "target \(description) activation point could not be brought on-screen",
            transaction: transaction
        )
        switch placement {
        case .success(.alreadyInPosition):
            return await stateAfterStableLiveGeometry(
                inflatedTarget,
                requireOnscreenActivationPoint: true
            )
        case .success(.moved):
            switch await awaitLiveTargetRefresh(
                for: inflatedTarget.target,
                treeElement: inflatedTarget.treeElement,
                method: method,
                after: settledSequence,
                deadline: inflatedTarget.deadline,
                resolution: inflatedTarget.resolution.adding(.activationPointPlacement)
            ) {
            case .inflated(let refreshedTarget):
                return await stateAfterStableLiveGeometry(
                    refreshedTarget,
                    requireOnscreenActivationPoint: true
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
        scrollFailedMessage: String,
        transaction: RevealTransaction? = nil
    ) async -> Result<TheSafecracker.ScrollPrimitiveOutcome, ElementInflationFailure> {
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
        guard let scrollTarget = Navigation.ScrollableTarget.programmatic(scrollView, in: vault) else {
            return .failure(.geometryNotActionable(scrollFailedMessage))
        }
        transaction?.record(scrollView)
        let transition = await exploration.moveViewport(
            .revealPoint(
                activationPoint,
                in: scrollTarget,
                preferredScreenRect: Self.interactionComfortZone,
                minimumScreenRect: ScreenMetrics.current.bounds
            )
        )
        switch transition.outcome {
        case .unchanged:
            return .success(.alreadyInPosition)
        case .unavailable:
            if ScreenMetrics.current.bounds.contains(activationPoint) {
                return .success(.alreadyInPosition)
            }
            return .failure(.geometryNotActionable(scrollFailedMessage))
        case .moved:
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

        fileprivate init(_ target: TheVault.LiveActionTarget) {
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
        requireOnscreenActivationPoint: Bool
    ) async -> State {
        let deadline = inflatedTarget.deadline
        var stableTarget = inflatedTarget
        var stabilization = LiveGeometryStabilization(
            initial: LiveGeometrySample(inflatedTarget.liveTarget),
            requiresOnscreen: requireOnscreenActivationPoint
        )

        while deadline.hasTimeRemaining(at: geometryEnvironment.now()) {
            guard !Task.isCancelled else {
                return stateAfterGeometryReduction(
                    stabilization.reduce(.cancelled),
                    target: stableTarget
                )
            }
            await geometryEnvironment.awaitFrame()
            guard !Task.isCancelled else {
                return stateAfterGeometryReduction(
                    stabilization.reduce(.cancelled),
                    target: stableTarget
                )
            }
            guard deadline.hasTimeRemaining(at: geometryEnvironment.now()) else {
                return stateAfterGeometryReduction(
                    stabilization.reduce(.deadlineExpired),
                    target: stableTarget
                )
            }
            guard vault.refreshLiveCapture() != nil else { continue }
            guard let currentTreeElement = vault.interfaceElement(
                heistId: inflatedTarget.treeElement.heistId
            ) else {
                return .failed(.staleRefresh(
                    "selected target \(inflatedTarget.treeElement.heistId.rawValue) left committed semantic truth"
                ))
            }
            let currentTarget: InflatedElementTarget
            switch stableActionTarget(
                target: inflatedTarget.target,
                treeElement: currentTreeElement,
                deadline: deadline,
                resolution: stableTarget.resolution
            ) {
            case .resolved(let target):
                currentTarget = target
            case .retry(let reason):
                stableTarget = stableTarget.adding(reason.adjustment)
                continue
            case .unavailable:
                continue
            }
            stableTarget = currentTarget
            guard deadline.hasTimeRemaining(at: geometryEnvironment.now()) else {
                return stateAfterGeometryReduction(
                    stabilization.reduce(.deadlineExpired),
                    target: stableTarget
                )
            }
            switch stabilization.reduce(.sample(
                LiveGeometrySample(currentTarget.liveTarget),
                viewport: ScreenMetrics.current.bounds
            )) {
            case .awaiting(let next):
                stabilization = next
            case .stable:
                guard deadline.hasTimeRemaining(at: geometryEnvironment.now()) else {
                    return stateAfterGeometryReduction(
                        stabilization.reduce(.deadlineExpired),
                        target: stableTarget
                    )
                }
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
            return .failed(.timedOut(
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

    private enum StableActionTargetResolution {
        case resolved(InflatedElementTarget)
        case retry(RetryReason)
        case unavailable
    }

    private func stableActionTarget(
        target: ResolvedAccessibilityTarget,
        treeElement: InterfaceTree.Element,
        deadline: SemanticObservationDeadline,
        resolution: ActionSubjectResolution
    ) -> StableActionTargetResolution {
        let liveTarget: TheVault.LiveActionTarget
        switch vault.resolveLiveActionTarget(for: treeElement) {
        case .resolved(let target):
            liveTarget = target
        case .objectUnavailable:
            return .retry(.objectDeallocated)
        case .geometryUnavailable:
            return .unavailable
        }
        return .resolved(InflatedElementTarget(
            target: target,
            treeElement: treeElement,
            liveTarget: liveTarget,
            deadline: deadline,
            resolution: resolution
        ))
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
