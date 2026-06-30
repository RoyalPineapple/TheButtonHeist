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
        let contentFramesByPath: [TreePath: CGRect]
        let scrollMembershipsByPath: [TreePath: SemanticScreen.ScrollMembership]
        let nestedInScrollViewPaths: Set<TreePath>
    }

    private struct ContainerIdentityAccumulator {
        var contentFramesByPath: [TreePath: CGRect] = [:]
        var scrollMembershipsByPath: [TreePath: SemanticScreen.ScrollMembership] = [:]
        var nestedInScrollViewPaths = Set<TreePath>()
    }

    static func buildContainerIdentityContext(
        hierarchy: [AccessibilityHierarchy],
        scrollableContainerViewsByPath: [TreePath: UIScrollView] = [:]
    ) -> ContainerIdentityContext {
        var accumulator = ContainerIdentityAccumulator()
        for (index, node) in hierarchy.enumerated() {
            collectContainerContentFrames(
                node: node,
                path: TreePath([index]),
                parentScrollContext: nil,
                scrollableContainerViewsByPath: scrollableContainerViewsByPath,
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
        scrollableContainerViewsByPath: [TreePath: UIScrollView],
        accumulator: inout ContainerIdentityAccumulator
    ) {
        guard case .container(let container, let children) = node else { return }

        let frame = container.frame.cgRect
        let contentFrame: CGRect
        if let parentScrollContext {
            contentFrame = CGRect(origin: .zero, size: frame.size)
            accumulator.scrollMembershipsByPath[path] = SemanticScreen.ScrollMembership(
                containerPath: parentScrollContext.containerPath,
                index: nil
            )
            accumulator.nestedInScrollViewPaths.insert(path)
        } else {
            contentFrame = frame
        }
        accumulator.contentFramesByPath[path] = contentFrame

        if let scrollView = scrollableContainerViewsByPath[path],
           !scrollView.bhIsUnsafeForProgrammaticScrolling {
            let childScrollContext = ScrollContext(view: scrollView, containerPath: path)
            for (index, child) in children.enumerated() {
                collectContainerContentFrames(
                    node: child,
                    path: path.appending(index),
                    parentScrollContext: childScrollContext,
                    scrollableContainerViewsByPath: scrollableContainerViewsByPath,
                    accumulator: &accumulator
                )
            }
        } else {
            for (index, child) in children.enumerated() {
                collectContainerContentFrames(
                    node: child,
                    path: path.appending(index),
                    parentScrollContext: parentScrollContext,
                    scrollableContainerViewsByPath: scrollableContainerViewsByPath,
                    accumulator: &accumulator
                )
            }
        }
    }

    // MARK: - Element Context Building

    struct ElementContext {
        let scrollMembership: SemanticScreen.ScrollMembership?
        weak var scrollView: UIScrollView?
    }

    private struct ScrollContext {
        let view: UIScrollView
        let containerPath: TreePath
    }

    /// Walk the hierarchy tree to gather per-element scroll membership and scroll
    /// view refs. Live element objects are read directly from the
    /// parser result while building the current live capture.
    static func buildElementContexts(
        hierarchy: [AccessibilityHierarchy],
        scrollableContainerViewsByPath: [TreePath: UIScrollView] = [:]
    ) -> [AccessibilityElement: ElementContext] {
        let byPath = buildElementContextsByPath(
            hierarchy: hierarchy,
            scrollableContainerViewsByPath: scrollableContainerViewsByPath
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
        scrollableContainerViewsByPath: [TreePath: UIScrollView] = [:]
    ) -> [TreePath: ElementContext] {
        var contexts: [AccessibilityElement: ElementContext] = [:]
        var contextsByPath: [TreePath: ElementContext] = [:]
        for (index, node) in hierarchy.enumerated() {
            collectElementContexts(
                node: node,
                path: TreePath([index]),
                parentScrollContext: nil,
                scrollableContainerViewsByPath: scrollableContainerViewsByPath,
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
        scrollableContainerViewsByPath: [TreePath: UIScrollView],
        into contexts: inout [AccessibilityElement: ElementContext],
        byPath contextsByPath: inout [TreePath: ElementContext]
    ) {
        switch node {
        case .element(let element, _):
            let context = ElementContext(
                scrollMembership: parentScrollContext.map {
                    SemanticScreen.ScrollMembership(containerPath: $0.containerPath, index: nil)
                },
                scrollView: parentScrollContext?.view
            )
            contexts[element] = context
            contextsByPath[path] = context
        case .container(_, let children):
            let childScrollContext: ScrollContext?
            if let scrollView = scrollableContainerViewsByPath[path],
               !scrollView.bhIsUnsafeForProgrammaticScrolling {
                childScrollContext = ScrollContext(view: scrollView, containerPath: path)
            } else {
                childScrollContext = parentScrollContext
            }

            for (index, child) in children.enumerated() {
                collectElementContexts(
                    node: child,
                    path: path.appending(index),
                    parentScrollContext: childScrollContext,
                    scrollableContainerViewsByPath: scrollableContainerViewsByPath,
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
        contentFrame: CGRect
    ) -> ContainerName {
        let frameHash = coarseFrameHash(contentFrame)
        switch container.type {
        case .scrollable:
            return ContainerName(rawValue: "scrollable_\(frameHash)")
        case .semanticGroup(let label, let value, let identifier):
            let labelSlug = TheScore.slugify(label) ?? "anon"
            let valueSlug = TheScore.slugify(value) ?? ""
            let identifierSlug = identifier ?? ""
            return ContainerName(rawValue: "semantic_\(identifierSlug)_\(labelSlug)_\(valueSlug)")
        case .list:
            return ContainerName(rawValue: "list_\(frameHash)")
        case .landmark:
            return ContainerName(rawValue: "landmark_\(frameHash)")
        case .tabBar:
            return ContainerName(rawValue: "tabBar_\(frameHash)")
        case .dataTable(let rows, let columns):
            return ContainerName(rawValue: "table_\(rows)x\(columns)_\(frameHash)")
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
