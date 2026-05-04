#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

// MARK: - Stable Container Identity

extension TheStash.ElementRegistry {

    /// Compute a stable identifier for a parser container, derived from its
    /// own exposed values. Identifiers persist across parses so the registry
    /// tree can survive frame drift, content size changes, and
    /// viewport-trimmed reparses.
    ///
    /// `contentFrame` is the container's frame expressed in the nearest
    /// enclosing scrollable's content space (or screen space for top-level
    /// containers) — TheBurglar computes it during the parse walk. Using the
    /// content-space frame means a container nested in a scroll view keeps
    /// its identity as the outer view scrolls, and reusable cell-embedded
    /// containers at distinct logical positions get distinct ids.
    ///
    /// Strategy by container type:
    /// - `.semanticGroup`: derived from label/value/identifier slugs only.
    ///   Frame is irrelevant — the metadata IS the identity.
    /// - Top-level `.scrollable`: object identity via the live scroll view ref
    ///   so normal screen-space frame drift does not detach retained children.
    /// - Nested `.scrollable`: type tag plus coarse content-frame hash, so
    ///   cell-reused inner scroll views at different logical positions do not
    ///   collapse into one container.
    /// - `.list` / `.landmark` / `.tabBar`: type tag plus a coarse
    ///   content-frame hash.
    /// - `.dataTable`: type tag plus row/column counts plus content-frame
    ///   hash.
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

    /// Quantize a frame to 8-pt cells before hashing so minor layout shifts
    /// don't break container identity. NaN/infinity coordinates (e.g. from
    /// UIPickerView's 3D-transformed cells) are sanitized to 0 to keep the
    /// hash a total function.
    private static func coarseFrameHash(_ frame: CGRect) -> String {
        let x = Int((frame.origin.x.sanitizedForJSON / 8).rounded())
        let y = Int((frame.origin.y.sanitizedForJSON / 8).rounded())
        let width = Int((frame.size.width.sanitizedForJSON / 8).rounded())
        let height = Int((frame.size.height.sanitizedForJSON / 8).rounded())
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
        containerContentFrames: [AccessibilityContainer: CGRect],
        containersNestedInScrollView: Set<AccessibilityContainer> = [],
        scrollableViews: [AccessibilityContainer: UIView] = [:]
    ) {
        let oldRoots = roots
        let oldIndex = elementByHeistId
        let liveHeistIds = Set(heistIds.values)
        let orphans = Self.collectOrphans(roots: oldRoots, liveHeistIds: liveHeistIds)

        let built = Self.buildNodes(
            hierarchy: hierarchy,
            heistIds: heistIds,
            contexts: contexts,
            containerContentFrames: containerContentFrames,
            containersNestedInScrollView: containersNestedInScrollView,
            scrollableViews: scrollableViews,
            oldIndex: oldIndex,
            oldRoots: oldRoots
        )
        let attached = Self.attachOrphans(roots: built, orphans: orphans)
        let sorted = Self.sortContainerChildren(roots: attached, liveHeistIds: liveHeistIds)
        let pruned = Self.pruneEmptyContainers(roots: sorted)

        roots = pruned
        elementByHeistId = Self.buildIndex(roots: pruned)
    }

    /// Walk the tree and return all leaf elements in depth-first traversal order.
    func flattenElements() -> [TheStash.ScreenElement] {
        var collected: [TheStash.ScreenElement] = []
        Self.collectLeaves(roots, into: &collected)
        return collected
    }

    private static func collectLeaves(
        _ nodes: [TheStash.RegistryNode],
        into collected: inout [TheStash.ScreenElement]
    ) {
        for node in nodes {
            switch node {
            case .element(let element):
                collected.append(element)
            case .container(_, let children):
                collectLeaves(children, into: &collected)
            }
        }
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
        containerContentFrames: [AccessibilityContainer: CGRect],
        containersNestedInScrollView: Set<AccessibilityContainer>,
        scrollableViews: [AccessibilityContainer: UIView],
        oldIndex: [String: TheStash.RegistryPath],
        oldRoots: [TheStash.RegistryNode]
    ) -> [TheStash.RegistryNode] {
        hierarchy.compactMap { hier in
            buildNode(
                hier: hier, heistIds: heistIds, contexts: contexts,
                containerContentFrames: containerContentFrames,
                containersNestedInScrollView: containersNestedInScrollView,
                scrollableViews: scrollableViews,
                oldIndex: oldIndex, oldRoots: oldRoots
            )
        }
    }

