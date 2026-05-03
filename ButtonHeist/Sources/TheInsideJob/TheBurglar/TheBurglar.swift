#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

/// The crew member who breaks in and takes what he finds.
///
/// TheBurglar reads the live accessibility tree, assigns heistIds, detects
/// screen changes, and populates TheStash's registry. He owns the parse
/// pipeline — the work of acquisition. TheStash owns the registry and
/// answers questions about it.
///
/// Intentionally module-internal so TheInsideJob unit tests can validate parse/apply behavior.
/// Production call sites should always go through TheStash facades.
@MainActor
final class TheBurglar {

    private let parser = AccessibilityHierarchyParser()
    private let tripwire: TheTripwire

    /// Persistence ratio below which a tab bar content swap counts as a tab switch.
    /// If fewer than this fraction of non-tab-bar labels persist between snapshots,
    /// we treat it as a screen change rather than a scroll.
    private static let tabSwitchPersistThreshold = 0.4

    init(tripwire: TheTripwire) {
        self.tripwire = tripwire
    }

    // MARK: - Parse Result

    /// Everything the parser produces in a single read. Value type — no mutation,
    /// no instance state. Created by `parse()`, consumed by `apply(_:)`.
    struct ParseResult {
        let elements: [AccessibilityElement]
        let hierarchy: [AccessibilityHierarchy]
        let objects: [AccessibilityElement: NSObject]
        let scrollViews: [AccessibilityContainer: UIView]
    }

    // MARK: - Parse (read-only)

    /// Read the live accessibility tree without mutating any state.
    /// Returns a ParseResult value that can be inspected (e.g., for topology comparison)
    /// before deciding whether to apply it.
    func parse() -> ParseResult? {
        let windows = tripwire.getAccessibleWindows()
        guard !windows.isEmpty else {
            insideJobLogger.debug("TheBurglar.parse(): no accessible windows — returning nil")
            return nil
        }

        // Parse runs on the main thread (UIKit accessibility SPI). Long parses
        // here are the main culprit when the main actor stalls during a UIKit
        // transition, so log durations to make the cost visible. Slow parses
        // (>= 100ms) get info-level so they show up without enabling debug logs.
        let parseStart = CFAbsoluteTimeGetCurrent()
        defer {
            let parseMs = Int((CFAbsoluteTimeGetCurrent() - parseStart) * 1000)
            if parseMs >= 100 {
                insideJobLogger.info("TheBurglar.parse(): \(parseMs)ms (\(windows.count) window(s))")
            } else {
                insideJobLogger.debug("TheBurglar.parse(): \(parseMs)ms (\(windows.count) window(s))")
            }
        }

        let revealedSearchBars = Self.revealHiddenSearchBars()
        defer { Self.restoreSearchBarHiding(revealedSearchBars) }

        var allHierarchy: [AccessibilityHierarchy] = []
        var allObjects: [AccessibilityElement: NSObject] = [:]
        var allScrollViews: [AccessibilityContainer: UIView] = [:]

        for (window, rootView) in windows {
            autoreleasepool {
                let windowTree = parser.parseAccessibilityHierarchy(
                    in: rootView,
                    rotorResultLimit: 0,
                    elementVisitor: { element, _, object in
                        allObjects[element] = object
                    },
                    containerVisitor: { container, object in
                        if case .scrollable = container.type, let view = object as? UIView {
                            allScrollViews[container] = view
                        }
                    }
                )

                if windows.count > 1 {
                    let windowName = NSStringFromClass(type(of: window))
                    let container = AccessibilityContainer(
                        type: .semanticGroup(
                            label: windowName,
                            value: "windowLevel: \(window.windowLevel.rawValue)",
                            identifier: nil
                        ),
                        frame: window.frame
                    )
                    allHierarchy.append(.container(container, children: windowTree))
                } else {
                    allHierarchy.append(contentsOf: windowTree)
                }
            }
        }

        return ParseResult(
            elements: allHierarchy.sortedElements,
            hierarchy: allHierarchy,
            objects: allObjects,
            scrollViews: allScrollViews
        )
    }

