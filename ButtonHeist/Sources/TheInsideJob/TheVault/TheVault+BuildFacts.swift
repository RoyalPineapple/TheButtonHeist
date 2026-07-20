#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore
import ThePlans

import AccessibilitySnapshotParser

extension TheVault {

    struct ElementScrollFacts: Equatable {
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

    struct ScrollFacts: Equatable {
        let contextContainerPaths: Set<TreePath>
        let elementsByPath: [TreePath: ElementScrollFacts]
        let containerObservedScrollContentActivationPointsByPath: [TreePath: InterfaceTree.ObservedScrollContentActivationPoint]
        let inventoriesByPath: [TreePath: ScrollInventory]

        init(
            contextContainerPaths: Set<TreePath> = [],
            elementsByPath: [TreePath: ElementScrollFacts] = [:],
            containerObservedScrollContentActivationPointsByPath: [TreePath: InterfaceTree.ObservedScrollContentActivationPoint] = [:],
            inventoriesByPath: [TreePath: ScrollInventory] = [:]
        ) {
            self.contextContainerPaths = contextContainerPaths
            self.elementsByPath = elementsByPath
            self.containerObservedScrollContentActivationPointsByPath = containerObservedScrollContentActivationPointsByPath
            self.inventoriesByPath = inventoriesByPath
        }

        func element(at path: TreePath) -> ElementScrollFacts? {
            elementsByPath[path]
        }
    }

    struct FocusFacts: Equatable {
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
    struct BuildFacts: Equatable {
        let scroll: ScrollFacts
        let focus: FocusFacts

        init(
            scroll: ScrollFacts = ScrollFacts(),
            focus: FocusFacts = FocusFacts()
        ) {
            self.scroll = scroll
            self.focus = focus
        }
    }

}

@MainActor
extension TheVault.BuildFacts {

    /// UIKit boundary for observation-building facts. Keep Objective-C accessibility
    /// inventory/index reads, responder checks, scroll safety checks, and
    /// coordinate conversion here rather than in projection.
    static func extract(
        from result: TheVault.CaptureResult,
        identityContext: TheVault.IdentityContext
    ) -> TheVault.BuildFacts {
        let elementScrollExtraction = elementScrollFacts(
            identityContext: identityContext,
            objectsByPath: result.objectsByPath,
            scrollViewsByPath: result.scrollViewsByPath
        )

        return TheVault.BuildFacts(
            scroll: TheVault.ScrollFacts(
                contextContainerPaths: identityContext.scrollableContainerPaths,
                elementsByPath: elementScrollExtraction.elementsByPath,
                containerObservedScrollContentActivationPointsByPath: containerObservedScrollContentActivationPoints(
                    identityContext: identityContext,
                    scrollViewsByPath: result.scrollViewsByPath
                ),
                inventoriesByPath: scrollInventories(
                    visibleIndicesByContainerPath: elementScrollExtraction.visibleIndicesByContainerPath,
                    scrollViewsByPath: result.scrollViewsByPath
                )
            ),
            focus: TheVault.FocusFacts(
                firstResponderPaths: firstResponderPaths(in: result.objectsByPath)
            )
        )
    }

    static func scrollContextContainerPaths(
        from result: TheVault.CaptureResult
    ) -> Set<TreePath> {
        Set(
            result.scrollViewsByPath.compactMap { path, scrollView in
                scrollView.bhIsUnsafeForProgrammaticScrolling ? nil : path
            }
        )
    }

    private struct ElementScrollFactsExtraction {
        let elementsByPath: [TreePath: TheVault.ElementScrollFacts]
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
        identityContext: TheVault.IdentityContext,
        objectsByPath: [TreePath: NSObject],
        scrollViewsByPath: [TreePath: UIScrollView]
    ) -> ElementScrollFactsExtraction {
        var elementsByPath: [TreePath: TheVault.ElementScrollFacts] = [:]
        var visibleIndicesByContainerPath: [TreePath: Set<Int>] = [:]

        for identity in identityContext.elements {
            guard let membership = identity.scrollMembership,
                  let scrollView = scrollViewsByPath[membership.containerPath]
            else { continue }

            let index = scrollIndex(of: objectsByPath[identity.path], in: scrollView)
            if let index {
                visibleIndicesByContainerPath[membership.containerPath, default: []].insert(index)
            }
            elementsByPath[identity.path] = TheVault.ElementScrollFacts(
                membership: InterfaceTree.ScrollMembership(
                    containerPath: membership.containerPath,
                    index: index
                ),
                observedScrollContentActivationPoint: observedScrollContentActivationPoint(
                    for: identity.element,
                    in: scrollView
                )
            )
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
            uniqueKeysWithValues: scrollViewsByPath.compactMap { path, scrollView in
                guard let inventory = ScrollInventory(
                    totalElementCount: totalElementCount(in: scrollView),
                    visibleIndices: (visibleIndicesByContainerPath[path] ?? []).sorted()
                ) else { return nil }
                return (path, inventory)
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
        identityContext: TheVault.IdentityContext,
        scrollViewsByPath: [TreePath: UIScrollView]
    ) -> [TreePath: InterfaceTree.ObservedScrollContentActivationPoint] {
        Dictionary(
            uniqueKeysWithValues: identityContext.containers.compactMap { identity in
                guard let membership = identity.scrollMembership,
                      let scrollView = scrollViewsByPath[membership.containerPath]
                else { return nil }
                let frame = identity.container.frame.cgRect
                let activationPoint = CGPoint(x: frame.midX, y: frame.midY)
                guard activationPoint.x.isFinite, activationPoint.y.isFinite,
                      let observedPoint = InterfaceTree.ObservedScrollContentActivationPoint(
                          scrollView.convert(activationPoint, from: nil)
                      )
                else { return nil }
                return (identity.path, observedPoint)
            }
        )
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
