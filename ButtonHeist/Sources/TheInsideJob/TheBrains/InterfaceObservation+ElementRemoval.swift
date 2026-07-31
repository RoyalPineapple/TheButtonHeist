#if canImport(UIKit)
#if DEBUG
import AccessibilitySnapshotModel
import TheScore

extension InterfaceObservation {
    func removingElements(withIds removedIds: Set<HeistId>) -> InterfaceObservation {
        guard !removedIds.isEmpty else { return self }
        let viewportCapture = tree.viewportCapture
        let filteredViewport = viewportCapture.hierarchy.removingElements(
            withIds: removedIds,
            idsByPath: viewportCapture.heistIdsByPath
        )
        let pathMap = filteredViewport.pathMap
        let snapshot = LiveCapture.Snapshot(
            hierarchy: filteredViewport.hierarchy,
            heistIdsByPath: filteredViewport.idsByPath,
            firstResponderHeistId: viewportCapture.firstResponderHeistId.flatMap {
                removedIds.contains($0) ? nil : $0
            }
        )
        let dispatchReferences = LiveCapture.DispatchReferences(
            elementRefs: liveCapture.dispatchReferences.elementRefs.filter { !removedIds.contains($0.key) },
            containerRefsByPath: Self.remap(liveCapture.dispatchReferences.containerRefsByPath, using: pathMap),
            scrollableContainerViewsByPath: Self.remap(
                liveCapture.dispatchReferences.scrollableContainerViewsByPath,
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
                geometry: HeistElement.Geometry(
                    screen: entry.geometry.screen,
                    view: remap(entry.geometry.view, using: pathMap)
                ),
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
                viewSpace: remap(entry.viewSpace, using: pathMap),
                scrollMembership: remap(entry.scrollMembership, using: pathMap),
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

    private func remap(
        _ viewSpace: HeistElement.Geometry.ViewSpace,
        using pathMap: [TreePath: TreePath]
    ) -> HeistElement.Geometry.ViewSpace {
        HeistElement.Geometry.ViewSpace(
            ownerPath: pathMap[viewSpace.ownerPath] ?? viewSpace.ownerPath,
            frame: viewSpace.frame,
            activationPoint: viewSpace.activationPoint
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
