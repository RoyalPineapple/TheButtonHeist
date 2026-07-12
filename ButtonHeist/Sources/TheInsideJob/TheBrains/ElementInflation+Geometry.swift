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
        activationPointPolicy: ActivationPointPolicy
    ) async -> State {
        if activationPointPolicy == .liveObjectOnly {
            return await stateAfterStableLiveGeometry(
                inflatedTarget,
                requireOnscreenActivationPoint: false
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
                requireOnscreenActivationPoint: true
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
                requireOnscreenActivationPoint: true
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

    private func stateAfterStableLiveGeometry(
        _ inflatedTarget: InflatedElementTarget,
        requireOnscreenActivationPoint: Bool
    ) async -> State {
        if !canRefreshLiveGeometryThroughWindow(inflatedTarget.liveTarget.object) {
            await tripwire.yieldRealFrames(1)
            if requireOnscreenActivationPoint,
               !ScreenMetrics.current.bounds.contains(inflatedTarget.liveTarget.activationPoint) {
                return .failed(.geometryNotActionable(
                    "target \(Navigation.ScrollTargetDescription(inflatedTarget.treeElement).description) "
                        + "activation point stayed off-screen"
                ))
            }
            return .inflated(inflatedTarget)
        }

        await tripwire.yieldRealFrames(1)
        guard stash.refreshLiveCapture() != nil else {
            return .failed(.geometryNotActionable(
                "target \(Navigation.ScrollTargetDescription(inflatedTarget.treeElement).description) "
                    + "live geometry refresh was unavailable"
            ))
        }
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
            if requireOnscreenActivationPoint,
               !ScreenMetrics.current.bounds.contains(currentTarget.liveTarget.activationPoint) {
                return .failed(.geometryNotActionable(
                    "target \(Navigation.ScrollTargetDescription(currentTreeElement).description) "
                        + "activation point stayed off-screen"
                ))
            }
            return .inflated(currentTarget)
        case .failure(let failure)?:
            return .failed(failure)
        case nil:
            return .failed(.staleRefresh(
                "settled target was unavailable after refreshing live geometry"
            ))
        }
    }

    private func stableActionTarget(
        target: AccessibilityTarget,
        treeElement: InterfaceTree.Element
    ) -> InflatedElementTarget? {
        guard case .resolved(let liveTarget) = stash.resolveLiveActionTarget(for: treeElement),
              retainedInterfaceElement(liveTarget.treeElement, matches: target)
        else { return nil }
        return InflatedElementTarget(
            target: target,
            treeElement: liveTarget.treeElement,
            liveTarget: liveTarget
        )
    }

    private func canRefreshLiveGeometryThroughWindow(_ object: NSObject) -> Bool {
        if let view = object as? UIView {
            return view.window != nil
        }
        if let element = object as? UIAccessibilityElement,
           let view = element.accessibilityContainer as? UIView {
            return view.window != nil
        }
        return false
    }
}

#endif // canImport(UIKit) && DEBUG
