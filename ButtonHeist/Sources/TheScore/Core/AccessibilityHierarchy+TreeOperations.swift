import AccessibilitySnapshotModel

package extension Array where Element == AccessibilityHierarchy {
    func compactMap<Context, Result>(
        first maxCount: Int = 0,
        context: Context,
        container transformContext: (Context, AccessibilityContainer) -> Context,
        element transformElement: (AccessibilityElement, Int, Context) -> Result?
    ) -> [Result] {
        var contexts: [Context] = []
        var results: [Result] = []
        AccessibilityHierarchyTraversal.walk(roots: self) { event in
            switch event {
            case .enter(.element(let element, let traversalIndex), _):
                if let result = transformElement(element, traversalIndex, contexts.last ?? context) {
                    results.append(result)
                }
                return maxCount <= 0 || results.count < maxCount
            case .enter(.container(let container, _), _):
                contexts.append(transformContext(contexts.last ?? context, container))
                return true
            case .leave:
                contexts.removeLast()
                return true
            }
        }
        return results
    }
}

package extension AccessibilityHierarchy {
    var elements: [PathIndexedAccessibilityElement] {
        compactMapSubtrees { hierarchy, path in
            guard case .element(let element, let traversalIndex) = hierarchy else { return nil }
            return PathIndexedAccessibilityElement(
                element: element,
                path: path,
                traversalIndex: traversalIndex
            )
        }
    }

    var containers: [AccessibilityContainer] {
        compactMapSubtrees { hierarchy, _ in
            guard case .container(let container, _) = hierarchy else { return nil }
            return container
        }
    }
}

package extension Array where Element == AccessibilityHierarchy {
    var elements: [PathIndexedAccessibilityElement] {
        pathIndexedElements
    }

    var sortedElements: [AccessibilityElement] {
        pathIndexedElements.map(\.element)
    }

    var containers: [AccessibilityContainer] {
        pathIndexedContainers.map(\.container)
    }

    var scrollableContainers: [AccessibilityContainer] {
        pathIndexedContainers.compactMap { indexedContainer in
            indexedContainer.container.isScrollable ? indexedContainer.container : nil
        }
    }

    var containerFingerprints: [AccessibilityContainer: Int] {
        var fingerprints: [AccessibilityContainer: Int] = [:]
        var subtreeFingerprints: [Int] = []
        AccessibilityHierarchyTraversal.walk(roots: self) { event in
            switch event {
            case .enter(.element(let element, _), _):
                subtreeFingerprints.append(hierarchyContentFingerprint(for: element))
            case .enter(.container, _):
                break
            case .leave(let container, let childCount):
                let childFingerprints: [Int]
                if childCount == 0 {
                    childFingerprints = []
                } else {
                    childFingerprints = subtreeFingerprints.suffix(childCount).map { $0 }
                    subtreeFingerprints.removeLast(childCount)
                }
                let fingerprint = hierarchyContentFingerprint(
                    for: container,
                    childFingerprints: childFingerprints
                )
                fingerprints[container] = fingerprint
                subtreeFingerprints.append(fingerprint)
            }
            return true
        }
        return fingerprints
    }
}
