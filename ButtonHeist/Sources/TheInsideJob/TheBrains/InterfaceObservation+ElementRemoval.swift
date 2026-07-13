#if canImport(UIKit)
#if DEBUG
import AccessibilitySnapshotModel
import TheScore

extension InterfaceObservation {
    func removingElements(withIds removedIds: Set<HeistId>) -> InterfaceObservation {
        guard !removedIds.isEmpty else { return self }
        let filteredViewport = liveCapture.hierarchy.removingElements(
            withIds: removedIds,
            idsByPath: liveCapture.heistIdsByPath
        )
        let pathMap = filteredViewport.pathMap
        let snapshot = LiveCapture.Snapshot(
            hierarchy: filteredViewport.hierarchy,
            containerNamesByPath: Self.remap(liveCapture.containerNamesByPath, using: pathMap),
            heistIdsByPath: filteredViewport.idsByPath,
            containerContentFramesByPath: Self.remap(liveCapture.containerContentFramesByPath, using: pathMap),
            containerScrollMembershipsByPath: Self.remapMemberships(
                liveCapture.containerScrollMembershipsByPath,
                using: pathMap
            ),
            containerObservedScrollContentActivationPointsByPath: Self.remap(
                liveCapture.containerObservedScrollContentActivationPointsByPath,
                using: pathMap
            ),
            scrollInventoriesByPath: Self.remap(liveCapture.scrollInventoriesByPath, using: pathMap),
            firstResponderHeistId: liveCapture.firstResponderHeistId.flatMap {
                removedIds.contains($0) ? nil : $0
            }
        )
        let dispatchReferences = LiveCapture.DispatchReferences(
            elementRefs: liveCapture.elementRefs.filter { !removedIds.contains($0.key) },
            containerRefsByPath: Self.remap(liveCapture.containerRefsByPath, using: pathMap),
            scrollableContainerViewsByPath: Self.remap(
                liveCapture.scrollableContainerViewsByPath,
                using: pathMap
            )
        )
        let filteredTree = tree.removingElements(
            withIds: removedIds,
            using: pathMap,
            viewportCapture: snapshot
        )
        do {
            return try InterfaceObservation.build(
                tree: filteredTree,
                dispatchReferences: dispatchReferences
            )
        } catch {
            preconditionFailure("Post-action observation filtering failed validation: \(error)")
        }
    }

    private static func remap<Value>(
        _ values: [TreePath: Value],
        using pathMap: [TreePath: TreePath]
    ) -> [TreePath: Value] {
        Dictionary(
            uniqueKeysWithValues: values.compactMap { path, value in
                pathMap[path].map { ($0, value) }
            }
        )
    }

    private static func remapMemberships(
        _ memberships: [TreePath: InterfaceTree.ScrollMembership],
        using pathMap: [TreePath: TreePath]
    ) -> [TreePath: InterfaceTree.ScrollMembership] {
        Dictionary(
            uniqueKeysWithValues: memberships.compactMap { path, membership in
                guard let remappedPath = pathMap[path],
                      let remappedContainerPath = pathMap[membership.containerPath]
                else { return nil }
                return (
                    remappedPath,
                    InterfaceTree.ScrollMembership(
                        containerPath: remappedContainerPath,
                        index: membership.index
                    )
                )
            }
        )
    }
}

private extension InterfaceTree {
    func removingElements(
        withIds removedIds: Set<HeistId>,
        using pathMap: [TreePath: TreePath],
        viewportCapture: LiveCapture.Snapshot
    ) -> InterfaceTree {
        var remappedElements: [HeistId: Element] = [:]
        remappedElements.reserveCapacity(elements.count)
        for (heistId, entry) in elements where !removedIds.contains(heistId) {
            let remappedPath = viewportElementIDs.contains(heistId)
                ? pathMap[entry.path] ?? entry.path
                : entry.path
            remappedElements[heistId] = Element(
                heistId: entry.heistId,
                path: remappedPath,
                scrollMembership: remap(entry.scrollMembership, using: pathMap),
                observedScrollContentActivationPoint: entry.observedScrollContentActivationPoint,
                element: entry.element
            )
        }

        var remappedContainers: [TreePath: Container] = [:]
        remappedContainers.reserveCapacity(containers.count)
        for entry in containers.values.sorted(by: { $0.path < $1.path }) {
            let remappedPath = pathMap[entry.path] ?? entry.path
            remappedContainers[remappedPath] = Container(
                container: entry.container,
                path: remappedPath,
                containerName: entry.containerName,
                contentRect: entry.contentFrame,
                scrollMembership: remap(entry.scrollMembership, using: pathMap),
                observedScrollContentActivationPoint: entry.observedScrollContentActivationPoint,
                scrollInventory: entry.scrollInventory
            )
        }
        return InterfaceTree(
            elements: remappedElements,
            containers: remappedContainers,
            viewportCapture: viewportCapture
        )
    }

    private func remap(
        _ membership: ScrollMembership?,
        using pathMap: [TreePath: TreePath]
    ) -> ScrollMembership? {
        guard let membership else { return nil }
        return ScrollMembership(
            containerPath: pathMap[membership.containerPath] ?? membership.containerPath,
            index: membership.index
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
