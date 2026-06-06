#if canImport(UIKit)
#if DEBUG
import UIKit

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
        if parentScrollView != nil {
            contentFrame = CGRect(origin: .zero, size: frame.size)
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
        let scrollContainerPath: TreePath?
        weak var scrollView: UIScrollView?
        weak var object: NSObject?
    }

    private struct ScrollContext {
        let view: UIScrollView
        let containerPath: TreePath
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
                parentScrollContext: nil,
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
        parentScrollContext: ScrollContext?,
        scrollableContainerViews: [AccessibilityContainer: UIView],
        scrollableContainerViewsByPath: [TreePath: UIView],
        objectIndex: ElementObjectIndex,
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
                scrollView: parentScrollContext?.view,
                object: objectIndex.object(for: element, path: path)
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
                    objectIndex: objectIndex,
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
