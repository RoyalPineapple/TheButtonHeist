#if canImport(UIKit)
#if DEBUG
import CryptoKit
import UIKit

import TheScore
import ThePlans

import AccessibilitySnapshotParser

extension TheBurglar {

    // MARK: - Build Screen From Parse

    /// Build a Screen value from a ParseResult. UIKit/Objective-C reads are
    /// extracted into typed facts first; projection then assigns heistIds,
    /// resolves context, computes container names, and applies live facts.
    static func buildScreen(from result: ParseResult) -> Screen {
        let hierarchy = screenCoordinateHierarchy(from: result)
        let facts = ScreenBuildFacts.extract(
            from: result,
            screenCoordinateHierarchy: hierarchy
        )
        let projection = buildScreenProjection(
            from: result,
            hierarchy: hierarchy,
            facts: facts
        )
        logScreenBuildEvents(projection.logEvents)
        return projection.screen
    }

    /// Pure projection entry used by focused tests with synthetic facts.
    static func buildScreen(from result: ParseResult, facts: ScreenBuildFacts) -> Screen {
        buildScreenProjection(
            from: result,
            hierarchy: screenCoordinateHierarchy(from: result),
            facts: facts
        ).screen
    }

    private static func buildScreenProjection(
        from result: ParseResult,
        hierarchy: [AccessibilityHierarchy],
        facts: ScreenBuildFacts
    ) -> ScreenBuildProjection {
        let indexedElements = hierarchy.pathIndexedElements
        let elements = indexedElements.map(\.element)
        let contextsByPath = buildElementContextsByPath(
            hierarchy: hierarchy,
            scrollableContainerPaths: facts.scroll.contextContainerPaths
        )
        let identityContext = buildContainerIdentityContext(
            hierarchy: hierarchy,
            scrollableContainerPaths: facts.scroll.contextContainerPaths
        )
        let containerNamesByPath = buildContainerNamesByPath(
            hierarchy: hierarchy,
            identityContext: identityContext
        )

        let baseHeistIds = TheStash.IdAssignment.assign(elements)
        let resolvedHeistIds = baseHeistIds

        var logEvents: [ScreenBuildLogEvent] = []
        var screenElements: [HeistId: Screen.ScreenElement] = [:]
        screenElements.reserveCapacity(elements.count)
        var heistIdsByPath: [TreePath: HeistId] = [:]
        heistIdsByPath.reserveCapacity(elements.count)
        var elementRefs: [HeistId: Screen.ElementRef] = [:]
        elementRefs.reserveCapacity(elements.count)
        for (indexedElement, heistId) in zip(indexedElements, resolvedHeistIds) {
            let parsedElement = indexedElement.element
            let path = indexedElement.path
            let context = contextsByPath[path]
            let scrollMembership = scrollMembership(
                context?.scrollMembership,
                path: path,
                facts: facts
            )
            let observedScrollContentActivationPoint = facts.activationPoints.element(at: path)
            let entry = Screen.ScreenElement(
                heistId: heistId,
                scrollMembership: scrollMembership,
                observedScrollContentActivationPoint: observedScrollContentActivationPoint,
                element: parsedElement
            )
            if let observedScrollContentActivationPoint, let scrollMembership {
                logEvents.append(
                    .capturedObservedScrollContentActivationPoint(
                        heistId: heistId,
                        containerPath: scrollMembership.containerPath,
                        index: scrollMembership.index,
                        point: observedScrollContentActivationPoint.point
                    )
                )
            }
            screenElements[heistId] = entry
            heistIdsByPath[path] = heistId
            elementRefs[heistId] = Screen.ElementRef(
                object: result.objectsByPath[path],
                scrollView: (context?.scrollMembership).flatMap { membership in
                    result.scrollViewsByPath[membership.containerPath]
                }
            )
        }

        let firstResponders = zip(indexedElements, resolvedHeistIds).filter { item, _ in
            facts.focus.isFirstResponder(at: item.path)
        }
        if firstResponders.count > 1 {
            logEvents.append(.multipleFirstResponders(firstResponders.map { $0.1 }))
        }

        let scrollableViewRefsByPath = result.scrollViewsByPath.mapValues {
            Screen.ScrollableViewRef(view: $0)
        }
        let containerRefsByPath = result.containerObjectsByPath.mapValues {
            Screen.ContainerRef(object: $0)
        }
        let screen = Screen(
            elements: screenElements,
            hierarchy: hierarchy,
            containerNamesByPath: containerNamesByPath,
            heistIdsByPath: heistIdsByPath,
            elementRefs: elementRefs,
            containerRefsByPath: containerRefsByPath,
            containerContentFramesByPath: identityContext.contentFramesByPath,
            containerScrollMembershipsByPath: identityContext.scrollMembershipsByPath,
            containerObservedScrollContentActivationPointsByPath: facts.activationPoints.containerByPath,
            scrollInventoriesByPath: facts.scroll.inventoriesByPath,
            firstResponderHeistId: firstResponders.first?.1,
            scrollableContainerViewsByPath: scrollableViewRefsByPath
        )
        return ScreenBuildProjection(
            screen: screen,
            logEvents: logEvents
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

    private static func scrollMembership(
        _ membership: Screen.ScrollMembership?,
        path: TreePath,
        facts: ScreenBuildFacts
    ) -> Screen.ScrollMembership? {
        guard let membership else { return nil }
        return Screen.ScrollMembership(
            containerPath: membership.containerPath,
            index: facts.scroll.index(
                forElementAt: path,
                in: membership.containerPath
            )
        )
    }

    private static func logScreenBuildEvents(_ events: [ScreenBuildLogEvent]) {
        for event in events {
            switch event {
            case .capturedObservedScrollContentActivationPoint(let heistId, let containerPath, let index, let point):
                let containerPathDescription = containerPath.indices.map(String.init).joined(separator: ".")
                let indexDescription = index.map(String.init) ?? "nil"
                insideJobLogger.debug(
                    """
                    Captured observed scroll-content activation point \
                    heistId=\(heistId.rawValue, privacy: .public) \
                    containerPath=\(containerPathDescription, privacy: .public) \
                    index=\(indexDescription, privacy: .public) \
                    point=(\(Double(point.x), privacy: .public), \(Double(point.y), privacy: .public))
                    """
                )

            case .multipleFirstResponders(let heistIds):
                insideJobLogger.warning(
                    "Multiple first responders detected: \(heistIds.map { $0.description }.joined(separator: ", "))"
                )
            }
        }
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

    private struct ScreenBuildProjection {
        let screen: Screen
        let logEvents: [ScreenBuildLogEvent]
    }

    private enum ScreenBuildLogEvent: Equatable {
        case capturedObservedScrollContentActivationPoint(
            heistId: HeistId,
            containerPath: TreePath,
            index: Int?,
            point: CGPoint
        )
        case multipleFirstResponders([HeistId])
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
