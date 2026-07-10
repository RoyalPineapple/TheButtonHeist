#if canImport(UIKit)
#if DEBUG
import UIKit

import ThePlans
import TheScore

import AccessibilitySnapshotParser

extension TheBurglar {

    // MARK: - Container Content-Frame Building

    /// Walk the hierarchy tree to compute each container's accessibility frame
    /// and whether it is nested under a scrollable ancestor. Container identity
    /// is semantic parser evidence; live scroll-view conversion is dispatch
    /// evidence and must not feed generated container names or interface hashes.
    struct ContainerIdentityContext {
        let contentFramesByPath: [TreePath: ContentRect]
        let scrollMembershipsByPath: [TreePath: SemanticScreen.ScrollMembership]
        let nestedInScrollViewPaths: Set<TreePath>
    }

    private struct ContainerIdentityAccumulator {
        var contentFramesByPath: [TreePath: ContentRect] = [:]
        var scrollMembershipsByPath: [TreePath: SemanticScreen.ScrollMembership] = [:]
        var nestedInScrollViewPaths = Set<TreePath>()
    }

    static func buildContainerIdentityContext(
        hierarchy: [AccessibilityHierarchy],
        scrollableContainerPaths: Set<TreePath> = []
    ) -> ContainerIdentityContext {
        var accumulator = ContainerIdentityAccumulator()
        for (index, node) in hierarchy.enumerated() {
            collectContainerContentFrames(
                node: node,
                path: TreePath([index]),
                parentScrollContext: nil,
                scrollableContainerPaths: scrollableContainerPaths,
                accumulator: &accumulator
            )
        }
        return ContainerIdentityContext(
            contentFramesByPath: accumulator.contentFramesByPath,
            scrollMembershipsByPath: accumulator.scrollMembershipsByPath,
            nestedInScrollViewPaths: accumulator.nestedInScrollViewPaths
        )
    }

    private static func collectContainerContentFrames(
        node: AccessibilityHierarchy,
        path: TreePath,
        parentScrollContext: ScrollContext?,
        scrollableContainerPaths: Set<TreePath>,
        accumulator: inout ContainerIdentityAccumulator
    ) {
        guard case .container(let container, let children) = node else { return }

        let frame = container.frame.cgRect
        let contentFrame: ContentRect
        if let parentScrollContext {
            contentFrame = ContentRect(CGRect(origin: .zero, size: frame.size))
            accumulator.scrollMembershipsByPath[path] = SemanticScreen.ScrollMembership(
                containerPath: parentScrollContext.containerPath,
                index: nil
            )
            accumulator.nestedInScrollViewPaths.insert(path)
        } else {
            contentFrame = ContentRect(frame)
        }
        accumulator.contentFramesByPath[path] = contentFrame

        if scrollableContainerPaths.contains(path) {
            let childScrollContext = ScrollContext(containerPath: path)
            for (index, child) in children.enumerated() {
                collectContainerContentFrames(
                    node: child,
                    path: path.appending(index),
                    parentScrollContext: childScrollContext,
                    scrollableContainerPaths: scrollableContainerPaths,
                    accumulator: &accumulator
                )
            }
        } else {
            for (index, child) in children.enumerated() {
                collectContainerContentFrames(
                    node: child,
                    path: path.appending(index),
                    parentScrollContext: parentScrollContext,
                    scrollableContainerPaths: scrollableContainerPaths,
                    accumulator: &accumulator
                )
            }
        }
    }

    // MARK: - Element Context Building

    struct ElementContext {
        let scrollMembership: SemanticScreen.ScrollMembership?
    }

    private struct ScrollContext {
        let containerPath: TreePath
    }