    private static func buildNode(
        hier: AccessibilityHierarchy,
        heistIds: [AccessibilityElement: String],
        contexts: [AccessibilityElement: TheStash.ElementContext],
        containerContentFrames: [AccessibilityContainer: CGRect],
        containersNestedInScrollView: Set<AccessibilityContainer>,
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
                    containerContentFrames: containerContentFrames,
                    containersNestedInScrollView: containersNestedInScrollView,
                    scrollableViews: scrollableViews,
                    oldIndex: oldIndex, oldRoots: oldRoots
                )
            }
            let contentFrame = containerContentFrames[container] ?? container.frame
            let stableId = Self.stableId(
                for: container,
                contentFrame: contentFrame,
                isNestedInScrollView: containersNestedInScrollView.contains(container),
                scrollableView: scrollableViews[container]
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

    // MARK: - Retained Child Reordering (pure)

    /// Sort retained children back into a useful position after orphan
    /// attachment. Scrollables use content-space order; non-scrollable
    /// containers keep parser order unless they gained retained children, in
    /// which case screen-space order prevents old entries from being appended
    /// after their live siblings.
    private static func sortContainerChildren(
        roots: [TheStash.RegistryNode],
        liveHeistIds: Set<String>
    ) -> [TheStash.RegistryNode] {
        roots.mapTree(
            onElement: { .element($0) },
            onContainer: { entry, children in
                if case .scrollable = entry.container.type {
                    return .container(entry, children: children.sorted(by: scrollableChildOrder))
                }
                if children.contains(where: { containsRetainedElement($0, liveHeistIds: liveHeistIds) }) {
                    return .container(entry, children: children.sorted(by: screenChildOrder))
                }
                return .container(entry, children: children)
            }
        )
    }

    private static func containsRetainedElement(
        _ node: TheStash.RegistryNode,
        liveHeistIds: Set<String>
    ) -> Bool {
        switch node {
        case .element(let element):
            return !liveHeistIds.contains(element.heistId)
        case .container(_, let children):
            return children.contains { containsRetainedElement($0, liveHeistIds: liveHeistIds) }
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
        node.folded(
            onElement: { element in
                element.contentSpaceOrigin?.y ?? element.element.shape.frame.origin.y
            },
            onContainer: { entry, results in
                results.min() ?? entry.container.frame.origin.y
            }
        )
    }

    private static func screenChildOrder(
        _ lhs: TheStash.RegistryNode, _ rhs: TheStash.RegistryNode
    ) -> Bool {
        let lhsPoint = firstScreenPoint(of: lhs)
        let rhsPoint = firstScreenPoint(of: rhs)
        if abs(lhsPoint.y - rhsPoint.y) >= 0.5 { return lhsPoint.y < rhsPoint.y }
        if abs(lhsPoint.x - rhsPoint.x) >= 0.5 { return lhsPoint.x < rhsPoint.x }
        let lhsId = firstHeistId(in: [lhs]) ?? ""
        let rhsId = firstHeistId(in: [rhs]) ?? ""
        return lhsId < rhsId
    }

    private static func firstScreenPoint(of node: TheStash.RegistryNode) -> CGPoint {
        node.folded(
            onElement: { $0.element.shape.frame.origin },
            onContainer: { entry, results in
                results.sorted {
                    if abs($0.y - $1.y) >= 0.5 { return $0.y < $1.y }
                    if abs($0.x - $1.x) >= 0.5 { return $0.x < $1.x }
                    return false
                }.first ?? entry.container.frame.origin
            }
        )
    }

    // MARK: - Empty Container Pruning (pure)

    private static func pruneEmptyContainers(
        roots: [TheStash.RegistryNode]
    ) -> [TheStash.RegistryNode] {
        roots.mapTree(
            onElement: { .element($0) },
            onContainer: { entry, children in
                children.isEmpty ? nil : .container(entry, children: children)
            }
        )
    }

    // MARK: - Prune by Allowlist (pure)

    private static func prune(
        roots: [TheStash.RegistryNode], keeping: Set<String>
    ) -> [TheStash.RegistryNode] {
        roots.mapTree(
            onElement: { keeping.contains($0.heistId) ? .element($0) : nil },
            onContainer: { entry, children in
                children.isEmpty ? nil : .container(entry, children: children)
            }
        )
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

#endif // DEBUG
#endif // canImport(UIKit)
