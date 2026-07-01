#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore
import ThePlans

import AccessibilitySnapshotParser

extension TheBurglar {

    /// Value facts extracted from live UIKit / Objective-C accessibility
    /// objects before pure screen projection.
    struct ScreenBuildFacts: Equatable {
        struct ScrollElementIndexKey: Hashable {
            let containerPath: TreePath
            let elementPath: TreePath
        }

        let scrollContextContainerPaths: Set<TreePath>
        let firstResponderPaths: Set<TreePath>
        let scrollElementIndicesByPath: [ScrollElementIndexKey: Int]
        let scrollInventoriesByPath: [TreePath: ScrollInventory]
        let elementObservedScrollContentActivationPointsByPath: [TreePath: Screen.ObservedScrollContentActivationPoint]
        let containerObservedScrollContentActivationPointsByPath: [TreePath: Screen.ObservedScrollContentActivationPoint]

        init(
            scrollContextContainerPaths: Set<TreePath> = [],
            firstResponderPaths: Set<TreePath> = [],
            scrollElementIndicesByPath: [ScrollElementIndexKey: Int] = [:],
            scrollInventoriesByPath: [TreePath: ScrollInventory] = [:],
            elementObservedScrollContentActivationPointsByPath: [TreePath: Screen.ObservedScrollContentActivationPoint] = [:],
            containerObservedScrollContentActivationPointsByPath: [TreePath: Screen.ObservedScrollContentActivationPoint] = [:]
        ) {
            self.scrollContextContainerPaths = scrollContextContainerPaths
            self.firstResponderPaths = firstResponderPaths
            self.scrollElementIndicesByPath = scrollElementIndicesByPath
            self.scrollInventoriesByPath = scrollInventoriesByPath
            self.elementObservedScrollContentActivationPointsByPath = elementObservedScrollContentActivationPointsByPath
            self.containerObservedScrollContentActivationPointsByPath = containerObservedScrollContentActivationPointsByPath
        }

        func scrollIndex(
            forElementAt elementPath: TreePath,
            in containerPath: TreePath
        ) -> Int? {
            scrollElementIndicesByPath[
                ScrollElementIndexKey(
                    containerPath: containerPath,
                    elementPath: elementPath
                )
            ]
        }
    }

}

@MainActor
extension TheBurglar.ScreenBuildFacts {

    /// UIKit boundary for screen-building facts. Keep Objective-C accessibility
    /// inventory/index reads, responder checks, scroll safety checks, and
    /// coordinate conversion here rather than in projection.
    static func extract(
        from result: TheBurglar.ParseResult,
        screenCoordinateHierarchy hierarchy: [AccessibilityHierarchy]
    ) -> TheBurglar.ScreenBuildFacts {
        let scrollContextContainerPaths = Set(
            result.scrollViewsByPath.compactMap { path, scrollView in
                scrollView.bhIsUnsafeForProgrammaticScrolling ? nil : path
            }
        )
        let identityContext = TheBurglar.buildContainerIdentityContext(
            hierarchy: hierarchy,
            scrollableContainerPaths: scrollContextContainerPaths
        )
        let elementContextsByPath = TheBurglar.buildElementContextsByPath(
            hierarchy: hierarchy,
            scrollableContainerPaths: scrollContextContainerPaths
        )
        let scrollElementIndicesByPath = scrollElementIndices(
            hierarchy: hierarchy,
            objectsByPath: result.objectsByPath,
            scrollViewsByPath: result.scrollViewsByPath
        )

        return TheBurglar.ScreenBuildFacts(
            scrollContextContainerPaths: scrollContextContainerPaths,
            firstResponderPaths: firstResponderPaths(in: result.objectsByPath),
            scrollElementIndicesByPath: scrollElementIndicesByPath,
            scrollInventoriesByPath: scrollInventories(
                hierarchy: hierarchy,
                indicesByPath: scrollElementIndicesByPath,
                scrollViewsByPath: result.scrollViewsByPath
            ),
            elementObservedScrollContentActivationPointsByPath: elementObservedScrollContentActivationPoints(
                hierarchy: hierarchy,
                elementContextsByPath: elementContextsByPath,
                scrollViewsByPath: result.scrollViewsByPath
            ),
            containerObservedScrollContentActivationPointsByPath: containerObservedScrollContentActivationPoints(
                hierarchy: hierarchy,
                identityContext: identityContext,
                scrollViewsByPath: result.scrollViewsByPath
            )
        )
    }

    private static func firstResponderPaths(in objectsByPath: [TreePath: NSObject]) -> Set<TreePath> {
        Set(
            objectsByPath.compactMap { path, object in
                (object as? UIView)?.isFirstResponder == true ? path : nil
            }
        )
    }

