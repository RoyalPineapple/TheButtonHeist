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
        let contentFrames: [AccessibilityContainer: CGRect]
        let contentFramesByPath: [TreePath: CGRect]
        let scrollContentOriginsByPath: [TreePath: CGPoint]
        let scrollContainerPathsByPath: [TreePath: TreePath]
        let nestedInScrollView: Set<AccessibilityContainer>
    }

    private struct ContainerIdentityAccumulator {
        var contentFrames: [AccessibilityContainer: CGRect] = [:]
        var contentFramesByPath: [TreePath: CGRect] = [:]
        var scrollContentOriginsByPath: [TreePath: CGPoint] = [:]
        var scrollContainerPathsByPath: [TreePath: TreePath] = [:]
        var nestedInScrollView = Set<AccessibilityContainer>()
    }

    static func buildContainerIdentityContext(
        hierarchy: [AccessibilityHierarchy],
        scrollableContainerViews: [AccessibilityContainer: UIView],
        scrollableContainerViewsByPath: [TreePath: UIView] = [:]
    ) -> ContainerIdentityContext {
        var accumulator = ContainerIdentityAccumulator()
        for (index, node) in hierarchy.enumerated() {
            collectContainerContentFrames(
                node: node,
                path: TreePath([index]),
                parentScrollContext: nil,
                scrollableContainerViews: scrollableContainerViews,
                scrollableContainerViewsByPath: scrollableContainerViewsByPath,
                accumulator: &accumulator
            )
        }
        return ContainerIdentityContext(
            contentFrames: accumulator.contentFrames,
            contentFramesByPath: accumulator.contentFramesByPath,
            scrollContentOriginsByPath: accumulator.scrollContentOriginsByPath,
            scrollContainerPathsByPath: accumulator.scrollContainerPathsByPath,
            nestedInScrollView: accumulator.nestedInScrollView
        )
    }

    private static func collectContainerContentFrames(
        node: AccessibilityHierarchy,
        path: TreePath,
        parentScrollContext: ScrollContext?,
        scrollableContainerViews: [AccessibilityContainer: UIView],
        scrollableContainerViewsByPath: [TreePath: UIView],
        accumulator: inout ContainerIdentityAccumulator
    ) {
        guard case .container(let container, let children) = node else { return }

        let frame = container.frame.cgRect
        let contentFrame: CGRect
        if let parentScrollContext {
            contentFrame = CGRect(origin: .zero, size: frame.size)
            if !frame.isNull, !frame.isEmpty {
                accumulator.scrollContentOriginsByPath[path] = parentScrollContext.view.convert(frame.origin, from: nil)
                accumulator.scrollContainerPathsByPath[path] = parentScrollContext.containerPath
            }
            accumulator.nestedInScrollView.insert(container)
        } else {
            contentFrame = frame
        }
        accumulator.contentFrames[container] = contentFrame
        accumulator.contentFramesByPath[path] = contentFrame

        if let scrollView = scrollableContainerViewsByPath[path] as? UIScrollView
            ?? scrollableContainerViews[container] as? UIScrollView,
           !scrollView.bhIsUnsafeForProgrammaticScrolling {
            let childScrollContext = ScrollContext(view: scrollView, containerPath: path)
            for (index, child) in children.enumerated() {
                collectContainerContentFrames(
                    node: child,
                    path: path.appending(index),
                    parentScrollContext: childScrollContext,
                    scrollableContainerViews: scrollableContainerViews,
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
                    scrollableContainerViews: scrollableContainerViews,
                    scrollableContainerViewsByPath: scrollableContainerViewsByPath,
                    accumulator: &accumulator
                )
            }
        }
    }

    // MARK: - Element Context Building

    struct ElementContext {
        let contentSpaceOrigin: CGPoint?
        let scrollContainerPath: TreePath?
        weak var scrollView: UIScrollView?
    }

    private struct ScrollContext {
        let view: UIScrollView
        let containerPath: TreePath
    }

    /// Walk the hierarchy tree to gather per-element context: content-space origins,
    /// and scroll view refs. Live element objects are read directly from the
    /// parser result while building the current live capture.
    static func buildElementContexts(
        hierarchy: [AccessibilityHierarchy],
        scrollableContainerViews: [AccessibilityContainer: UIView],
        scrollableContainerViewsByPath: [TreePath: UIView] = [:]
    ) -> [AccessibilityElement: ElementContext] {
        let byPath = buildElementContextsByPath(
            hierarchy: hierarchy,
            scrollableContainerViews: scrollableContainerViews,
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
        scrollableContainerViews: [AccessibilityContainer: UIView],
        scrollableContainerViewsByPath: [TreePath: UIView] = [:]
    ) -> [TreePath: ElementContext] {
        var contexts: [AccessibilityElement: ElementContext] = [:]
        var contextsByPath: [TreePath: ElementContext] = [:]
        for (index, node) in hierarchy.enumerated() {
            collectElementContexts(
                node: node,
                path: TreePath([index]),
                parentScrollContext: nil,
                scrollableContainerViews: scrollableContainerViews,
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
        scrollableContainerViews: [AccessibilityContainer: UIView],
        scrollableContainerViewsByPath: [TreePath: UIView],
        into contexts: inout [AccessibilityElement: ElementContext],
        byPath contextsByPath: inout [TreePath: ElementContext]
    ) {
        switch node {
        case .element(let element, _):
            let origin: CGPoint? = parentScrollContext.flatMap { context in
                let frame = element.shape.frame
                return (!frame.isNull && !frame.isEmpty)
                    ? context.view.convert(frame.origin, from: nil)
                    : nil
            }
            let context = ElementContext(
                contentSpaceOrigin: origin,
                scrollContainerPath: parentScrollContext?.containerPath,
                scrollView: parentScrollContext?.view
            )
            contexts[element] = context
            contextsByPath[path] = context
        case .container(let container, let children):
            let childScrollContext: ScrollContext?
            if let scrollView = scrollableContainerViewsByPath[path] as? UIScrollView
                ?? scrollableContainerViews[container] as? UIScrollView,
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
                    scrollableContainerViews: scrollableContainerViews,
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
