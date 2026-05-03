#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

// MARK: - Stable Container Identity

extension TheStash.ElementRegistry {

    /// Compute a stable identifier for a parser container. Identifiers persist
    /// across parses so the registry tree can survive frame drift, content
    /// size changes, and viewport-trimmed reparses.
    ///
    /// Strategy by container type:
    /// - `.scrollable`: object identity via the live scroll view ref. The same
    ///   `UIScrollView` produces the same id across parses regardless of frame
    ///   or content size shifts.
    /// - `.semanticGroup`: derived from label/value/identifier. Two semantic
    ///   groups with identical metadata collapse to the same id (acceptable;
    ///   they're indistinguishable to users too).
    /// - `.list` / `.landmark` / `.tabBar` / `.dataTable`: a coarse-frame hash
    ///   plus the heistId of the first child anchors topology. Heuristic;
    ///   collisions degrade to "merged into one node" rather than a crash.
    static func stableId(
        for container: AccessibilityContainer,
        scrollableViews: [AccessibilityContainer: UIView],
        firstChildHeistId: String?
    ) -> String {
        switch container.type {
        case .scrollable:
            if let view = scrollableViews[container] {
                let oid = ObjectIdentifier(view)
                return "scrollable_\(String(oid.hashValue, radix: 16))"
            }
            return "scrollable_\(coarseFrameHash(container.frame))_\(firstChildHeistId ?? "anon")"

        case .semanticGroup(let label, let value, let identifier):
            let labelSlug = TheScore.slugify(label) ?? "anon"
            let valueSlug = TheScore.slugify(value) ?? ""
            let identifierSlug = identifier ?? ""
            return "semantic_\(identifierSlug)_\(labelSlug)_\(valueSlug)"

        case .list:
            return "list_\(coarseFrameHash(container.frame))_\(firstChildHeistId ?? "anon")"

        case .landmark:
            return "landmark_\(coarseFrameHash(container.frame))_\(firstChildHeistId ?? "anon")"

        case .tabBar:
            return "tabBar_\(coarseFrameHash(container.frame))_\(firstChildHeistId ?? "anon")"

        case .dataTable(let rows, let columns):
            return "table_\(rows)x\(columns)_\(coarseFrameHash(container.frame))_\(firstChildHeistId ?? "anon")"
        }
    }

    /// Quantize a frame to 8-pt cells before hashing so minor layout shifts
    /// don't break container identity. Collisions are acceptable here:
    /// a colliding hash is OK because the type tag and first-child heistId
    /// both participate in the final stableId.
    private static func coarseFrameHash(_ frame: CGRect) -> String {
        let x = Int((frame.origin.x / 8).rounded())
        let y = Int((frame.origin.y / 8).rounded())
        let width = Int((frame.size.width / 8).rounded())
        let height = Int((frame.size.height / 8).rounded())
        return "\(x)_\(y)_\(width)_\(height)"
    }

    // MARK: - Merge

    /// Merge a freshly parsed accessibility hierarchy into the persistent
    /// registry tree.
    ///
    /// The merge is a pure pipeline: we capture orphans from the old tree,
    /// build a fresh tree from the incoming hierarchy, attach orphans under
    /// their previous container, sort scrollable children by content-space Y,
    /// prune empty containers, and rebuild the heistId index. Each step is a
    /// total function from `[RegistryNode]` to `[RegistryNode]`, so the final
    /// state depends only on inputs.
    ///
    /// Live elements update in place (new `AccessibilityElement` payload, new
    /// UIKit context); absent elements are retained at their last known
    /// position; novel elements and containers are inserted; emptied
    /// containers are pruned.
    mutating func merge(
        hierarchy: [AccessibilityHierarchy],
        heistIds: [AccessibilityElement: String],
        contexts: [AccessibilityElement: TheStash.ElementContext],
        scrollableViews: [AccessibilityContainer: UIView]
    ) {
        let oldRoots = roots
        let oldIndex = elementByHeistId
        let liveHeistIds = Set(heistIds.values)
        let orphans = Self.collectOrphans(roots: oldRoots, liveHeistIds: liveHeistIds)

        let built = Self.buildNodes(
            hierarchy: hierarchy,
            heistIds: heistIds,
            contexts: contexts,
            scrollableViews: scrollableViews,
            oldIndex: oldIndex,
            oldRoots: oldRoots
        )
        let attached = Self.attachOrphans(roots: built, orphans: orphans)
        let sorted = Self.sortScrollableChildren(roots: attached)
        let pruned = Self.pruneEmptyContainers(roots: sorted)

        roots = pruned
        elementByHeistId = Self.buildIndex(roots: pruned)
    }

