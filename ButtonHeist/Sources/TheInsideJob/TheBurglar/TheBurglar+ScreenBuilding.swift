#if canImport(UIKit)
#if DEBUG
import CryptoKit
import UIKit

import TheScore
import ThePlans

import AccessibilitySnapshotParser

extension TheBurglar {

    // MARK: - Build Screen From Parse

    /// Build a Screen value from a ParseResult. Pure: no mutable state. This
    /// pass assigns heistIds, resolves context, computes container names,
    /// and detects first responder state.
    static func buildScreen(from result: ParseResult) -> Screen {
        let hierarchy = screenCoordinateHierarchy(from: result)
        let indexedElements = hierarchy.pathIndexedElements
        let elements = indexedElements.map(\.element)
        let contextsByPath = buildElementContextsByPath(
            hierarchy: hierarchy,
            scrollableContainerViewsByPath: result.scrollViewsByPath
        )
        let identityContext = buildContainerIdentityContext(
            hierarchy: hierarchy,
            scrollableContainerViewsByPath: result.scrollViewsByPath
        )
        let containerNamesByPath = buildContainerNamesByPath(
            hierarchy: hierarchy,
            identityContext: identityContext
        )
        let containerScrollContentLocationsByPath = containerScrollContentLocations(
            identityContext: identityContext
        )

        let baseHeistIds = TheStash.IdAssignment.assign(elements)
        let resolvedHeistIds = baseHeistIds

        var screenElements: [HeistId: Screen.ScreenElement] = [:]
        screenElements.reserveCapacity(elements.count)
        var heistIdsByPath: [TreePath: HeistId] = [:]
        heistIdsByPath.reserveCapacity(elements.count)
        var elementRefs: [HeistId: Screen.ElementRef] = [:]
        elementRefs.reserveCapacity(elements.count)
        for ((parsedElement, path, _), heistId) in zip(indexedElements, resolvedHeistIds) {
            let context = contextsByPath[path]
            let entry = Screen.ScreenElement(
                heistId: heistId,
                scrollContentLocation: context.flatMap {
                    scrollContentLocation(for: $0)
                },
                element: parsedElement
            )
            screenElements[heistId] = entry
            heistIdsByPath[path] = heistId
            elementRefs[heistId] = Screen.ElementRef(
                object: result.objectsByPath[path],
                scrollView: context?.scrollView
            )
        }

        let firstResponders = zip(indexedElements, resolvedHeistIds).filter { item, _ in
            let object = result.objectsByPath[item.path]
            return (object as? UIView)?.isFirstResponder == true
        }
        if firstResponders.count > 1 {
            insideJobLogger.warning("Multiple first responders detected: \(firstResponders.map { $0.1.description }.joined(separator: ", "))")
        }

        let scrollableViewRefsByPath = result.scrollViewsByPath.mapValues {
            Screen.ScrollableViewRef(view: $0)
        }
        let containerRefsByPath = result.containerObjectsByPath.mapValues {
            Screen.ContainerRef(object: $0)
        }
        return Screen(
            elements: screenElements,
            hierarchy: hierarchy,
            containerNamesByPath: containerNamesByPath,
            heistIdsByPath: heistIdsByPath,
            elementRefs: elementRefs,
            containerRefsByPath: containerRefsByPath,
            containerContentFramesByPath: identityContext.contentFramesByPath,
            containerScrollContentLocationsByPath: containerScrollContentLocationsByPath,
            firstResponderHeistId: firstResponders.first?.1,
            scrollableContainerViewsByPath: scrollableViewRefsByPath
        )
    }

    /// The snapshot parser emits geometry in its parsing root's local
    /// coordinate space. Button Heist's world model and wire/element-inflation
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
        for context: ElementContext
    ) -> Screen.ScrollContentLocation? {
        guard let origin = context.contentSpaceOrigin,
              let scrollContainerPath = context.scrollContainerPath
        else { return nil }
        return Screen.ScrollContentLocation(
            origin: origin,
            scrollContainerPath: scrollContainerPath
        )
    }

    private static func containerScrollContentLocations(
        identityContext: ContainerIdentityContext
    ) -> [TreePath: Screen.ScrollContentLocation] {
        Dictionary(
            uniqueKeysWithValues: identityContext.scrollContentOriginsByPath.compactMap { path, origin in
                guard let scrollContainerPath = identityContext.scrollContainerPathsByPath[path]
                else { return nil }
                return (
                    path,
                    Screen.ScrollContentLocation(
                        origin: origin,
                        scrollContainerPath: scrollContainerPath
                    )
                )
            }
        )
    }

    // MARK: - Container Name Index

    private static func buildContainerNamesByPath(
        hierarchy: [AccessibilityHierarchy],
        identityContext: ContainerIdentityContext
    ) -> [TreePath: ContainerName] {
        let candidates = hierarchy.compactMapSubtrees { node, path -> ContainerNameCandidate? in
            guard case .container(let container, _) = node else { return nil }
            let contentFrame = identityContext.contentFramesByPath[path]
                ?? container.frame.cgRect
            let readableName = containerName(
                for: container,
                contentFrame: contentFrame
            )
            return ContainerNameCandidate(
                path: path,
                node: node,
                readableName: readableName
            )
        }

        let duplicateReadableNames = Set(
            Dictionary(grouping: candidates, by: \.readableName)
                .filter { $0.value.count > 1 }
                .keys
        )

        var byPath: [TreePath: ContainerName] = [:]
        for candidate in candidates {
            let containerName: ContainerName
            if duplicateReadableNames.contains(candidate.readableName) {
                containerName = captureLocalContainerId(
                    readableName: candidate.readableName,
                    node: candidate.node,
                    path: candidate.path
                )
            } else {
                containerName = candidate.readableName
            }
            byPath[candidate.path] = containerName
        }
        return byPath
    }

    static func captureLocalContainerId(
        readableName: ContainerName,
        node: AccessibilityHierarchy,
        path: TreePath
    ) -> ContainerName {
        ContainerName(rawValue: "\(readableName.rawValue)-\(containerHash(node: node, path: path))")
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

    private struct ContainerNameCandidate {
        let path: TreePath
        let node: AccessibilityHierarchy
        let readableName: ContainerName
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