    // MARK: - Apply (mutates registry)

    /// Apply a parse result to the registry. Sets `currentHierarchy`,
    /// `scrollableContainerViews`, merges the parsed hierarchy into the
    /// persistent registry tree, refreshes viewport / reverseIndex.
    /// Returns the assigned heistIds so callers can track them (e.g. for
    /// explore cycle accumulation).
    @discardableResult
    func apply(_ result: ParseResult, to stash: TheStash) -> [String] {
        stash.currentHierarchy = result.hierarchy
        stash.scrollableContainerViews = result.scrollViews

        let contexts = buildElementContexts(
            hierarchy: result.hierarchy,
            scrollableContainerViews: result.scrollViews,
            elementObjects: result.objects
        )

        let containerIdentityContext = Self.buildContainerIdentityContext(
            hierarchy: result.hierarchy,
            scrollableContainerViews: result.scrollViews
        )

        let heistIds = TheStash.IdAssignment.assign(result.elements)
        stash.registry.register(
            parsedElements: result.elements,
            heistIds: heistIds,
            contexts: contexts,
            hierarchy: result.hierarchy,
            containerContentFrames: containerIdentityContext.contentFrames,
            containersNestedInScrollView: containerIdentityContext.nestedInScrollView,
            scrollableViews: result.scrollViews
        )

        // Detect first responder among parsed elements — no view hierarchy walk.
        let firstResponders = zip(result.elements, heistIds).filter { element, _ in
            (result.objects[element] as? UIView)?.isFirstResponder == true
        }
        if firstResponders.count > 1 {
            insideJobLogger.warning("Multiple first responders detected: \(firstResponders.map(\.1).joined(separator: ", "))")
        }
        stash.registry.firstResponderHeistId = firstResponders.first?.1

        // Cache screen name — first header element in traversal order.
        stash.lastScreenName = result.elements.first {
            $0.traits.contains(.header) && $0.label != nil
        }?.label
        stash.lastScreenId = TheStash.IdAssignment.slugify(stash.lastScreenName)

        return heistIds
    }

    /// Parse and apply in one step. Most callers use this.
    @discardableResult
    func refresh(into stash: TheStash) -> ParseResult? {
        guard let result = parse() else { return nil }
        apply(result, to: stash)
        return result
    }

    // MARK: - Topology-Based Screen Change

    /// Did the accessibility topology change between two element snapshots?
    func isTopologyChanged(
        before: [AccessibilityElement],
        after: [AccessibilityElement],
        beforeHierarchy: [AccessibilityHierarchy],
        afterHierarchy: [AccessibilityHierarchy]
    ) -> Bool {
        let backButtonTrait = UIAccessibilityTraits.fromNames(["backButton"])
        let hadBackButton = before.contains { $0.traits.contains(backButtonTrait) }
        let hasBackButton = after.contains { $0.traits.contains(backButtonTrait) }
        if hadBackButton != hasBackButton { return true }

        let beforeHeaders = Set(before.compactMap { $0.traits.contains(.header) ? $0.label : nil })
        let afterHeaders = Set(after.compactMap { $0.traits.contains(.header) ? $0.label : nil })
        if !beforeHeaders.isEmpty, !afterHeaders.isEmpty, beforeHeaders.isDisjoint(with: afterHeaders) {
            return true
        }

        // Tab bar content change: if the hierarchy contains a .tabBar container and the
        // elements outside that container were largely replaced, a tab switch occurred.
        if isTabBarContentChanged(beforeHierarchy: beforeHierarchy, afterHierarchy: afterHierarchy) {
            return true
        }

        return false
    }