    /// Walk the tree and return all leaf elements in depth-first traversal order.
    func flattenElements() -> [TheStash.ScreenElement] {
        roots.flatMap { $0.flattenElements() }
    }

    /// O(1) lookup by heistId via `elementByHeistId`.
    func findElement(heistId: String) -> TheStash.ScreenElement? {
        guard let path = elementByHeistId[heistId] else { return nil }
        return Self.element(at: path, in: roots)
    }

    /// Walk `roots` and remove any leaf whose heistId is not in `keeping`.
    /// Containers with no element descendants after pruning are also removed.
    mutating func pruneTree(keeping: Set<String>) {
        let pruned = Self.prune(roots: roots, keeping: keeping)
        roots = pruned
        elementByHeistId = Self.buildIndex(roots: pruned)
    }

    // MARK: - Orphan Collection

    private struct Orphan {
        let element: TheStash.ScreenElement
        /// stableId of the immediate container ancestor in the old tree.
        /// nil if the orphan was at root level.
        let parentStableId: String?
    }

    private static func collectOrphans(
        roots: [TheStash.RegistryNode], liveHeistIds: Set<String>
    ) -> [Orphan] {
        roots.flatMap { collectOrphans(node: $0, parentStableId: nil, liveHeistIds: liveHeistIds) }
    }

    private static func collectOrphans(
        node: TheStash.RegistryNode,
        parentStableId: String?,
        liveHeistIds: Set<String>
    ) -> [Orphan] {
        switch node {
        case .element(let element):
            return liveHeistIds.contains(element.heistId)
                ? []
                : [Orphan(element: element, parentStableId: parentStableId)]
        case .container(let entry, let children):
            return children.flatMap {
                collectOrphans(node: $0, parentStableId: entry.stableId, liveHeistIds: liveHeistIds)
            }
        }
    }

    // MARK: - Build Tree from Hierarchy

    private static func buildNodes(
        hierarchy: [AccessibilityHierarchy],
        heistIds: [AccessibilityElement: String],
        contexts: [AccessibilityElement: TheStash.ElementContext],
        scrollableViews: [AccessibilityContainer: UIView],
        oldIndex: [String: TheStash.RegistryPath],
        oldRoots: [TheStash.RegistryNode]
    ) -> [TheStash.RegistryNode] {
        hierarchy.compactMap { hier in
            buildNode(
                hier: hier, heistIds: heistIds, contexts: contexts,
                scrollableViews: scrollableViews, oldIndex: oldIndex, oldRoots: oldRoots
            )
        }
    }

    private static func buildNode(
        hier: AccessibilityHierarchy,
        heistIds: [AccessibilityElement: String],
        contexts: [AccessibilityElement: TheStash.ElementContext],
        scrollableViews: [AccessibilityContainer: UIView],
        oldIndex: [String: TheStash.RegistryPath],
        oldRoots: [TheStash.RegistryNode]
    ) -> TheStash.RegistryNode? {
        switch hier {
        case .element(let parsedElement, _):
            guard let heistId = heistIds[parsedElement] else { return nil }
            let context = contexts[parsedElement]
            let priorOrigin: CGPoint? = oldIndex[heistId].flatMap { path in
                Self.element(at: path, in: oldRoots)?.contentSpaceOrigin
            }
            let screenElement = TheStash.ScreenElement(
                heistId: heistId,
                contentSpaceOrigin: context?.contentSpaceOrigin ?? priorOrigin,
                element: parsedElement,
                object: context?.object,
                scrollView: context?.scrollView
            )
            return .element(screenElement)

        case .container(let container, let children):
            let childNodes = children.compactMap { child in
                buildNode(
                    hier: child, heistIds: heistIds, contexts: contexts,
                    scrollableViews: scrollableViews, oldIndex: oldIndex, oldRoots: oldRoots
                )
            }
            let firstChild = firstHeistId(in: childNodes)
            let stableId = Self.stableId(
                for: container, scrollableViews: scrollableViews, firstChildHeistId: firstChild
            )
            let entry = TheStash.RegistryContainerEntry(stableId: stableId, container: container)
            return .container(entry, children: childNodes)
        }
    }

