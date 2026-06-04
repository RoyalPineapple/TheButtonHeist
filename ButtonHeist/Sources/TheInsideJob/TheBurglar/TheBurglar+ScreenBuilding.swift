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
        let hierarchy = screenCoordinateHierarchy(from: result)
        let scrollViews = scrollViewsByContainerForCurrentCapture(
            hierarchy: hierarchy,
            scrollViewsByPath: result.scrollViewsByPath
        ).merging(result.scrollViews, uniquingKeysWith: { current, _ in current })
        let indexedElements = hierarchy.pathIndexedElements
        let elements = indexedElements.map(\.element)
        let contextsByPath = buildElementContextsByPath(
            hierarchy: hierarchy,
            scrollableContainerViews: scrollViews,
            scrollableContainerViewsByPath: result.scrollViewsByPath,
            elementObjects: result.objects,
            elementObjectsByPath: result.objectsByPath
        )
        let identityContext = buildContainerIdentityContext(
            hierarchy: hierarchy,
            scrollableContainerViews: scrollViews,
            scrollableContainerViewsByPath: result.scrollViewsByPath
        )
        let containerStableIdIndex = buildContainerStableIdIndex(
            hierarchy: hierarchy,
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
            hierarchy: hierarchy,
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

    /// The snapshot parser emits geometry in its parsing root's local
    /// coordinate space. Button Heist's world model and wire/actionability
    /// surfaces need UIKit accessibility screen coordinates, so restore those by
    /// applying each parse root's screen offset at the parser boundary.
    private static func screenCoordinateHierarchy(from result: ParseResult) -> [AccessibilityHierarchy] {
        result.hierarchy.enumerated().map { index, node in
            screenCoordinateNode(
                node,
                path: TreePath([index]),
                inheritedOffset: .zero,
                screenCoordinateOffsetsByPath: result.screenCoordinateOffsetsByPath
            )
        }
    }

    private static func screenCoordinateNode(
        _ node: AccessibilityHierarchy,
        path: TreePath,
        inheritedOffset: CGPoint,
        screenCoordinateOffsetsByPath: [TreePath: CGPoint]
    ) -> AccessibilityHierarchy {
        let offset = screenCoordinateOffsetsByPath[path] ?? inheritedOffset
        switch node {
        case .element(let element, let traversalIndex):
            return .element(
                element.translatedBy(x: offset.x, y: offset.y),
                traversalIndex: traversalIndex
            )

        case .container(let container, let children):
            let mappedChildren = children.enumerated().map { childIndex, child in
                screenCoordinateNode(
                    child,
                    path: path.appending(childIndex),
                    inheritedOffset: offset,
                    screenCoordinateOffsetsByPath: screenCoordinateOffsetsByPath
                )
            }
            return .container(
                container.translatedBy(x: offset.x, y: offset.y),
                children: mappedChildren
            )
        }
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

private extension AccessibilityElement {
    func translatedBy(x: CGFloat, y: CGFloat) -> AccessibilityElement {
        AccessibilityElement(
            description: description,
            label: label,
            value: value,
            traits: traits,
            identifier: identifier,
            hint: hint,
            userInputLabels: userInputLabels,
            shape: shape.translatedBy(x: x, y: y),
            activationPoint: activationPoint.translatedBy(x: x, y: y),
            usesDefaultActivationPoint: usesDefaultActivationPoint,
            customActions: customActions,
            customContent: customContent,
            customRotors: customRotors.map { $0.translatedBy(x: x, y: y) },
            accessibilityLanguage: accessibilityLanguage,
            respondsToUserInteraction: respondsToUserInteraction
        )
    }
}

private extension AccessibilityElement.CustomRotor {
    func translatedBy(x: CGFloat, y: CGFloat) -> AccessibilityElement.CustomRotor {
        AccessibilityElement.CustomRotor(
            name: name,
            resultMarkers: resultMarkers.map { $0.translatedBy(x: x, y: y) },
            limit: limit
        )
    }
}

private extension AccessibilityElement.CustomRotor.ResultMarker {
    func translatedBy(x: CGFloat, y: CGFloat) -> AccessibilityElement.CustomRotor.ResultMarker {
        AccessibilityElement.CustomRotor.ResultMarker(
            elementDescription: elementDescription,
            rangeDescription: rangeDescription,
            shape: shape?.translatedBy(x: x, y: y)
        )
    }
}

private extension AccessibilityContainer {
    func translatedBy(x: CGFloat, y: CGFloat) -> AccessibilityContainer {
        AccessibilityContainer(
            type: type,
            frame: frame.translatedBy(x: x, y: y),
            isModalBoundary: isModalBoundary,
            customActions: customActions
        )
    }
}

private extension AccessibilityShape {
    func translatedBy(x: CGFloat, y: CGFloat) -> AccessibilityShape {
        switch self {
        case .frame(let rect):
            return .frame(rect.translatedBy(x: x, y: y))
        case .path(let elements):
            return .path(elements.map { $0.translatedBy(x: x, y: y) })
        }
    }
}

private extension AccessibilityPathElement {
    func translatedBy(x: CGFloat, y: CGFloat) -> AccessibilityPathElement {
        switch self {
        case .move(let point):
            return .move(to: point.translatedBy(x: x, y: y))
        case .line(let point):
            return .line(to: point.translatedBy(x: x, y: y))
        case .quadCurve(let point, let control):
            return .quadCurve(
                to: point.translatedBy(x: x, y: y),
                control: control.translatedBy(x: x, y: y)
            )
        case .curve(let point, let control1, let control2):
            return .curve(
                to: point.translatedBy(x: x, y: y),
                control1: control1.translatedBy(x: x, y: y),
                control2: control2.translatedBy(x: x, y: y)
            )
        case .closeSubpath:
            return .closeSubpath
        }
    }
}

private extension AccessibilityRect {
    func translatedBy(x: CGFloat, y: CGFloat) -> AccessibilityRect {
        AccessibilityRect(
            origin: origin.translatedBy(x: x, y: y),
            size: size
        )
    }
}

private extension AccessibilityPoint {
    func translatedBy(x: CGFloat, y: CGFloat) -> AccessibilityPoint {
        AccessibilityPoint(
            x: self.x + Double(x),
            y: self.y + Double(y)
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
