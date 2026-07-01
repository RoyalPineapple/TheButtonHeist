#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore
import ThePlans

import AccessibilitySnapshotParser

extension TheBurglar {

    struct ScreenBuildElementScrollFacts: Equatable {
        let membership: Screen.ScrollMembership
        let observedScrollContentActivationPoint: Screen.ObservedScrollContentActivationPoint?

        init(
            containerPath: TreePath,
            index: Int? = nil,
            observedScrollContentActivationPoint: Screen.ObservedScrollContentActivationPoint? = nil
        ) {
            self.init(
                membership: Screen.ScrollMembership(containerPath: containerPath, index: index),
                observedScrollContentActivationPoint: observedScrollContentActivationPoint
            )
        }

        init(
            membership: Screen.ScrollMembership,
            observedScrollContentActivationPoint: Screen.ObservedScrollContentActivationPoint? = nil
        ) {
            self.membership = membership
            self.observedScrollContentActivationPoint = observedScrollContentActivationPoint
        }
    }

    struct ScreenBuildScrollFacts: Equatable {
        let contextContainerPaths: Set<TreePath>
        let elementsByPath: [TreePath: ScreenBuildElementScrollFacts]
        let containerObservedScrollContentActivationPointsByPath: [TreePath: Screen.ObservedScrollContentActivationPoint]
        let inventoriesByPath: [TreePath: ScrollInventory]

        init(
            contextContainerPaths: Set<TreePath> = [],
            elementsByPath: [TreePath: ScreenBuildElementScrollFacts] = [:],
            containerObservedScrollContentActivationPointsByPath: [TreePath: Screen.ObservedScrollContentActivationPoint] = [:],
            inventoriesByPath: [TreePath: ScrollInventory] = [:]
        ) {
            self.contextContainerPaths = contextContainerPaths
            self.elementsByPath = elementsByPath
            self.containerObservedScrollContentActivationPointsByPath = containerObservedScrollContentActivationPointsByPath
            self.inventoriesByPath = inventoriesByPath
        }

        func element(at path: TreePath) -> ScreenBuildElementScrollFacts? {
            elementsByPath[path]
        }
    }

    struct ScreenBuildFocusFacts: Equatable {
        let firstResponderPaths: Set<TreePath>

        init(firstResponderPaths: Set<TreePath> = []) {
            self.firstResponderPaths = firstResponderPaths
        }

        func isFirstResponder(at path: TreePath) -> Bool {
            firstResponderPaths.contains(path)
        }
    }

    /// Value facts extracted from live UIKit / Objective-C accessibility
    /// objects before pure screen projection.
    struct ScreenBuildFacts: Equatable {
        let scroll: ScreenBuildScrollFacts
        let focus: ScreenBuildFocusFacts

        init(
            scroll: ScreenBuildScrollFacts = ScreenBuildScrollFacts(),
            focus: ScreenBuildFocusFacts = ScreenBuildFocusFacts()
        ) {
            self.scroll = scroll
            self.focus = focus
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
        let elementScrollExtraction = elementScrollFacts(
            hierarchy: hierarchy,
            elementContextsByPath: elementContextsByPath,
            objectsByPath: result.objectsByPath,
            scrollViewsByPath: result.scrollViewsByPath
        )

        return TheBurglar.ScreenBuildFacts(
            scroll: TheBurglar.ScreenBuildScrollFacts(
                contextContainerPaths: scrollContextContainerPaths,
                elementsByPath: elementScrollExtraction.elementsByPath,
                containerObservedScrollContentActivationPointsByPath: containerObservedScrollContentActivationPoints(
                    hierarchy: hierarchy,
                    identityContext: identityContext,
                    scrollViewsByPath: result.scrollViewsByPath
                ),
                inventoriesByPath: scrollInventories(
                    visibleIndicesByContainerPath: elementScrollExtraction.visibleIndicesByContainerPath,
                    scrollViewsByPath: result.scrollViewsByPath
                )
            ),
            focus: TheBurglar.ScreenBuildFocusFacts(
                firstResponderPaths: firstResponderPaths(in: result.objectsByPath)
            )
        )
    }

    private struct ElementScrollFactsExtraction {
        let elementsByPath: [TreePath: TheBurglar.ScreenBuildElementScrollFacts]
        let visibleIndicesByContainerPath: [TreePath: Set<Int>]
    }

    private static func firstResponderPaths(in objectsByPath: [TreePath: NSObject]) -> Set<TreePath> {
        Set(
            objectsByPath.compactMap { path, object in
                (object as? UIView)?.isFirstResponder == true ? path : nil
            }
        )
    }

    private static func elementScrollFacts(
        hierarchy: [AccessibilityHierarchy],
        elementContextsByPath: [TreePath: TheBurglar.ElementContext],
        objectsByPath: [TreePath: NSObject],
        scrollViewsByPath: [TreePath: UIScrollView]
    ) -> ElementScrollFactsExtraction {
        let indexedElements = hierarchy.pathIndexedElements
        var elementsByPath: [TreePath: TheBurglar.ScreenBuildElementScrollFacts] = [:]
        var visibleIndicesByContainerPath: [TreePath: Set<Int>] = [:]

        for (containerPath, scrollView) in scrollViewsByPath {
            for item in indexedElements
                where item.path != containerPath && item.path.hasPrefix(containerPath) {
                let index = scrollIndex(of: objectsByPath[item.path], in: scrollView)
                if let index {
                    visibleIndicesByContainerPath[containerPath, default: []].insert(index)
                }
                guard elementContextsByPath[item.path]?.scrollMembership?.containerPath == containerPath else {
                    continue
                }
                elementsByPath[item.path] = TheBurglar.ScreenBuildElementScrollFacts(
                    containerPath: containerPath,
                    index: index,
                    observedScrollContentActivationPoint: observedScrollContentActivationPoint(
                        for: item.element,
                        in: scrollView
                    )
                )
            }
        }

        return ElementScrollFactsExtraction(
            elementsByPath: elementsByPath,
            visibleIndicesByContainerPath: visibleIndicesByContainerPath
        )
    }

    private static func scrollInventories(
        visibleIndicesByContainerPath: [TreePath: Set<Int>],
        scrollViewsByPath: [TreePath: UIScrollView]
    ) -> [TreePath: ScrollInventory] {
        Dictionary(
            uniqueKeysWithValues: scrollViewsByPath.map { path, scrollView in
                return (
                    path,
                    ScrollInventory(
                        totalElementCount: totalElementCount(in: scrollView),
                        visibleIndices: (visibleIndicesByContainerPath[path] ?? []).sorted()
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
