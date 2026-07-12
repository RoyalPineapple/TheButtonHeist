#if canImport(UIKit)
#if DEBUG
import AccessibilitySnapshotModel
import AccessibilitySnapshotParser
import UIKit

import TheScore

// MARK: - Live Geometry Resolution

extension TheStash {

    /// Dispatch-only action target.
    ///
    /// The `treeElement` is semantic identity; `object`, `frame`, and
    /// `activationPoint` are live accessibility authority freshly sampled by
    /// `resolveLiveActionTarget(for:)`.
    struct LiveActionTarget {
        let treeElement: InterfaceTree.Element
        let object: NSObject
        let frame: CGRect
        let activationPoint: CGPoint

        var element: AccessibilityElement { treeElement.element }
    }

    enum LiveActionTargetResolution {
        case resolved(LiveActionTarget)
        case objectUnavailable
        case geometryUnavailable
    }

    /// Dispatch-only container target.
    ///
    /// `containerTarget` is semantic container identity. The backing object is
    /// acquired from the latest live interface immediately before dispatch.
    struct LiveContainerTarget {
        let containerTarget: InterfaceTree.Container
        let object: NSObject
        let frame: CGRect
        let activationPoint: CGPoint

        var container: AccessibilityContainer { containerTarget.container }
    }

    enum LiveContainerTargetResolution {
        case resolved(LiveContainerTarget)
        case objectUnavailable
        case geometryUnavailable
    }

    private struct LiveGeometry {
        let frame: CGRect
        let activationPoint: CGPoint
    }

    func resolveLiveActionTarget(for treeElement: InterfaceTree.Element) -> LiveActionTargetResolution {
        guard let object = dispatchObject(for: treeElement) else {
            return .objectUnavailable
        }
        let liveElement = liveInterfaceElement(heistId: treeElement.heistId) ?? treeElement
        guard let geometry = Self.liveGeometry(for: liveElement.element) else {
            return .geometryUnavailable
        }
        return .resolved(LiveActionTarget(
            treeElement: liveElement,
            object: object,
            frame: geometry.frame,
            activationPoint: geometry.activationPoint
        ))
    }

    func resolveLiveContainerTarget(for containerTarget: InterfaceTree.Container) -> LiveContainerTargetResolution {
        guard let object = liveContainerObject(forPath: containerTarget.path) else {
            return .objectUnavailable
        }
        guard let liveContainer = liveContainer(forPath: containerTarget.path),
              let geometry = Self.liveGeometry(for: liveContainer) else {
            return .geometryUnavailable
        }
        return .resolved(LiveContainerTarget(
            containerTarget: containerTarget,
            object: object,
            frame: geometry.frame,
            activationPoint: geometry.activationPoint
        ))
    }

    func liveObject(for treeElement: InterfaceTree.Element) -> NSObject? {
        dispatchObject(for: treeElement)
    }

    func liveScrollView(forContainerPath path: TreePath) -> UIScrollView? {
        var ancestorIndices = path.indices
        while !ancestorIndices.isEmpty {
            ancestorIndices.removeLast()
            guard !ancestorIndices.isEmpty else { break }
            let ancestorPath = TreePath(ancestorIndices)
            let scrollView = liveScrollableContainerView(forPath: ancestorPath)
            if let scrollView {
                return scrollView
            }
        }
        return nil
    }

    private func dispatchObject(for treeElement: InterfaceTree.Element) -> NSObject? {
        if viewportElementIDs.contains(treeElement.heistId) {
            return liveObject(for: treeElement.heistId)
        }
        return nil
    }

    private static func liveGeometry(for element: AccessibilityElement) -> LiveGeometry? {
        let frame = element.bhFrame
        let activationPoint = element.bhResolvedActivationPoint
        guard isUsableFrame(frame),
              isUsablePoint(activationPoint) else {
            return nil
        }
        return LiveGeometry(frame: frame, activationPoint: activationPoint)
    }

    private static func liveGeometry(for container: AccessibilityContainer) -> LiveGeometry? {
        let frame = container.frame.cgRect
        let activationPoint = CGPoint(x: frame.midX, y: frame.midY)
        guard isUsableFrame(frame),
              isUsablePoint(activationPoint) else {
            return nil
        }
        return LiveGeometry(frame: frame, activationPoint: activationPoint)
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

#endif // DEBUG
#endif // canImport(UIKit)
