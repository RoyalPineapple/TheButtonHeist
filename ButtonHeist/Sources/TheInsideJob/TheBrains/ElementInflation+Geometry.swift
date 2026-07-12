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
        attempt: Int,
        didReveal: Bool,
        method: ActionMethod,
        activationPointPolicy: ActivationPointPolicy
    ) async -> State {
        if activationPointPolicy == .liveObjectOnly {
            return await stateAfterStableLiveGeometry(
                inflatedTarget,
                attempt: attempt,
                method: method,
                requireOnscreenActivationPoint: false
            )
        }
        return .placing(inflatedTarget: inflatedTarget, attempt: attempt, didReveal: didReveal)
    }

    internal func stateAfterPlacement(
        _ inflatedTarget: InflatedElementTarget,
        didReveal: Bool,
        attempt: Int,
        method: ActionMethod
    ) async -> State {
        let liveTarget = inflatedTarget.liveTarget
        if ScreenMetrics.current.bounds.contains(liveTarget.activationPoint) {
            return await stateAfterStableLiveGeometry(
                inflatedTarget,
                attempt: attempt,
                method: method,
                requireOnscreenActivationPoint: true
            )
        }
        if didReveal {
            return .failed(.geometryNotActionable(
                "target \(Navigation.ScrollTargetDescription(liveTarget.screenElement).description) "
                    + "did not become actionable after semantic reveal; "
                    + Self.liveGeometrySummary(liveTarget)
            ))
        }

        let screenElement = liveTarget.screenElement
        let description = Navigation.ScrollTargetDescription(screenElement).description
        let placement = await scrollActivationPointIntoBounds(
            liveTarget.activationPoint,
            in: stash.liveScrollView(for: screenElement),
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
                attempt: attempt,
                method: method,
                requireOnscreenActivationPoint: true
            )
        case .success(.moved):
            return .retrying(failedAttempt: attempt, reason: .activationPointOffscreen)
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
            stash.refreshTreeAfterViewportMove()
            return .success(.moved)
        }
    }

    private struct LiveGeometrySample {
        fileprivate let frame: CGRect
        fileprivate let activationPoint: CGPoint

        fileprivate init(_ target: TheStash.LiveActionTarget) {
            frame = target.frame
            activationPoint = target.activationPoint
        }

        fileprivate init?(_ screenElement: TheStash.ScreenElement) {
            let frame = screenElement.element.bhFrame
            let activationPoint = screenElement.element.bhResolvedActivationPoint
            guard Self.isUsableFrame(frame),
                  Self.isUsablePoint(activationPoint)
            else { return nil }
            self.frame = frame
            self.activationPoint = activationPoint
        }

        fileprivate func matches(_ other: LiveGeometrySample) -> Bool {
            frame.matchesForActionHandoff(other.frame)
                && activationPoint.matchesForActionHandoff(other.activationPoint)
        }

        private static func isUsableFrame(_ frame: CGRect) -> Bool {
            !frame.isNull
                && !frame.isEmpty
                && frame.origin.x.isFinite
                && frame.origin.y.isFinite
                && frame.size.width.isFinite
                && frame.size.height.isFinite
        }

        private static func isUsablePoint(_ point: CGPoint) -> Bool {
            point.x.isFinite && point.y.isFinite
        }
    }

    private func stateAfterStableLiveGeometry(
        _ inflatedTarget: InflatedElementTarget,
        attempt: Int,
        method: ActionMethod,
        requireOnscreenActivationPoint: Bool
    ) async -> State {
        let deadline = CFAbsoluteTimeGetCurrent() + Self.stableGeometryTimeout
        var stableTarget = inflatedTarget
        var previous = LiveGeometrySample(inflatedTarget.liveTarget)
        var quietFrames = 1
        if !canRefreshLiveGeometryThroughWindow(inflatedTarget.liveTarget.object) {
            await tripwire.yieldRealFrames(1)
            if requireOnscreenActivationPoint,
               !ScreenMetrics.current.bounds.contains(stableTarget.liveTarget.activationPoint) {
                return .retrying(failedAttempt: attempt, reason: .activationPointOffscreen)
            }
            return .inflated(stableTarget)
        }

        while !Task.isCancelled {
            guard CFAbsoluteTimeGetCurrent() < deadline else { break }
            await tripwire.yieldRealFrames(1)
            guard stash.refreshLiveCapture() != nil else { continue }
            switch visibleTargetResolution(inflatedTarget.target) {
            case .success(let currentScreenElement)?:
                guard let current = LiveGeometrySample(currentScreenElement) else {
                    return .failed(.geometryNotActionable(
                        ActionCapabilityDiagnostic.gestureTargetUnavailable(
                            method: method,
                            element: currentScreenElement,
                            isVisible: stash.visibleIds.contains(currentScreenElement.heistId)
                        )
                    ))
                }
                if requireOnscreenActivationPoint,
                   !ScreenMetrics.current.bounds.contains(current.activationPoint) {
                    return .retrying(failedAttempt: attempt, reason: .activationPointOffscreen)
                }
                guard let currentTarget = stableActionTarget(
                    target: inflatedTarget.target,
                    screenElement: currentScreenElement
                ) else {
                    return .failed(.staleRefresh(
                        "target \(Navigation.ScrollTargetDescription(currentScreenElement).description) "
                            + "could not be proven against the current live capture"
                    ))
                }
                if current.matches(previous) {
                    quietFrames += 1
                    stableTarget = currentTarget
                    if quietFrames >= Self.stableGeometryQuietFrames {
                        return .inflated(stableTarget)
                    }
                } else {
                    previous = current
                    stableTarget = currentTarget
                    quietFrames = 1
                }
            case .failure(let failure)?:
                return .failed(failure)
            case nil:
                continue
            }
        }

        return .failed(.geometryNotActionable(
            "target \(Navigation.ScrollTargetDescription(stableTarget.screenElement).description) "
                + "live geometry did not settle within \(Int(Self.stableGeometryTimeout * 1_000))ms; "
                + Self.liveGeometrySummary(stableTarget.liveTarget)
        ))
    }

    private func stableActionTarget(
        target: ElementTarget,
        screenElement: TheStash.ScreenElement
    ) -> InflatedElementTarget? {
        guard case .resolved(let liveTarget) = stash.resolveLiveActionTarget(for: screenElement),
              retainedScreenElement(liveTarget.screenElement, matches: target)
        else { return nil }
        return InflatedElementTarget(
            target: target,
            screenElement: liveTarget.screenElement,
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