    private static func firstHeistId(in nodes: [TheStash.RegistryNode]) -> String? {
        for node in nodes {
            switch node {
            case .element(let element):
                return element.heistId
            case .container(_, let children):
                if let id = firstHeistId(in: children) { return id }
            }
        }
        return nil
    }

    // MARK: - Orphan Attachment (pure)

    private static func attachOrphans(
        roots: [TheStash.RegistryNode], orphans: [Orphan]
    ) -> [TheStash.RegistryNode] {
        orphans.reduce(roots) { acc, orphan in
            attach(roots: acc, orphan: orphan)
        }
    }

    private static func attach(
        roots: [TheStash.RegistryNode], orphan: Orphan
    ) -> [TheStash.RegistryNode] {
        let orphanNode = TheStash.RegistryNode.element(orphan.element)
        if let parentStableId = orphan.parentStableId,
           let attached = attachInside(roots: roots, parentStableId: parentStableId, child: orphanNode) {
            return attached
        }
        return roots + [orphanNode]
    }

    /// Walk the tree looking for a container with `parentStableId` and append
    /// `child` to its children. Returns the new tree on first match, nil if
    /// no matching container was found.
    private static func attachInside(
        roots: [TheStash.RegistryNode],
        parentStableId: String,
        child: TheStash.RegistryNode
    ) -> [TheStash.RegistryNode]? {
        for index in roots.indices {
            switch roots[index] {
            case .element:
                continue
            case .container(let entry, let children):
                if entry.stableId == parentStableId {
                    var copy = roots
                    copy[index] = .container(entry, children: children + [child])
                    return copy
                }
                if let updatedChildren = attachInside(
                    roots: children, parentStableId: parentStableId, child: child
                ) {
                    var copy = roots
                    copy[index] = .container(entry, children: updatedChildren)
                    return copy
                }
            }
        }
        return nil
    }

    // MARK: - Scrollable Reordering (pure)

    /// Sort the children of every `.scrollable` container by content-space Y so
    /// off-screen orphans interleave with visible siblings. Non-scrollable
    /// containers preserve incoming order.
    private static func sortScrollableChildren(
        roots: [TheStash.RegistryNode]
    ) -> [TheStash.RegistryNode] {
        roots.map { node in
            switch node {
            case .element:
                return node
            case .container(let entry, let children):
                let sortedChildren = sortScrollableChildren(roots: children)
                if case .scrollable = entry.container.type {
                    return .container(entry, children: sortedChildren.sorted(by: scrollableChildOrder))
                }
                return .container(entry, children: sortedChildren)
            }
        }
    }

    private static func scrollableChildOrder(
        _ lhs: TheStash.RegistryNode, _ rhs: TheStash.RegistryNode
    ) -> Bool {
        let lhsY = firstY(of: lhs)
        let rhsY = firstY(of: rhs)
        if lhsY != rhsY { return lhsY < rhsY }
        let lhsId = firstHeistId(in: [lhs]) ?? ""
        let rhsId = firstHeistId(in: [rhs]) ?? ""
        return lhsId < rhsId
    }

    private static func firstY(of node: TheStash.RegistryNode) -> CGFloat {
        switch node {
        case .element(let element):
            if let origin = element.contentSpaceOrigin { return origin.y }
            return element.element.shape.frame.origin.y
        case .container(let entry, let children):
            return children.map { firstY(of: $0) }.min() ?? entry.container.frame.origin.y
        }
    }

    // MARK: - Empty Container Pruning (pure)

    private static func pruneEmptyContainers(
        roots: [TheStash.RegistryNode]
    ) -> [TheStash.RegistryNode] {
        roots.compactMap { node in
            switch node {
            case .element:
                return node
            case .container(let entry, let children):
                let pruned = pruneEmptyContainers(roots: children)
                return pruned.isEmpty ? nil : .container(entry, children: pruned)
            }
        }
    }

