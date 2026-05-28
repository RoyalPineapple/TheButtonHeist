#if canImport(UIKit)
#if DEBUG
import CryptoKit
import UIKit

import TheScore

import AccessibilitySnapshotParser

extension TheBurglar {

    // MARK: - Build Screen From Parse

    /// Build a Screen value from a ParseResult. Pure: no mutable state. This
    /// pass assigns heistIds, resolves context, computes container stable IDs,
    /// and detects first responder state.
    static func buildScreen(from result: ParseResult) -> Screen {
        let indexedElements = result.hierarchy.pathIndexedElements
        let elements = indexedElements.map(\.element)
        let contextsByPath = buildElementContextsByPath(
            hierarchy: result.hierarchy,
            scrollableContainerViews: result.scrollViews,
            scrollableContainerViewsByPath: result.scrollViewsByPath,
            elementObjects: result.objects,
            elementObjectsByPath: result.objectsByPath
        )
        let identityContext = buildContainerIdentityContext(
            hierarchy: result.hierarchy,
            scrollableContainerViews: result.scrollViews,
            scrollableContainerViewsByPath: result.scrollViewsByPath
        )
        let containerStableIdIndex = buildContainerStableIdIndex(
            hierarchy: result.hierarchy,
            identityContext: identityContext
        )
        let containerStableIds = containerStableIdIndex.byContainer
        let containerStableIdsByPath = containerStableIdIndex.byPath

        let baseHeistIds = TheStash.IdAssignment.assign(elements)
        let resolvedHeistIds = baseHeistIds

        var screenElements: [HeistId: Screen.ScreenElement] = [:]
        screenElements.reserveCapacity(elements.count)
        var heistIdByElement: [AccessibilityElement: HeistId] = [:]
        heistIdByElement.reserveCapacity(elements.count)
        var heistIdByElementPath: [TreePath: HeistId] = [:]
        heistIdByElementPath.reserveCapacity(elements.count)
        var elementRefs: [HeistId: Screen.ElementRef] = [:]
        elementRefs.reserveCapacity(elements.count)
        for ((parsedElement, path, _), heistId) in zip(indexedElements, resolvedHeistIds) {
            let context = contextsByPath[path]
            let entry = Screen.ScreenElement(
                heistId: heistId,
                scrollContentLocation: context.flatMap {
                    scrollContentLocation(for: $0, containerStableIdsByPath: containerStableIdsByPath)
                },
                element: parsedElement
            )
            screenElements[heistId] = entry
            heistIdByElement[parsedElement] = heistId
            heistIdByElementPath[path] = heistId
            elementRefs[heistId] = Screen.ElementRef(
                object: context?.object,
                scrollView: context?.scrollView
            )
        }

        let firstResponders = zip(indexedElements, resolvedHeistIds).filter { item, _ in
            (contextsByPath[item.path]?.object as? UIView)?.isFirstResponder == true
        }
        if firstResponders.count > 1 {
            insideJobLogger.warning("Multiple first responders detected: \(firstResponders.map(\.1).joined(separator: ", "))")
        }

        let scrollableViewRefs = result.scrollViews.mapValues { Screen.ScrollableViewRef(view: $0) }
        let scrollableViewRefsByPath = result.scrollViewsByPath.mapValues {
            Screen.ScrollableViewRef(view: $0)
        }
        let containerRefsByPath = result.containerObjectsByPath.mapValues {
            Screen.ContainerRef(object: $0)
        }
        return Screen(
            elements: screenElements,
            hierarchy: result.hierarchy,
            containerStableIds: containerStableIds,
            containerStableIdsByPath: containerStableIdsByPath,
            heistIdByElement: heistIdByElement,
            heistIdByElementPath: heistIdByElementPath,
            elementRefs: elementRefs,
            containerRefsByPath: containerRefsByPath,
            containerContentFramesByPath: identityContext.contentFramesByPath,
            firstResponderHeistId: firstResponders.first?.1,
            scrollableContainerViews: scrollableViewRefs,
            scrollableContainerViewsByPath: scrollableViewRefsByPath
        )
    }

    private static func scrollContentLocation(
        for context: ElementContext,
        containerStableIdsByPath: [TreePath: HeistContainer]
    ) -> Screen.ScrollContentLocation? {
        guard let origin = context.contentSpaceOrigin,
              let scrollContainerPath = context.scrollContainerPath,
              let scrollContainer = containerStableIdsByPath[scrollContainerPath]
        else { return nil }
        return Screen.ScrollContentLocation(
            origin: origin,
            scrollContainer: scrollContainer
        )
    }

    // MARK: - Container StableId Index

    private static func buildContainerStableIdIndex(
        hierarchy: [AccessibilityHierarchy],
        identityContext: ContainerIdentityContext
    ) -> ContainerStableIdIndex {
        let candidates = hierarchy.compactMapSubtrees { node, path -> ContainerStableIdCandidate? in
            guard case .container(let container, _) = node else { return nil }
            let contentFrame = identityContext.contentFramesByPath[path]
                ?? identityContext.contentFrames[container]
                ?? container.frame.cgRect
            let readableName = stableId(
                for: container,
                contentFrame: contentFrame
            )
            return ContainerStableIdCandidate(
                path: path,
                container: container,
                node: node,
                readableName: readableName
            )
        }

        let duplicateReadableNames = Set(
            Dictionary(grouping: candidates, by: \.readableName)
                .filter { $0.value.count > 1 }
                .keys
        )

        var byContainer: [AccessibilityContainer: HeistContainer] = [:]
        var byPath: [TreePath: HeistContainer] = [:]
        for candidate in candidates {
            let stableId: HeistContainer
            if duplicateReadableNames.contains(candidate.readableName) {
                stableId = captureLocalContainerId(
                    readableName: candidate.readableName,
                    node: candidate.node,
                    path: candidate.path
                )
            } else {
                stableId = candidate.readableName
            }
            byContainer[candidate.container] = stableId
            byPath[candidate.path] = stableId
        }
        return ContainerStableIdIndex(byContainer: byContainer, byPath: byPath)
    }

    static func captureLocalContainerId(
        readableName: HeistContainer,
        node: AccessibilityHierarchy,
        path: TreePath
    ) -> HeistContainer {
        "\(readableName)-\(containerHash(node: node, path: path))"
    }

    private static func containerHash(node: AccessibilityHierarchy, path: TreePath) -> String {
        let data = stableContainerHashData(node: node, path: path)
        return SHA256.hash(data: data).prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    private static func stableContainerHashData(node: AccessibilityHierarchy, path: TreePath) -> Data {
        let payload = ContainerIdentityPayload(path: path.indices, subtree: node)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        switch Result(catching: { try encoder.encode(payload) }) {
        case .success(let data):
            return data
        case .failure(let error):
            preconditionFailure("Failed to encode container identity payload: \(error)")
        }
    }

    private struct ContainerStableIdCandidate {
        let path: TreePath
        let container: AccessibilityContainer
        let node: AccessibilityHierarchy
        let readableName: HeistContainer
    }

    private struct ContainerStableIdIndex {
        let byContainer: [AccessibilityContainer: HeistContainer]
        let byPath: [TreePath: HeistContainer]
    }

    private struct ContainerIdentityPayload: Encodable {
        let path: [Int]
        let subtree: AccessibilityHierarchy
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
