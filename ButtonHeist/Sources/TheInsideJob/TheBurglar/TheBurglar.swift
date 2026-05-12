#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

/// The crew member who breaks in and takes what he finds.
///
/// TheBurglar reads the live accessibility tree, assigns heistIds, and detects
/// screen changes. Pure helpers — he has no mutable state. TheStash invokes
/// him via `parse()` to obtain a `Screen` value, then commits or merges it on
/// its own schedule.
///
/// Intentionally module-internal so TheInsideJob unit tests can validate parse
/// behavior. Production call sites should always go through TheStash facades.
@MainActor
final class TheBurglar {

    private let parser = AccessibilityHierarchyParser()
    private let tripwire: TheTripwire

    init(tripwire: TheTripwire) {
        self.tripwire = tripwire
    }

    // MARK: - Parse Result (internal)

    /// Internal parse intermediate — raw output from the AccessibilitySnapshotParser
    /// walk before heistId assignment. Tests use it to inject pre-parsed data.
    struct ParseResult {
        let elements: [AccessibilityElement]
        let hierarchy: [AccessibilityHierarchy]
        let objects: [AccessibilityElement: NSObject]
        let scrollViews: [AccessibilityContainer: UIView]
    }

    // MARK: - Parse (read-only)

    /// Read the live accessibility tree without mutating any state.
    /// Returns a ParseResult value or nil if no accessible windows exist.
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

        let beforeCounts = beforeContent.reduce(into: [:]) { counts, label in counts[label, default: 0] += 1 }
        let afterCounts = afterContent.reduce(into: [:]) { counts, label in counts[label, default: 0] += 1 }
        let matchedCount = beforeCounts.reduce(0) { running, pair in
            running + min(pair.value, afterCounts[pair.key] ?? 0)
        }

        let maxCount = max(beforeContent.count, afterContent.count)
        let persistRatio = Double(matchedCount) / Double(maxCount)
        return persistRatio < AccessibilityPolicy.tabSwitchPersistThreshold
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

    struct ElementContext {
        let contentSpaceOrigin: CGPoint?
        weak var scrollView: UIScrollView?
        weak var object: NSObject?
    }