    /// Returns true when the content outside a tab bar container changed between snapshots.
    ///
    /// Partitions each hierarchy into tab bar elements (inside `.tabBar` containers) and
    /// content elements (everything else). If both snapshots have a tab bar and the content
    /// elements are mostly different, the user switched tabs.
    private func isTabBarContentChanged(
        beforeHierarchy: [AccessibilityHierarchy],
        afterHierarchy: [AccessibilityHierarchy]
    ) -> Bool {
        let beforePartition = partitionByTabBar(beforeHierarchy)
        let afterPartition = partitionByTabBar(afterHierarchy)
        guard beforePartition.hasTabBar, afterPartition.hasTabBar else { return false }

        let beforeContent = beforePartition.contentLabels
        let afterContent = afterPartition.contentLabels
        guard !beforeContent.isEmpty, !afterContent.isEmpty else { return false }

        // Multiset intersection via per-label frequency: the overlap between
        // the two lists is the sum over all labels of min(beforeCount, afterCount).
        let beforeCounts = beforeContent.reduce(into: [:]) { counts, label in counts[label, default: 0] += 1 }
        let afterCounts = afterContent.reduce(into: [:]) { counts, label in counts[label, default: 0] += 1 }
        let matchedCount = beforeCounts.reduce(0) { running, pair in
            running + min(pair.value, afterCounts[pair.key] ?? 0)
        }

        let maxCount = max(beforeContent.count, afterContent.count)
        let persistRatio = Double(matchedCount) / Double(maxCount)
        return persistRatio < Self.tabSwitchPersistThreshold
    }

    private struct TabBarPartition {
        let hasTabBar: Bool
        let contentLabels: [String]
    }

    /// Walk the hierarchy tree, separating elements inside `.tabBar` containers from content.
    private func partitionByTabBar(_ hierarchy: [AccessibilityHierarchy]) -> TabBarPartition {
        var hasTabBar = false
        let contentLabels: [String] = hierarchy.compactMap(
            context: false,
            container: { insideTabBar, container in
                if case .tabBar = container.type {
                    hasTabBar = true
                    return true
                }
                return insideTabBar
            },
            element: { element, _, insideTabBar in
                if !insideTabBar, let label = element.label {
                    return label
                }
                return nil
            }
        )
        return TabBarPartition(hasTabBar: hasTabBar, contentLabels: contentLabels)
    }

    // MARK: - Container Content-Frame Building

    /// Walk the hierarchy tree to compute each container's frame expressed in
    /// the nearest enclosing scrollable's content space. Top-level containers
    /// (no enclosing scrollable) keep their screen-space frame.
    ///
    /// The result feeds `ElementRegistry.stableId` so a container nested in a
    /// scroll view keeps its identity as the outer view scrolls, and reusable
    /// cell-embedded containers at distinct logical positions get distinct
    /// ids (no UIView-instance ambiguity from the cell pool).
    struct ContainerIdentityContext {
        let contentFrames: [AccessibilityContainer: CGRect]
        let nestedInScrollView: Set<AccessibilityContainer>
    }

    static func buildContainerIdentityContext(
        hierarchy: [AccessibilityHierarchy],
        scrollableContainerViews: [AccessibilityContainer: UIView]
    ) -> ContainerIdentityContext {
        var contentFrames: [AccessibilityContainer: CGRect] = [:]
        var nestedInScrollView = Set<AccessibilityContainer>()
        for node in hierarchy {
            collectContainerContentFrames(
                node: node,
                parentScrollView: nil,
                scrollableContainerViews: scrollableContainerViews,
                into: &contentFrames,
                nestedInScrollView: &nestedInScrollView
            )
        }
        return ContainerIdentityContext(
            contentFrames: contentFrames,
            nestedInScrollView: nestedInScrollView
        )
    }