    // MARK: - Prune by Allowlist (pure)

    private static func prune(
        roots: [TheStash.RegistryNode], keeping: Set<String>
    ) -> [TheStash.RegistryNode] {
        roots.compactMap { node in
            switch node {
            case .element(let element):
                return keeping.contains(element.heistId) ? node : nil
            case .container(let entry, let children):
                let pruned = prune(roots: children, keeping: keeping)
                return pruned.isEmpty ? nil : .container(entry, children: pruned)
            }
        }
    }

    // MARK: - Index and Path Walks

    /// Resolve a `RegistryPath` to its leaf element, returning nil if the path
    /// does not reach a leaf or is otherwise invalid.
    static func element(
        at path: TheStash.RegistryPath, in roots: [TheStash.RegistryNode]
    ) -> TheStash.ScreenElement? {
        guard let firstIndex = path.first, roots.indices.contains(firstIndex) else { return nil }
        let node = roots[firstIndex]
        let rest = Array(path.dropFirst())
        switch node {
        case .element(let element):
            return rest.isEmpty ? element : nil
        case .container(_, let children):
            return rest.isEmpty ? nil : element(at: rest, in: children)
        }
    }

    private static func buildIndex(
        roots: [TheStash.RegistryNode]
    ) -> [String: TheStash.RegistryPath] {
        var index: [String: TheStash.RegistryPath] = [:]
        for (idx, root) in roots.enumerated() {
            buildIndex(node: root, path: [idx], into: &index)
        }
        return index
    }

    private static func buildIndex(
        node: TheStash.RegistryNode,
        path: TheStash.RegistryPath,
        into index: inout [String: TheStash.RegistryPath]
    ) {
        switch node {
        case .element(let element):
            index[element.heistId] = path
        case .container(_, let children):
            for (childIdx, child) in children.enumerated() {
                buildIndex(node: child, path: path + [childIdx], into: &index)
            }
        }
    }

    // MARK: - Invariant Checking (debug)

    /// Validate every internal invariant. Returns the first violation as a
    /// human-readable string, or nil if the registry is consistent.
    /// Invariants:
    /// 1. Every `elementByHeistId` entry resolves to a leaf with the matching heistId.
    /// 2. Every leaf in `roots` appears in `elementByHeistId`.
    /// 3. No heistId appears more than once in `roots`.
    /// 4. Every container has at least one element descendant.
    func validateInvariants() -> String? {
        for (heistId, path) in elementByHeistId {
            guard let element = Self.element(at: path, in: roots) else {
                return "elementByHeistId[\(heistId)] points to invalid path \(path)"
            }
            guard element.heistId == heistId else {
                return "elementByHeistId[\(heistId)] resolves to element \(element.heistId)"
            }
        }

        let leafHeistIds = flattenElements().map(\.heistId)
        for heistId in leafHeistIds where elementByHeistId[heistId] == nil {
            return "Element \(heistId) in tree but missing from elementByHeistId"
        }

        let counts = leafHeistIds.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        for (heistId, count) in counts where count > 1 {
            return "Duplicate heistId \(heistId) appears \(count) times in tree"
        }

        for (index, root) in roots.enumerated() {
            if let violation = validateContainersHaveDescendants(root) {
                return "root[\(index)]: \(violation)"
            }
        }

        return nil
    }

    private func validateContainersHaveDescendants(_ node: TheStash.RegistryNode) -> String? {
        switch node {
        case .element:
            return nil
        case .container(let entry, let children):
            if children.isEmpty {
                return "container \(entry.stableId) has no children"
            }
            for child in children {
                if let violation = validateContainersHaveDescendants(child) {
                    return violation
                }
            }
            return nil
        }
    }
}

// MARK: - Node Walks

extension TheStash.RegistryNode {

    /// Depth-first walk yielding every element leaf descendant.
    func flattenElements() -> [TheStash.ScreenElement] {
        switch self {
        case .element(let element):
            return [element]
        case .container(_, let children):
            return children.flatMap { $0.flattenElements() }
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
