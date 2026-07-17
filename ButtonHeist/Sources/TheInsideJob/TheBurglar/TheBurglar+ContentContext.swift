#if canImport(UIKit)
#if DEBUG
import UIKit

import ThePlans
import TheScore

import AccessibilitySnapshotParser

extension TheBurglar {

    // MARK: - Hierarchy Identity

    struct HierarchyContainerIdentity {
        let path: TreePath
        let container: AccessibilityContainer
        let children: [AccessibilityHierarchy]
        let contentFrame: ContentRect
        let scrollMembership: InterfaceTree.ScrollMembership?

        var subtree: AccessibilityHierarchy {
            .container(container, children: children)
        }
    }

    struct HierarchyElementIdentity {
        let path: TreePath
        let element: AccessibilityElement
        let traversalIndex: Int
        let scrollMembership: InterfaceTree.ScrollMembership?
    }

    /// Path-distinct identity facts derived from one hierarchy traversal.
    /// Container geometry and scroll membership are durable value evidence;
    /// live UIKit conversion remains outside this context.
    struct HierarchyIdentityContext {
        let hierarchy: [AccessibilityHierarchy]
        let scrollableContainerPaths: Set<TreePath>
        let containers: [HierarchyContainerIdentity]
        let elements: [HierarchyElementIdentity]

        var contentFramesByPath: [TreePath: ContentRect] {
            Dictionary(uniqueKeysWithValues: containers.map { ($0.path, $0.contentFrame) })
        }

        var scrollMembershipsByPath: [TreePath: InterfaceTree.ScrollMembership] {
            Dictionary(
                uniqueKeysWithValues: containers.compactMap { identity in
                    identity.scrollMembership.map { (identity.path, $0) }
                }
            )
        }

        var nestedInScrollViewPaths: Set<TreePath> {
            Set(containers.compactMap { $0.scrollMembership == nil ? nil : $0.path })
        }
    }

    private struct HierarchyIdentityTraversalContext {
        let path: TreePath
        let parentScrollContainerPath: TreePath?
    }

    private struct HierarchyIdentityAccumulator {
        var containers: [HierarchyContainerIdentity] = []
        var elements: [HierarchyElementIdentity] = []
    }

    static func buildHierarchyIdentityContext(
        hierarchy: [AccessibilityHierarchy],
        scrollableContainerPaths: Set<TreePath> = []
    ) -> HierarchyIdentityContext {
        var accumulator = HierarchyIdentityAccumulator()
        for (rootIndex, root) in hierarchy.enumerated() {
            root.foldedPreorder(
                context: HierarchyIdentityTraversalContext(
                    path: TreePath([rootIndex]),
                    parentScrollContainerPath: nil
                ),
                into: &accumulator,
                onElement: { element, traversalIndex, context, accumulator in
                    accumulator.elements.append(
                        HierarchyElementIdentity(
                            path: context.path,
                            element: element,
                            traversalIndex: traversalIndex,
                            scrollMembership: context.parentScrollContainerPath.map {
                                InterfaceTree.ScrollMembership(containerPath: $0, index: nil)
                            }
                        )
                    )
                    return true
                },
                onContainer: { container, children, context, accumulator in
                    let membership = context.parentScrollContainerPath.map {
                        InterfaceTree.ScrollMembership(containerPath: $0, index: nil)
                    }
                    let frame = container.frame.cgRect
                    let contentFrame = membership == nil
                        ? ContentRect(frame)
                        : ContentRect(CGRect(origin: .zero, size: frame.size))
                    accumulator.containers.append(
                        HierarchyContainerIdentity(
                            path: context.path,
                            container: container,
                            children: children,
                            contentFrame: contentFrame,
                            scrollMembership: membership
                        )
                    )
                    let childScrollContainerPath = scrollableContainerPaths.contains(context.path)
                        ? context.path
                        : context.parentScrollContainerPath
                    return (
                        HierarchyIdentityTraversalContext(
                            path: context.path,
                            parentScrollContainerPath: childScrollContainerPath
                        ),
                        true
                    )
                },
                descend: { context, childIndex in
                    HierarchyIdentityTraversalContext(
                        path: context.path.appending(childIndex),
                        parentScrollContainerPath: context.parentScrollContainerPath
                    )
                }
            )
        }
        return HierarchyIdentityContext(
            hierarchy: hierarchy,
            scrollableContainerPaths: scrollableContainerPaths,
            containers: accumulator.containers,
            elements: accumulator.elements.sorted { lhs, rhs in
                if lhs.traversalIndex != rhs.traversalIndex {
                    return lhs.traversalIndex < rhs.traversalIndex
                }
                return lhs.path < rhs.path
            }
        )
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
        let facts = container.containerPredicateFacts
        switch facts.role {
        case .none where facts.isScrollable:
            return ContainerName(stringLiteral: "scrollable_\(frameHash)")
        case .none:
            let identifierSlug = facts.identifier ?? "anon"
            return ContainerName(stringLiteral: "container_\(identifierSlug)_\(frameHash)")
        case .semanticGroup(let label, let value):
            let labelSlug = TheScore.slugify(label) ?? "anon"
            let valueSlug = TheScore.slugify(value) ?? ""
            let identifierSlug = facts.identifier ?? ""
            return ContainerName(stringLiteral: "semantic_\(identifierSlug)_\(labelSlug)_\(valueSlug)")
        case .list:
            return ContainerName(stringLiteral: "list_\(frameHash)")
        case .landmark:
            return ContainerName(stringLiteral: "landmark_\(frameHash)")
        case .tabBar:
            return ContainerName(stringLiteral: "tabBar_\(frameHash)")
        case .series:
            return ContainerName(stringLiteral: "series_\(frameHash)")
        case .dataTable(let rows, let columns):
            return ContainerName(stringLiteral: "table_\(rows)x\(columns)_\(frameHash)")
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
