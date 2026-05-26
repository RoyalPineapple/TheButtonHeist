#if canImport(UIKit)
#if DEBUG
import CryptoKit
import UIKit

import TheScore

import AccessibilitySnapshotParser

extension TheBurglar {

    // MARK: - Build Screen From Parse

    /// Build a Screen value from a ParseResult. Pure: no mutable state.
    /// This is the lifted body of the old `apply(_:to:)` — heistId assignment
    /// (with content-position disambiguation), context resolution, container
    /// stable-id computation, and first-responder detection, all in one pass.
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

        let baseHeistIds = TheStash.IdAssignment.assign(elements)
        let resolvedHeistIds = resolveHeistIds(
            base: baseHeistIds,
            elements: elements,
            origins: indexedElements.map { contextsByPath[$0.path]?.contentSpaceOrigin }
        )

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
                contentSpaceOrigin: context?.contentSpaceOrigin,
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

        let containerStableIdIndex = buildContainerStableIdIndex(
            hierarchy: result.hierarchy,
            identityContext: identityContext
        )
        let containerStableIds = containerStableIdIndex.byContainer
        let containerStableIdsByPath = containerStableIdIndex.byPath

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
            firstResponderHeistId: firstResponders.first?.1,
            scrollableContainerViews: scrollableViewRefs,
            scrollableContainerViewsByPath: scrollableViewRefsByPath
        )
    }

    // MARK: - HeistId Disambiguation (in-parse only)

    /// Resolve a parallel-array of base heistIds, appending `_at_X_Y` content-
    /// space disambiguation when the same base id appears twice within a single
    /// parse with distinct content-space origins. Cross-parse disambiguation no
    /// longer exists — each parse is self-contained.
    private static func resolveHeistIds(
        base: [String],
        elements: [AccessibilityElement],
        origins: [CGPoint?]
    ) -> [String] {
        var resolved: [String] = []
        resolved.reserveCapacity(base.count)
        var seen: [String: (element: AccessibilityElement, origin: CGPoint?)] = [:]

        for ((heistId, element), origin) in zip(zip(base, elements), origins) {
            guard let existing = seen[heistId] else {
                resolved.append(heistId)
                seen[heistId] = (element, origin)
                continue
            }

            if hasSameMinimumMatcher(existing.element, element),
               let origin,
               let existingOrigin = existing.origin,
               !sameOrigin(existingOrigin, origin) {
                let disambiguated = contentPositionHeistId(heistId, origin: origin)
                resolved.append(disambiguated)
                seen[disambiguated] = (element, origin)
                continue
            }

            // Fall back: take the base id (IdAssignment.assign already adds
            // `_N` suffixes for duplicates; if we're still seeing a collision
            // here it's because the prior pass collapsed unique elements).
            resolved.append(heistId)
        }

        return resolved
    }

    static func contentPositionHeistId(_ baseHeistId: HeistId, origin: CGPoint) -> HeistId {
        "\(baseHeistId)_at_\(safeInt(origin.x.rounded()))_\(safeInt(origin.y.rounded()))"
    }

    private static func hasSameMinimumMatcher(_ lhs: AccessibilityElement, _ rhs: AccessibilityElement) -> Bool {
        guard lhs.identifier == rhs.identifier,
              lhs.label == rhs.label,
              stableTraitNames(lhs.traits) == stableTraitNames(rhs.traits) else {
            return false
        }
        if lhs.identifier?.isEmpty == false || lhs.label?.isEmpty == false {
            return true
        }
        return lhs.value == rhs.value
    }

    private static func stableTraitNames(_ traits: AccessibilityTraits) -> Set<String> {
        Set(traits.traitNames).subtracting(AccessibilityPolicy.transientTraitNames)
    }

    private static func sameOrigin(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool {
        abs(lhs.x - rhs.x) < 0.5 && abs(lhs.y - rhs.y) < 0.5
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
