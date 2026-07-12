#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore
import ThePlans

import AccessibilitySnapshotParser

extension TheBurglar {

    struct InterfaceObservationBuildElementScrollFacts: Equatable {
        let membership: InterfaceTree.ScrollMembership
        let observedScrollContentActivationPoint: InterfaceTree.ObservedScrollContentActivationPoint?

        init(
            containerPath: TreePath,
            index: Int? = nil,
            observedScrollContentActivationPoint: InterfaceTree.ObservedScrollContentActivationPoint? = nil
        ) {
            self.init(
                membership: InterfaceTree.ScrollMembership(containerPath: containerPath, index: index),
                observedScrollContentActivationPoint: observedScrollContentActivationPoint
            )
        }

        init(
            membership: InterfaceTree.ScrollMembership,
            observedScrollContentActivationPoint: InterfaceTree.ObservedScrollContentActivationPoint? = nil
        ) {
            self.membership = membership
            self.observedScrollContentActivationPoint = observedScrollContentActivationPoint
        }
    }

    struct InterfaceObservationBuildScrollFacts: Equatable {
        let contextContainerPaths: Set<TreePath>
        let elementsByPath: [TreePath: InterfaceObservationBuildElementScrollFacts]
        let containerObservedScrollContentActivationPointsByPath: [TreePath: InterfaceTree.ObservedScrollContentActivationPoint]
        let inventoriesByPath: [TreePath: ScrollInventory]

        init(
            contextContainerPaths: Set<TreePath> = [],
            elementsByPath: [TreePath: InterfaceObservationBuildElementScrollFacts] = [:],
            containerObservedScrollContentActivationPointsByPath: [TreePath: InterfaceTree.ObservedScrollContentActivationPoint] = [:],
            inventoriesByPath: [TreePath: ScrollInventory] = [:]
        ) {
            self.contextContainerPaths = contextContainerPaths
            self.elementsByPath = elementsByPath
            self.containerObservedScrollContentActivationPointsByPath = containerObservedScrollContentActivationPointsByPath
            self.inventoriesByPath = inventoriesByPath
        }

        func element(at path: TreePath) -> InterfaceObservationBuildElementScrollFacts? {
            elementsByPath[path]
        }
    }

    struct InterfaceObservationBuildFocusFacts: Equatable {
        let firstResponderPaths: Set<TreePath>

        init(firstResponderPaths: Set<TreePath> = []) {
            self.firstResponderPaths = firstResponderPaths
        }

        func isFirstResponder(at path: TreePath) -> Bool {
            firstResponderPaths.contains(path)
        }
    }

    /// Value facts extracted from live UIKit / Objective-C accessibility
    /// objects before pure interface projection.
    struct InterfaceObservationBuildFacts: Equatable {
        let scroll: InterfaceObservationBuildScrollFacts
        let focus: InterfaceObservationBuildFocusFacts

        init(
            scroll: InterfaceObservationBuildScrollFacts = InterfaceObservationBuildScrollFacts(),
            focus: InterfaceObservationBuildFocusFacts = InterfaceObservationBuildFocusFacts()
        ) {
            self.scroll = scroll
            self.focus = focus
        }
    }

}

@MainActor
extension TheBurglar.InterfaceObservationBuildFacts {

    /// UIKit boundary for observation-building facts. Keep Objective-C accessibility
    /// inventory/index reads, responder checks, scroll safety checks, and
    /// coordinate conversion here rather than in projection.
    static func extract(
        from result: TheBurglar.ParseResult,
        screenCoordinateHierarchy hierarchy: [AccessibilityHierarchy]
    ) -> TheBurglar.InterfaceObservationBuildFacts {
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

        return TheBurglar.InterfaceObservationBuildFacts(
            scroll: TheBurglar.InterfaceObservationBuildScrollFacts(
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
            focus: TheBurglar.InterfaceObservationBuildFocusFacts(
                firstResponderPaths: firstResponderPaths(in: result.objectsByPath)
            )
        )
    }

    private struct ElementScrollFactsExtraction {
        let elementsByPath: [TreePath: TheBurglar.InterfaceObservationBuildElementScrollFacts]
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
        let indexedElementsByPath = Dictionary(
            uniqueKeysWithValues: hierarchy.pathIndexedElements.map { ($0.path, $0.element) }
        )
        var elementPathsByContainerPath: [TreePath: [TreePath]] = [:]
        for (path, context) in elementContextsByPath {
            guard let membership = context.scrollMembership else { continue }
            elementPathsByContainerPath[membership.containerPath, default: []].append(path)
        }

        var elementsByPath: [TreePath: TheBurglar.InterfaceObservationBuildElementScrollFacts] = [:]
        var visibleIndicesByContainerPath: [TreePath: Set<Int>] = [:]

        for (containerPath, scrollView) in scrollViewsByPath {
            for path in elementPathsByContainerPath[containerPath, default: []] {
                guard let element = indexedElementsByPath[path],
                      let membership = elementContextsByPath[path]?.scrollMembership
                else { continue }

                let index = scrollIndex(of: objectsByPath[path], in: scrollView)
                if let index {
                    visibleIndicesByContainerPath[containerPath, default: []].insert(index)
                }
                elementsByPath[path] = TheBurglar.InterfaceObservationBuildElementScrollFacts(
                    membership: InterfaceTree.ScrollMembership(
                        containerPath: membership.containerPath,
                        index: index
                    ),
                    observedScrollContentActivationPoint: observedScrollContentActivationPoint(
                        for: element,
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
    ) -> InterfaceTree.ObservedScrollContentActivationPoint? {
        let activationPoint = element.bhResolvedActivationPoint
        guard activationPoint.x.isFinite, activationPoint.y.isFinite else { return nil }
        return InterfaceTree.ObservedScrollContentActivationPoint(
            scrollView.convert(activationPoint, from: nil)
        )
    }

    private static func containerObservedScrollContentActivationPoints(
        hierarchy: [AccessibilityHierarchy],
        identityContext: TheBurglar.ContainerIdentityContext,
        scrollViewsByPath: [TreePath: UIScrollView]
    ) -> [TreePath: InterfaceTree.ObservedScrollContentActivationPoint] {
        Dictionary(
            uniqueKeysWithValues: hierarchy.compactMapSubtrees { node, path -> (TreePath, InterfaceTree.ObservedScrollContentActivationPoint)? in
                guard case .container(let container, _) = node,
                      let membership = identityContext.scrollMembershipsByPath[path],
                      let scrollView = scrollViewsByPath[membership.containerPath]
                else { return nil }
                let frame = container.frame.cgRect
                let activationPoint = CGPoint(x: frame.midX, y: frame.midY)
                guard activationPoint.x.isFinite, activationPoint.y.isFinite,
                      let observedPoint = InterfaceTree.ObservedScrollContentActivationPoint(
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