    private static func scrollElementIndices(
        hierarchy: [AccessibilityHierarchy],
        objectsByPath: [TreePath: NSObject],
        scrollViewsByPath: [TreePath: UIScrollView]
    ) -> [ScrollElementIndexKey: Int] {
        var indicesByPath: [ScrollElementIndexKey: Int] = [:]
        for (containerPath, scrollView) in scrollViewsByPath {
            for item in hierarchy.pathIndexedElements
                where item.path != containerPath && item.path.hasPrefix(containerPath) {
                guard let index = scrollIndex(
                    of: objectsByPath[item.path],
                    in: scrollView
                ) else { continue }
                indicesByPath[
                    ScrollElementIndexKey(
                        containerPath: containerPath,
                        elementPath: item.path
                    )
                ] = index
            }
        }
        return indicesByPath
    }

    private static func scrollInventories(
        hierarchy: [AccessibilityHierarchy],
        indicesByPath: [ScrollElementIndexKey: Int],
        scrollViewsByPath: [TreePath: UIScrollView]
    ) -> [TreePath: ScrollInventory] {
        Dictionary(
            uniqueKeysWithValues: scrollViewsByPath.map { path, scrollView in
                let visibleIndices = hierarchy.pathIndexedElements.compactMap { item -> Int? in
                    guard item.path != path, item.path.hasPrefix(path) else { return nil }
                    return indicesByPath[
                        ScrollElementIndexKey(
                            containerPath: path,
                            elementPath: item.path
                        )
                    ]
                }
                return (
                    path,
                    ScrollInventory(
                        totalElementCount: totalElementCount(in: scrollView),
                        visibleIndices: Array(Set(visibleIndices)).sorted()
                    )
                )
            }
        )
    }

    private static func totalElementCount(in scrollView: UIScrollView) -> Int? {
        let count = scrollView.accessibilityElementCount()
        guard count != NSNotFound, count >= 0 else { return nil }
        return count
    }

    private static func scrollIndex(of object: NSObject?, in scrollView: UIScrollView) -> Int? {
        guard let object else { return nil }
        let index = scrollView.index(ofAccessibilityElement: object)
        guard index != NSNotFound, index >= 0 else { return nil }
        return index
    }

    private static func elementObservedScrollContentActivationPoints(
        hierarchy: [AccessibilityHierarchy],
        elementContextsByPath: [TreePath: TheBurglar.ElementContext],
        scrollViewsByPath: [TreePath: UIScrollView]
    ) -> [TreePath: Screen.ObservedScrollContentActivationPoint] {
        Dictionary(
            uniqueKeysWithValues: elementContextsByPath.compactMap { path, context -> (TreePath, Screen.ObservedScrollContentActivationPoint)? in
                guard let containerPath = context.scrollMembership?.containerPath,
                      let scrollView = scrollViewsByPath[containerPath],
                      case .element(let element, _) = hierarchy.node(at: path),
                      let observedPoint = observedScrollContentActivationPoint(
                          for: element,
                          in: scrollView
                      )
                else { return nil }
                return (path, observedPoint)
            }
        )
    }

    private static func observedScrollContentActivationPoint(
        for element: AccessibilityElement,
        in scrollView: UIScrollView
    ) -> Screen.ObservedScrollContentActivationPoint? {
        let activationPoint = element.bhResolvedActivationPoint
        guard activationPoint.x.isFinite, activationPoint.y.isFinite else { return nil }
        return Screen.ObservedScrollContentActivationPoint(
            scrollView.convert(activationPoint, from: nil)
        )
    }

    private static func containerObservedScrollContentActivationPoints(
        hierarchy: [AccessibilityHierarchy],
        identityContext: TheBurglar.ContainerIdentityContext,
        scrollViewsByPath: [TreePath: UIScrollView]
    ) -> [TreePath: Screen.ObservedScrollContentActivationPoint] {
        Dictionary(
            uniqueKeysWithValues: hierarchy.compactMapSubtrees { node, path -> (TreePath, Screen.ObservedScrollContentActivationPoint)? in
                guard case .container(let container, _) = node,
                      let membership = identityContext.scrollMembershipsByPath[path],
                      let scrollView = scrollViewsByPath[membership.containerPath]
                else { return nil }
                let frame = container.frame.cgRect
                let activationPoint = CGPoint(x: frame.midX, y: frame.midY)
                guard activationPoint.x.isFinite, activationPoint.y.isFinite,
                      let observedPoint = Screen.ObservedScrollContentActivationPoint(
                          scrollView.convert(activationPoint, from: nil)
                      )
                else { return nil }
                return (path, observedPoint)
            }
        )
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