    /// Walk the hierarchy tree to gather per-element scroll membership from
    /// typed scroll-container facts.
    static func buildElementContexts(
        hierarchy: [AccessibilityHierarchy],
        scrollableContainerPaths: Set<TreePath> = []
    ) -> [AccessibilityElement: ElementContext] {
        let byPath = buildElementContextsByPath(
            hierarchy: hierarchy,
            scrollableContainerPaths: scrollableContainerPaths
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
        scrollableContainerPaths: Set<TreePath> = []
    ) -> [TreePath: ElementContext] {
        var contexts: [AccessibilityElement: ElementContext] = [:]
        var contextsByPath: [TreePath: ElementContext] = [:]
        for (index, node) in hierarchy.enumerated() {
            collectElementContexts(
                node: node,
                path: TreePath([index]),
                parentScrollContext: nil,
                scrollableContainerPaths: scrollableContainerPaths,
                into: &contexts,
                byPath: &contextsByPath
            )
        }
        return contextsByPath
    }

    private static func collectElementContexts(
        node: AccessibilityHierarchy,
        path: TreePath,
        parentScrollContext: ScrollContext?,
        scrollableContainerPaths: Set<TreePath>,
        into contexts: inout [AccessibilityElement: ElementContext],
        byPath contextsByPath: inout [TreePath: ElementContext]
    ) {
        switch node {
        case .element(let element, _):
            let context = ElementContext(
                scrollMembership: parentScrollContext.map {
                    SemanticScreen.ScrollMembership(containerPath: $0.containerPath, index: nil)
                }
            )
            contexts[element] = context
            contextsByPath[path] = context
        case .container(_, let children):
            let childScrollContext: ScrollContext?
            if scrollableContainerPaths.contains(path) {
                childScrollContext = ScrollContext(containerPath: path)
            } else {
                childScrollContext = parentScrollContext
            }

            for (index, child) in children.enumerated() {
                collectElementContexts(
                    node: child,
                    path: path.appending(index),
                    parentScrollContext: childScrollContext,
                    scrollableContainerPaths: scrollableContainerPaths,
                    into: &contexts,
                    byPath: &contextsByPath
                )
            }
        }
    }

    // MARK: - Container Naming

    /// Compute a readable generated name prefix for a parser container, derived
    /// from its own exposed values. Container names are capture-local tree
    /// projections; `buildContainerNameIndex` appends a deterministic
    /// subtree hash when multiple containers share this prefix in one parse.
    static func containerName(
        for container: AccessibilityContainer,
        contentFrame: ContentRect
    ) -> ContainerName {
        let frameHash = coarseFrameHash(contentFrame.cgRect)
        switch container.type {
        case .none where container.scrollableContentSize != nil:
            return ContainerName(rawValue: "scrollable_\(frameHash)")
        case .none:
            let identifierSlug = container.identifier ?? "anon"
            return ContainerName(rawValue: "container_\(identifierSlug)_\(frameHash)")
        case .semanticGroup(let label, let value):
            let labelSlug = TheScore.slugify(label) ?? "anon"
            let valueSlug = TheScore.slugify(value) ?? ""
            let identifierSlug = container.identifier ?? ""
            return ContainerName(rawValue: "semantic_\(identifierSlug)_\(labelSlug)_\(valueSlug)")
        case .list:
            return ContainerName(rawValue: "list_\(frameHash)")
        case .landmark:
            return ContainerName(rawValue: "landmark_\(frameHash)")
        case .tabBar:
            return ContainerName(rawValue: "tabBar_\(frameHash)")
        case .dataTable(let rows, let columns, _):
            return ContainerName(rawValue: "table_\(rows)x\(columns)_\(frameHash)")
        case .scrollable:
            return ContainerName(rawValue: "scrollable_\(frameHash)")
        }
    }

    /// Coarse frame hash used when deriving generated container names. The
    /// bucket is device-dependent so iPad layouts get the same tolerance used
    /// by settle fingerprinting.
    static func coarseFrameHash(_ frame: CGRect) -> String {
        CoarseFrameComparison.hashFragment(for: frame)
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