    /// Walk the hierarchy tree to gather per-element context: content-space origins,
    /// scroll view refs, and live element objects.
    static func buildElementContexts(
        hierarchy: [AccessibilityHierarchy],
        scrollableContainerViews: [AccessibilityContainer: UIView],
        elementObjects: [AccessibilityElement: NSObject]
    ) -> [AccessibilityElement: ElementContext] {
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
                        ElementContext(
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

    // MARK: - Stable Container Identity

    /// Compute a stable identifier for a parser container, derived from its
    /// own exposed values. Identifiers persist across parses so callers that
    /// compare container identity across reads (wire tree edits, exploration
    /// caching) survive normal layout drift.
    static func stableId(
        for container: AccessibilityContainer,
        contentFrame: CGRect,
        isNestedInScrollView: Bool = false,
        scrollableView: UIView? = nil
    ) -> String {
        let frameHash = coarseFrameHash(contentFrame)
        switch container.type {
        case .scrollable:
            if let scrollableView, !isNestedInScrollView {
                let oid = ObjectIdentifier(scrollableView)
                return "scrollable_\(String(oid.hashValue, radix: 16))"
            }
            return "scrollable_\(frameHash)"
        case .semanticGroup(let label, let value, let identifier):
            let labelSlug = TheScore.slugify(label) ?? "anon"
            let valueSlug = TheScore.slugify(value) ?? ""
            let identifierSlug = identifier ?? ""
            return "semantic_\(identifierSlug)_\(labelSlug)_\(valueSlug)"
        case .list:
            return "list_\(frameHash)"
        case .landmark:
            return "landmark_\(frameHash)"
        case .tabBar:
            return "tabBar_\(frameHash)"
        case .dataTable(let rows, let columns):
            return "table_\(rows)x\(columns)_\(frameHash)"
        }
    }

    /// Bucket size (in points) used when hashing a container frame into a
    /// stable identifier. Round-to-nearest-8pt tolerates the minor layout
    /// drift produced by Auto Layout re-resolves, Dynamic Type rounding, and
    /// sub-pixel alignment, while still distinguishing visually distinct
    /// containers. 8pt aligns with UIKit's 8-point design grid, so a "same"
    /// container that shifts by a layout pass stays in the same bucket.
    private static let coarseFrameBucket: CGFloat = 8

    static func coarseFrameHash(_ frame: CGRect) -> String {
        let bucket = coarseFrameBucket
        let xCoord = safeInt((frame.origin.x.sanitizedForJSON / bucket).rounded())
        let yCoord = safeInt((frame.origin.y.sanitizedForJSON / bucket).rounded())
        let width = safeInt((frame.size.width.sanitizedForJSON / bucket).rounded())
        let height = safeInt((frame.size.height.sanitizedForJSON / bucket).rounded())
        return "\(xCoord)_\(yCoord)_\(width)_\(height)"
    }

    // MARK: - Build Screen From Parse

    /// Build a Screen value from a ParseResult. Pure: no mutable state.
    /// This is the lifted body of the old `apply(_:to:)` — heistId assignment
    /// (with content-position disambiguation), context resolution, container
    /// stable-id computation, and first-responder detection, all in one pass.
    static func buildScreen(from result: ParseResult) -> Screen {
        let contexts = buildElementContexts(
            hierarchy: result.hierarchy,
            scrollableContainerViews: result.scrollViews,
            elementObjects: result.objects
        )
        let identityContext = buildContainerIdentityContext(
            hierarchy: result.hierarchy,
            scrollableContainerViews: result.scrollViews
        )

        let baseHeistIds = TheStash.IdAssignment.assign(result.elements)
        let resolvedHeistIds = resolveHeistIds(
            base: baseHeistIds, elements: result.elements, contexts: contexts
        )

        var screenElements: [String: Screen.ScreenElement] = [:]
        screenElements.reserveCapacity(result.elements.count)
        var heistIdByElement: [AccessibilityElement: String] = [:]
        heistIdByElement.reserveCapacity(result.elements.count)
        for (parsedElement, heistId) in zip(result.elements, resolvedHeistIds) {
            let context = contexts[parsedElement]
            let entry = Screen.ScreenElement(
                heistId: heistId,
                contentSpaceOrigin: context?.contentSpaceOrigin,
                element: parsedElement,
                object: context?.object,
                scrollView: context?.scrollView
            )
            screenElements[heistId] = entry
            heistIdByElement[parsedElement] = heistId
        }

        let firstResponders = zip(result.elements, resolvedHeistIds).filter { element, _ in
            (result.objects[element] as? UIView)?.isFirstResponder == true
        }
        if firstResponders.count > 1 {
            insideJobLogger.warning("Multiple first responders detected: \(firstResponders.map(\.1).joined(separator: ", "))")
        }

        let containerStableIds = buildContainerStableIds(
            hierarchy: result.hierarchy,
            identityContext: identityContext,
            scrollableViews: result.scrollViews
        )

        let scrollableViewRefs = Dictionary(
            uniqueKeysWithValues: result.scrollViews.map { (container, view) in
                (container, Screen.ScrollableViewRef(view: view))
            }
        )

        return Screen(
            elements: screenElements,
            hierarchy: result.hierarchy,
            containerStableIds: containerStableIds,
            heistIdByElement: heistIdByElement,
            firstResponderHeistId: firstResponders.first?.1,
            scrollableContainerViews: scrollableViewRefs
        )
    }

    // MARK: - HeistId Disambiguation (in-parse only)

    /// Resolve a parallel-array of base heistIds, appending `_at_X_Y` content-
    /// space disambiguation when the same base id appears twice within a single
    /// parse with distinct content-space origins. Cross-parse disambiguation no
    /// longer exists — each parse is self-contained.
    private static func resolveHeistIds(
        base: [String],
        elements: [AccessibilityElement],
        contexts: [AccessibilityElement: ElementContext]
    ) -> [String] {
        var resolved: [String] = []
        resolved.reserveCapacity(base.count)
        var seen: [String: (element: AccessibilityElement, origin: CGPoint?)] = [:]

        for (heistId, element) in zip(base, elements) {
            let origin = contexts[element]?.contentSpaceOrigin
            guard let existing = seen[heistId] else {
                resolved.append(heistId)
                seen[heistId] = (element, origin)
                continue
            }

            if hasSameMinimumMatcher(existing.element, element),
               let origin,
               let existingOrigin = existing.origin,
               !sameOrigin(existingOrigin, origin) {
                let disambiguated = contentPositionHeistId(heistId, origin: origin)
                resolved.append(disambiguated)
                seen[disambiguated] = (element, origin)
                continue
            }

            // Fall back: take the base id (IdAssignment.assign already adds
            // `_N` suffixes for duplicates; if we're still seeing a collision
            // here it's because the prior pass collapsed unique elements).
            resolved.append(heistId)
        }

        return resolved
    }

    static func contentPositionHeistId(_ baseHeistId: String, origin: CGPoint) -> String {
        "\(baseHeistId)_at_\(safeInt(origin.x.rounded()))_\(safeInt(origin.y.rounded()))"
    }

    private static func hasSameMinimumMatcher(_ lhs: AccessibilityElement, _ rhs: AccessibilityElement) -> Bool {
        guard lhs.identifier == rhs.identifier,
              lhs.label == rhs.label,
              stableTraitNames(lhs.traits) == stableTraitNames(rhs.traits) else {
            return false
        }
        if lhs.identifier?.isEmpty == false || lhs.label?.isEmpty == false {
            return true
        }
        return lhs.value == rhs.value
    }

    private static func stableTraitNames(_ traits: UIAccessibilityTraits) -> Set<String> {
        Set(traits.traitNames).subtracting(AccessibilityPolicy.transientTraitNames)
    }

    private static func sameOrigin(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool {
        abs(lhs.x - rhs.x) < 0.5 && abs(lhs.y - rhs.y) < 0.5
    }

    // MARK: - Container StableId Index

    private static func buildContainerStableIds(
        hierarchy: [AccessibilityHierarchy],
        identityContext: ContainerIdentityContext,
        scrollableViews: [AccessibilityContainer: UIView]
    ) -> [AccessibilityContainer: String] {
        var result: [AccessibilityContainer: String] = [:]
        for container in hierarchy.containers {
            let contentFrame = identityContext.contentFrames[container] ?? container.frame
            let isNested = identityContext.nestedInScrollView.contains(container)
            let stableId = stableId(
                for: container,
                contentFrame: contentFrame,
                isNestedInScrollView: isNested,
                scrollableView: scrollableViews[container]
            )
            result[container] = stableId
        }
        return result
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
