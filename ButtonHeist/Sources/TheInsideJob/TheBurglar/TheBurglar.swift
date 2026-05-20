#if canImport(UIKit)
#if DEBUG
import CryptoKit
import UIKit

import TheScore

import AccessibilitySnapshotParser

/// The crew member who breaks in and takes what he finds.
///
/// TheBurglar reads the live accessibility tree and assigns heistIds. Pure
/// helpers — he has no mutable state. TheStash invokes
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
    /// The hierarchy is the source of element order; callers derive flat
    /// element lists from it instead of carrying a parallel array.
    struct ParseResult {
        let hierarchy: [AccessibilityHierarchy]
        let objects: [AccessibilityElement: NSObject]
        let objectsByPath: [TreePath: NSObject]
        let scrollViews: [AccessibilityContainer: UIView]
        let scrollViewsByPath: [TreePath: UIView]

        init(
            hierarchy: [AccessibilityHierarchy],
            objects: [AccessibilityElement: NSObject],
            objectsByPath: [TreePath: NSObject] = [:],
            scrollViews: [AccessibilityContainer: UIView],
            scrollViewsByPath: [TreePath: UIView] = [:]
        ) {
            self.hierarchy = hierarchy
            self.objects = objects
            self.objectsByPath = objectsByPath
            self.scrollViews = scrollViews
            self.scrollViewsByPath = scrollViewsByPath
        }
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

        var allHierarchy: [AccessibilityHierarchy] = []
        var allObjects: [AccessibilityElement: NSObject] = [:]
        var objectCandidates: [AccessibilityElement: [NSObject]] = [:]
        var scrollViewCandidates: [AccessibilityContainer: [UIView]] = [:]

        for (window, rootView) in windows {
            let containsModalBoundary = autoreleasepool { () -> Bool in
                var containsModalBoundary = false
                let windowTree = parser.parseAccessibilityHierarchy(
                    in: rootView,
                    rotorResultLimit: 0,
                    elementVisitor: { element, _, object in
                        allObjects[element] = object
                        objectCandidates[element, default: []].append(object)
                    },
                    containerVisitor: { container, object in
                        if case .scrollable = container.type, let view = object as? UIView {
                            scrollViewCandidates[container, default: []].append(view)
                        }
                        if container.isModalBoundary {
                            containsModalBoundary = true
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

                return containsModalBoundary
            }

            if containsModalBoundary {
                break
            }
        }

        let allScrollViewsByPath = Self.scrollViewsByPath(
            hierarchy: allHierarchy,
            scrollViewCandidates: scrollViewCandidates
        )
        let allObjectsByPath = Self.objectsByPath(
            hierarchy: allHierarchy,
            objectCandidates: objectCandidates
        )
        return ParseResult(
            hierarchy: allHierarchy,
            objects: allObjects,
            objectsByPath: allObjectsByPath,
            scrollViews: Self.scrollViewsByContainerForCurrentCapture(
                hierarchy: allHierarchy,
                scrollViewsByPath: allScrollViewsByPath
            ),
            scrollViewsByPath: allScrollViewsByPath
        )
    }

    /// Parse one live accessibility object by pumping it through the regular
    /// hierarchy parser with a temporary accessibility root. The object may be
    /// a custom rotor result that VoiceOver can focus even though it is not
    /// discoverable by walking the current app hierarchy.
    func parseObject(_ object: NSObject) -> AccessibilityElement? {
        let root = RotorResultParsingRoot(object: object)
        var parsedResult: AccessibilityElement?
        let hierarchy = parser.parseAccessibilityHierarchy(
            in: root,
            rotorResultLimit: 0,
            elementVisitor: { element, _, parsedObject in
                if parsedObject === object {
                    parsedResult = element
                }
            }
        )
        if let parsedResult {
            return parsedResult
        }
        return hierarchy.sortedElements.first
    }

    // MARK: - Container Content-Frame Building

    /// Walk the hierarchy tree to compute each container's frame expressed in
    /// the nearest enclosing scrollable's content space. Top-level containers
    /// (no enclosing scrollable) keep their screen-space frame.
    struct ContainerIdentityContext {
        let contentFrames: [AccessibilityContainer: CGRect]
        let contentFramesByPath: [TreePath: CGRect]
        let nestedInScrollView: Set<AccessibilityContainer>
    }

    static func buildContainerIdentityContext(
        hierarchy: [AccessibilityHierarchy],
        scrollableContainerViews: [AccessibilityContainer: UIView],
        scrollableContainerViewsByPath: [TreePath: UIView] = [:]
    ) -> ContainerIdentityContext {
        var contentFrames: [AccessibilityContainer: CGRect] = [:]
        var contentFramesByPath: [TreePath: CGRect] = [:]
        var nestedInScrollView = Set<AccessibilityContainer>()
        for (index, node) in hierarchy.enumerated() {
            collectContainerContentFrames(
                node: node,
                path: TreePath([index]),
                parentScrollView: nil,
                scrollableContainerViews: scrollableContainerViews,
                scrollableContainerViewsByPath: scrollableContainerViewsByPath,
                into: &contentFrames,
                byPath: &contentFramesByPath,
                nestedInScrollView: &nestedInScrollView
            )
        }
        return ContainerIdentityContext(
            contentFrames: contentFrames,
            contentFramesByPath: contentFramesByPath,
            nestedInScrollView: nestedInScrollView
        )
    }

    private static func collectContainerContentFrames(
        node: AccessibilityHierarchy,
        path: TreePath,
        parentScrollView: UIScrollView?,
        scrollableContainerViews: [AccessibilityContainer: UIView],
        scrollableContainerViewsByPath: [TreePath: UIView],
        into result: inout [AccessibilityContainer: CGRect],
        byPath pathResult: inout [TreePath: CGRect],
        nestedInScrollView: inout Set<AccessibilityContainer>
    ) {
        guard case .container(let container, let children) = node else { return }

        let frame = container.frame.cgRect
        let contentFrame: CGRect
        if let scrollView = parentScrollView, !frame.isNull, !frame.isEmpty {
            let origin = scrollView.convert(frame.origin, from: nil)
            contentFrame = CGRect(origin: origin, size: frame.size)
            nestedInScrollView.insert(container)
        } else {
            contentFrame = frame
        }
        result[container] = contentFrame
        pathResult[path] = contentFrame

        let childScrollView: UIScrollView?
        if let scrollView = scrollableContainerViewsByPath[path] as? UIScrollView
            ?? scrollableContainerViews[container] as? UIScrollView,
           !scrollView.bhIsUnsafeForProgrammaticScrolling {
            childScrollView = scrollView
        } else {
            childScrollView = parentScrollView
        }

        for (index, child) in children.enumerated() {
            collectContainerContentFrames(
                node: child,
                path: path.appending(index),
                parentScrollView: childScrollView,
                scrollableContainerViews: scrollableContainerViews,
                scrollableContainerViewsByPath: scrollableContainerViewsByPath,
                into: &result,
                byPath: &pathResult,
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

    private struct ElementObjectIndex {
        let byElement: [AccessibilityElement: NSObject]
        let byPath: [TreePath: NSObject]

        func object(for element: AccessibilityElement, path: TreePath) -> NSObject? {
            byPath[path] ?? byElement[element]
        }
    }

    /// Walk the hierarchy tree to gather per-element context: content-space origins,
    /// scroll view refs, and live element objects.
    static func buildElementContexts(
        hierarchy: [AccessibilityHierarchy],
        scrollableContainerViews: [AccessibilityContainer: UIView],
        scrollableContainerViewsByPath: [TreePath: UIView] = [:],
        elementObjects: [AccessibilityElement: NSObject],
        elementObjectsByPath: [TreePath: NSObject] = [:]
    ) -> [AccessibilityElement: ElementContext] {
        let byPath = buildElementContextsByPath(
            hierarchy: hierarchy,
            scrollableContainerViews: scrollableContainerViews,
            scrollableContainerViewsByPath: scrollableContainerViewsByPath,
            elementObjects: elementObjects,
            elementObjectsByPath: elementObjectsByPath
        )
        return Dictionary(
            byPath.compactMap { path, context in
                guard case .element(let element, _) = hierarchy.node(at: path) else { return nil }
                return (element, context)
            },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    static func buildElementContextsByPath(
        hierarchy: [AccessibilityHierarchy],
        scrollableContainerViews: [AccessibilityContainer: UIView],
        scrollableContainerViewsByPath: [TreePath: UIView] = [:],
        elementObjects: [AccessibilityElement: NSObject],
        elementObjectsByPath: [TreePath: NSObject] = [:]
    ) -> [TreePath: ElementContext] {
        var contexts: [AccessibilityElement: ElementContext] = [:]
        var contextsByPath: [TreePath: ElementContext] = [:]
        let objectIndex = ElementObjectIndex(byElement: elementObjects, byPath: elementObjectsByPath)
        for (index, node) in hierarchy.enumerated() {
            collectElementContexts(
                node: node,
                path: TreePath([index]),
                parentScrollView: nil,
                scrollableContainerViews: scrollableContainerViews,
                scrollableContainerViewsByPath: scrollableContainerViewsByPath,
                objectIndex: objectIndex,
                into: &contexts,
                byPath: &contextsByPath
            )
        }
        return contextsByPath
    }

    private static func collectElementContexts(
        node: AccessibilityHierarchy,
        path: TreePath,
        parentScrollView: UIScrollView?,
        scrollableContainerViews: [AccessibilityContainer: UIView],
        scrollableContainerViewsByPath: [TreePath: UIView],
        objectIndex: ElementObjectIndex,
        into contexts: inout [AccessibilityElement: ElementContext],
        byPath contextsByPath: inout [TreePath: ElementContext]
    ) {
        switch node {
        case .element(let element, _):
            let origin: CGPoint? = parentScrollView.flatMap { scrollView in
                let frame = element.shape.frame
                return (!frame.isNull && !frame.isEmpty)
                    ? scrollView.convert(frame.origin, from: nil)
                    : nil
            }
            let context = ElementContext(
                contentSpaceOrigin: origin,
                scrollView: parentScrollView,
                object: objectIndex.object(for: element, path: path)
            )
            contexts[element] = context
            contextsByPath[path] = context
        case .container(let container, let children):
            let childScrollView: UIScrollView?
            if let scrollView = scrollableContainerViewsByPath[path] as? UIScrollView
                ?? scrollableContainerViews[container] as? UIScrollView,
               !scrollView.bhIsUnsafeForProgrammaticScrolling {
                childScrollView = scrollView
            } else {
                childScrollView = parentScrollView
            }

            for (index, child) in children.enumerated() {
                collectElementContexts(
                    node: child,
                    path: path.appending(index),
                    parentScrollView: childScrollView,
                    scrollableContainerViews: scrollableContainerViews,
                    scrollableContainerViewsByPath: scrollableContainerViewsByPath,
                    objectIndex: objectIndex,
                    into: &contexts,
                    byPath: &contextsByPath
                )
            }
        }
    }

    // MARK: - Stable Container Identity

    /// Compute a readable handle prefix for a parser container, derived from
    /// its own exposed values. Container handles are capture-local tree
    /// projections; `buildContainerStableIdIndex` appends a deterministic
    /// subtree hash when multiple containers share this prefix in one parse.
    static func stableId(
        for container: AccessibilityContainer,
        contentFrame: CGRect
    ) -> String {
        let frameHash = coarseFrameHash(contentFrame)
        switch container.type {
        case .scrollable:
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
        let indexedElements = result.hierarchy.pathIndexedElements
        let elements = indexedElements.map(\.element)
        let contextsByPath = buildElementContextsByPath(
            hierarchy: result.hierarchy,
            scrollableContainerViews: result.scrollViews,
            scrollableContainerViewsByPath: result.scrollViewsByPath,
            elementObjects: result.objects,
            elementObjectsByPath: result.objectsByPath
        )
        let identityContext = buildContainerIdentityContext(
            hierarchy: result.hierarchy,
            scrollableContainerViews: result.scrollViews,
            scrollableContainerViewsByPath: result.scrollViewsByPath
        )

        let baseHeistIds = TheStash.IdAssignment.assign(elements)
        let resolvedHeistIds = resolveHeistIds(
            base: baseHeistIds,
            elements: elements,
            origins: indexedElements.map { contextsByPath[$0.path]?.contentSpaceOrigin }
        )

        var screenElements: [HeistId: Screen.ScreenElement] = [:]
        screenElements.reserveCapacity(elements.count)
        var heistIdByElement: [AccessibilityElement: HeistId] = [:]
        heistIdByElement.reserveCapacity(elements.count)
        var heistIdByElementPath: [TreePath: HeistId] = [:]
        heistIdByElementPath.reserveCapacity(elements.count)
        var elementRefs: [HeistId: Screen.ElementRef] = [:]
        elementRefs.reserveCapacity(elements.count)
        for ((parsedElement, path, _), heistId) in zip(indexedElements, resolvedHeistIds) {
            let context = contextsByPath[path]
            let entry = Screen.ScreenElement(
                heistId: heistId,
                contentSpaceOrigin: context?.contentSpaceOrigin,
                element: parsedElement
            )
            screenElements[heistId] = entry
            heistIdByElement[parsedElement] = heistId
            heistIdByElementPath[path] = heistId
            elementRefs[heistId] = Screen.ElementRef(
                object: context?.object,
                scrollView: context?.scrollView
            )
        }

        let firstResponders = zip(indexedElements, resolvedHeistIds).filter { item, _ in
            (contextsByPath[item.path]?.object as? UIView)?.isFirstResponder == true
        }
        if firstResponders.count > 1 {
            insideJobLogger.warning("Multiple first responders detected: \(firstResponders.map(\.1).joined(separator: ", "))")
        }

        let containerStableIdIndex = buildContainerStableIdIndex(
            hierarchy: result.hierarchy,
            identityContext: identityContext
        )
        let containerStableIds = containerStableIdIndex.byContainer
        let containerStableIdsByPath = containerStableIdIndex.byPath

        let scrollableViewRefs = result.scrollViews.mapValues { Screen.ScrollableViewRef(view: $0) }
        let scrollableViewRefsByPath = result.scrollViewsByPath.mapValues {
            Screen.ScrollableViewRef(view: $0)
        }
        return Screen(
            elements: screenElements,
            hierarchy: result.hierarchy,
            containerStableIds: containerStableIds,
            containerStableIdsByPath: containerStableIdsByPath,
            heistIdByElement: heistIdByElement,
            heistIdByElementPath: heistIdByElementPath,
            elementRefs: elementRefs,
            firstResponderHeistId: firstResponders.first?.1,
            scrollableContainerViews: scrollableViewRefs,
            scrollableContainerViewsByPath: scrollableViewRefsByPath
        )
    }

    private static func objectsByPath(
        hierarchy: [AccessibilityHierarchy],
        objectCandidates: [AccessibilityElement: [NSObject]]
    ) -> [TreePath: NSObject] {
        var consumedCounts: [AccessibilityElement: Int] = [:]
        var result: [TreePath: NSObject] = [:]
        for (element, path, _) in hierarchy.pathIndexedElements {
            let nextIndex = consumedCounts[element, default: 0]
            if let objects = objectCandidates[element], objects.indices.contains(nextIndex) {
                result[path] = objects[nextIndex]
            }
            consumedCounts[element] = nextIndex + 1
        }
        return result
    }

    private static func scrollViewsByPath(
        hierarchy: [AccessibilityHierarchy],
        scrollViewCandidates: [AccessibilityContainer: [UIView]]
    ) -> [TreePath: UIView] {
        var consumedCounts: [AccessibilityContainer: Int] = [:]
        var result: [TreePath: UIView] = [:]
        for (container, path) in parserVisitorScrollableContainerPaths(hierarchy: hierarchy) {
            let nextIndex = consumedCounts[container, default: 0]
            if let views = scrollViewCandidates[container], views.indices.contains(nextIndex) {
                result[path] = views[nextIndex]
            }
            consumedCounts[container] = nextIndex + 1
        }
        return result
    }

    private static func parserVisitorScrollableContainerPaths(
        hierarchy: [AccessibilityHierarchy]
    ) -> [(container: AccessibilityContainer, path: TreePath)] {
        hierarchy.enumerated().flatMap { index, node in
            parserVisitorScrollableContainerPaths(node: node, path: TreePath([index]))
        }
    }

    private static func parserVisitorScrollableContainerPaths(
        node: AccessibilityHierarchy,
        path: TreePath
    ) -> [(container: AccessibilityContainer, path: TreePath)] {
        guard case .container(let container, let children) = node else { return [] }

        var result = children.enumerated().flatMap { index, child in
            parserVisitorScrollableContainerPaths(node: child, path: path.appending(index))
        }
        if container.isScrollable {
            result.append((container, path))
        }
        return result
    }

    private static func scrollViewsByContainerForCurrentCapture(
        hierarchy: [AccessibilityHierarchy],
        scrollViewsByPath: [TreePath: UIView]
    ) -> [AccessibilityContainer: UIView] {
        var result: [AccessibilityContainer: UIView] = [:]
        for (container, path) in hierarchy.containerPaths where container.isScrollable {
            guard result[container] == nil, let view = scrollViewsByPath[path] else { continue }
            result[container] = view
        }
        return result
    }

    // MARK: - HeistId Disambiguation (in-parse only)

    /// Resolve a parallel-array of base heistIds, appending `_at_X_Y` content-
    /// space disambiguation when the same base id appears twice within a single
    /// parse with distinct content-space origins. Cross-parse disambiguation no
    /// longer exists — each parse is self-contained.
    private static func resolveHeistIds(
        base: [String],
        elements: [AccessibilityElement],
        origins: [CGPoint?]
    ) -> [String] {
        var resolved: [String] = []
        resolved.reserveCapacity(base.count)
        var seen: [String: (element: AccessibilityElement, origin: CGPoint?)] = [:]

        for ((heistId, element), origin) in zip(zip(base, elements), origins) {
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

    static func contentPositionHeistId(_ baseHeistId: HeistId, origin: CGPoint) -> HeistId {
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

    private static func stableTraitNames(_ traits: AccessibilityTraits) -> Set<String> {
        Set(traits.traitNames).subtracting(AccessibilityPolicy.transientTraitNames)
    }

    private static func sameOrigin(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool {
        abs(lhs.x - rhs.x) < 0.5 && abs(lhs.y - rhs.y) < 0.5
    }

    // MARK: - Container StableId Index

    private static func buildContainerStableIdIndex(
        hierarchy: [AccessibilityHierarchy],
        identityContext: ContainerIdentityContext
    ) -> ContainerStableIdIndex {
        let candidates = hierarchy.compactMapSubtrees { node, path -> ContainerStableIdCandidate? in
            guard case .container(let container, _) = node else { return nil }
            let contentFrame = identityContext.contentFramesByPath[path]
                ?? identityContext.contentFrames[container]
                ?? container.frame.cgRect
            let readableName = stableId(
                for: container,
                contentFrame: contentFrame
            )
            return ContainerStableIdCandidate(
                path: path,
                container: container,
                node: node,
                readableName: readableName
            )
        }

        let duplicateReadableNames = Set(
            Dictionary(grouping: candidates, by: \.readableName)
                .filter { $0.value.count > 1 }
                .keys
        )

        var byContainer: [AccessibilityContainer: HeistContainer] = [:]
        var byPath: [TreePath: HeistContainer] = [:]
        for candidate in candidates {
            let stableId: HeistContainer
            if duplicateReadableNames.contains(candidate.readableName) {
                stableId = captureLocalContainerId(
                    readableName: candidate.readableName,
                    node: candidate.node,
                    path: candidate.path
                )
            } else {
                stableId = candidate.readableName
            }
            byContainer[candidate.container] = stableId
            byPath[candidate.path] = stableId
        }
        return ContainerStableIdIndex(byContainer: byContainer, byPath: byPath)
    }

    static func captureLocalContainerId(
        readableName: HeistContainer,
        node: AccessibilityHierarchy,
        path: TreePath
    ) -> HeistContainer {
        "\(readableName)-\(containerHash(node: node, path: path))"
    }

    private static func containerHash(node: AccessibilityHierarchy, path: TreePath) -> String {
        let payload = ContainerIdentityPayload(path: path.indices, subtree: node)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(payload))
            ?? Data("\(path.indices)|\(String(describing: node))".utf8)
        return SHA256.hash(data: data).prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    private struct ContainerStableIdCandidate {
        let path: TreePath
        let container: AccessibilityContainer
        let node: AccessibilityHierarchy
        let readableName: HeistContainer
    }

    private struct ContainerStableIdIndex {
        let byContainer: [AccessibilityContainer: HeistContainer]
        let byPath: [TreePath: HeistContainer]
    }

    private struct ContainerIdentityPayload: Encodable {
        let path: [Int]
        let subtree: AccessibilityHierarchy
    }

}

private final class RotorResultParsingRoot: UIView {
    private let rotorResultObject: NSObject

    init(object: NSObject) {
        self.rotorResultObject = object
        super.init(frame: ScreenMetrics.current.bounds)
        isAccessibilityElement = false
        accessibilityElements = [rotorResultObject]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }
}

private extension Array where Element == AccessibilityHierarchy {
    func node(at path: TreePath) -> AccessibilityHierarchy? {
        guard let rootIndex = path.indices.first,
              indices.contains(rootIndex)
        else { return nil }
        guard path.indices.count > 1 else { return self[rootIndex] }
        return self[rootIndex].node(at: TreePath([Int](path.indices.dropFirst())))
    }
}

private extension AccessibilityHierarchy {
    func node(at path: TreePath) -> AccessibilityHierarchy? {
        guard !path.indices.isEmpty else { return self }
        guard case .container(_, let children) = self,
              let childIndex = path.indices.first,
              children.indices.contains(childIndex)
        else { return nil }
        return children[childIndex].node(at: TreePath([Int](path.indices.dropFirst())))
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