    private static func collectContainerContentFrames(
        node: AccessibilityHierarchy,
        parentScrollView: UIScrollView?,
        scrollableContainerViews: [AccessibilityContainer: UIView],
        into result: inout [AccessibilityContainer: CGRect],
        nestedInScrollView: inout Set<AccessibilityContainer>
    ) {
        guard case .container(let container, let children) = node else { return }

        let frame = container.frame
        let contentFrame: CGRect
        if let scrollView = parentScrollView, !frame.isNull, !frame.isEmpty {
            let origin = scrollView.convert(frame.origin, from: nil)
            contentFrame = CGRect(origin: origin, size: frame.size)
            nestedInScrollView.insert(container)
        } else {
            contentFrame = frame
        }
        result[container] = contentFrame

        let childScrollView: UIScrollView?
        if let scrollView = scrollableContainerViews[container] as? UIScrollView,
           !scrollView.bhIsUnsafeForProgrammaticScrolling {
            childScrollView = scrollView
        } else {
            childScrollView = parentScrollView
        }

        for child in children {
            collectContainerContentFrames(
                node: child,
                parentScrollView: childScrollView,
                scrollableContainerViews: scrollableContainerViews,
                into: &result,
                nestedInScrollView: &nestedInScrollView
            )
        }
    }

    // MARK: - Element Context Building

    /// Walk the hierarchy tree to gather per-element context: content-space origins,
    /// scroll view refs, and live element objects.
    private func buildElementContexts(
        hierarchy: [AccessibilityHierarchy],
        scrollableContainerViews: [AccessibilityContainer: UIView],
        elementObjects: [AccessibilityElement: NSObject]
    ) -> [AccessibilityElement: TheStash.ElementContext] {
        Dictionary(
            hierarchy.compactMap(
                context: nil as UIScrollView?,
                container: { parentScrollView, accessibilityContainer in
                    guard let scrollView = scrollableContainerViews[accessibilityContainer] as? UIScrollView,
                          !scrollView.bhIsUnsafeForProgrammaticScrolling else {
                        return parentScrollView
                    }
                    return scrollView
                },
                element: { element, _, scrollView in
                    let origin: CGPoint? = scrollView.flatMap { scrollView in
                        let frame = element.shape.frame
                        return (!frame.isNull && !frame.isEmpty)
                            ? scrollView.convert(frame.origin, from: nil)
                            : nil
                    }
                    return (
                        element,
                        TheStash.ElementContext(
                            contentSpaceOrigin: origin,
                            scrollView: scrollView,
                            object: elementObjects[element]
                        )
                    )
                }
            ),
            uniquingKeysWith: { _, latest in latest }
        )
    }

    // MARK: - Search Bar Reveal

    private static func revealHiddenSearchBars() -> [UINavigationItem] {
        var revealed: [UINavigationItem] = []
        guard let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return revealed }

        for window in windowScene.windows where !window.isHidden {
            guard let rootViewController = window.rootViewController else { continue }
            for viewController in allVisibleViewControllers(from: rootViewController) {
                let item = viewController.navigationItem
                guard item.searchController != nil, item.hidesSearchBarWhenScrolling else { continue }
                UIView.performWithoutAnimation {
                    item.hidesSearchBarWhenScrolling = false
                    viewController.navigationController?.navigationBar.layoutIfNeeded()
                }
                revealed.append(item)
            }
        }
        return revealed
    }

    private static func restoreSearchBarHiding(_ items: [UINavigationItem]) {
        guard !items.isEmpty else { return }
        UIView.performWithoutAnimation {
            for item in items {
                item.hidesSearchBarWhenScrolling = true
            }
        }
    }

    /// Walk the UIKit view controller tree from `root`, returning every leaf
    /// (non-container) view controller reachable through nav topViewController,
    /// tab selectedViewController, and modal presentedViewController edges.
    private static func allVisibleViewControllers(from root: UIViewController) -> [UIViewController] {
        let presentedChain = root.presentedViewController.map { allVisibleViewControllers(from: $0) } ?? []
        if let nav = root as? UINavigationController {
            let navChild = nav.topViewController.map { allVisibleViewControllers(from: $0) } ?? []
            return navChild + presentedChain
        }
        if let tab = root as? UITabBarController {
            let tabChild = tab.selectedViewController.map { allVisibleViewControllers(from: $0) } ?? []
            return tabChild + presentedChain
        }
        return [root] + presentedChain
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
