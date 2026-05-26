#if canImport(UIKit)
#if DEBUG
import AccessibilitySnapshotModel
import AccessibilitySnapshotParser
import UIKit

import TheScore

// MARK: - Live Geometry Resolution

extension TheStash {

    /// Geometry sampled from the current accessibility capture at dispatch time.
    ///
    /// Invariant: this value is created from the current accessibility capture
    /// after rejecting unusable frames and non-finite activation points.
    /// Persisted selectors, source heistIds, and replay metadata never provide
    /// this data.
    struct LiveElementGeometry {
        let frame: CGRect
        let activationPoint: CGPoint

        init?(element: AccessibilityElement) {
            let frame = element.bhFrame
            let activationPoint = element.bhResolvedActivationPoint
            guard Self.isUsableFrame(frame),
                  Self.isUsablePoint(activationPoint) else {
                return nil
            }
            self.frame = frame
            self.activationPoint = activationPoint
        }

        init?(container: AccessibilityContainer) {
            let frame = container.frame.cgRect
            let activationPoint = CGPoint(x: frame.midX, y: frame.midY)
            guard Self.isUsableFrame(frame),
                  Self.isUsablePoint(activationPoint) else {
                return nil
            }
            self.frame = frame
            self.activationPoint = activationPoint
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

    /// Dispatch-only action target.
    ///
    /// The `resolvedTarget` is semantic identity; `object`, `frame`, and
    /// `activationPoint` are live accessibility authority freshly sampled by
    /// `resolveLiveActionTarget(for:)`.
    struct LiveActionTarget {
        let resolvedTarget: ResolvedTarget
        let object: NSObject
        let frame: CGRect
        let activationPoint: CGPoint

        var screenElement: ScreenElement { resolvedTarget.screenElement }
        var element: AccessibilityElement { resolvedTarget.element }
    }

    enum LiveActionTargetResolution {
        case resolved(LiveActionTarget)
        case objectUnavailable
        case geometryUnavailable
    }

    /// Dispatch-only container target.
    ///
    /// `resolvedTarget` is semantic container identity. The backing object is
    /// acquired from the latest live interface immediately before dispatch.
    struct LiveContainerTarget {
        let resolvedTarget: ResolvedContainerTarget
        let object: NSObject
        let frame: CGRect
        let activationPoint: CGPoint

        var container: AccessibilityContainer { resolvedTarget.container }
    }

    enum LiveContainerTargetResolution {
        case resolved(LiveContainerTarget)
        case objectUnavailable
        case geometryUnavailable
    }

    func resolveLiveActionTarget(for resolvedTarget: ResolvedTarget) -> LiveActionTargetResolution {
        guard let object = dispatchObject(for: resolvedTarget.screenElement) else {
            return .objectUnavailable
        }
        guard let geometry = LiveElementGeometry(element: resolvedTarget.element) else {
            return .geometryUnavailable
        }
        return .resolved(LiveActionTarget(
            resolvedTarget: resolvedTarget,
            object: object,
            frame: geometry.frame,
            activationPoint: geometry.activationPoint
        ))
    }

    func resolveLiveContainerTarget(for resolvedTarget: ResolvedContainerTarget) -> LiveContainerTargetResolution {
        guard let object = currentScreen.liveInterface.containerObject(forPath: resolvedTarget.path) else {
            return .objectUnavailable
        }
        guard let geometry = LiveElementGeometry(container: resolvedTarget.container) else {
            return .geometryUnavailable
        }
        return .resolved(LiveContainerTarget(
            resolvedTarget: resolvedTarget,
            object: object,
            frame: geometry.frame,
            activationPoint: geometry.activationPoint
        ))
    }

    func liveObject(for screenElement: ScreenElement) -> NSObject? {
        dispatchObject(for: screenElement)
    }

    func liveScrollView(for screenElement: ScreenElement) -> UIScrollView? {
        currentScreen.liveInterface.scrollView(for: screenElement)
    }

    func liveScrollView(forContainerPath path: TreePath) -> UIScrollView? {
        var ancestorIndices = path.indices
        while !ancestorIndices.isEmpty {
            ancestorIndices.removeLast()
            guard !ancestorIndices.isEmpty else { break }
            let ancestorPath = TreePath(ancestorIndices)
            let scrollView = currentScreen.liveInterface.scrollableContainerViewsByPath[ancestorPath]?.view as? UIScrollView
            if let scrollView {
                return scrollView
            }
        }
        return nil
    }

    private func dispatchObject(for screenElement: ScreenElement) -> NSObject? {
        if visibleIds.contains(screenElement.heistId) {
            return currentScreen.liveInterface.object(for: screenElement.heistId)
        }
        if currentScreen.knownInterface.findElement(heistId: screenElement.heistId) == nil {
            return currentScreen.liveInterface.object(for: screenElement.heistId)
        }
        return nil
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
