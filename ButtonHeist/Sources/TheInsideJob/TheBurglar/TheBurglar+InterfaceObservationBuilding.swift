#if canImport(UIKit)
#if DEBUG
import CryptoKit
import UIKit

import TheScore
import ThePlans

import AccessibilitySnapshotParser

extension TheBurglar {

    // MARK: - Build Interface Observation From Parse

    /// Build an `InterfaceObservation` from a parse result. UIKit/Objective-C reads are
    /// extracted into typed facts first; projection then assigns heistIds,
    /// resolves context, computes container names, and applies live facts.
    static func buildObservation(from result: ParseResult) -> InterfaceObservation {
        let hierarchy = screenCoordinateHierarchy(from: result)
        let facts = InterfaceObservationBuildFacts.extract(
            from: result,
            screenCoordinateHierarchy: hierarchy
        )
        let projection = buildObservationProjection(
            hierarchy: hierarchy,
            facts: facts
        )
        logObservationBuildEvents(projection.logEvents)
        return buildObservation(
            from: projection,
            result: result
        )
    }

    /// Entry used by focused tests with synthetic facts. Projection stays pure;
    /// live refs are attached afterward at the live-capture boundary.
    static func buildObservation(from result: ParseResult, facts: InterfaceObservationBuildFacts) -> InterfaceObservation {
        let projection = buildObservationProjection(
            hierarchy: screenCoordinateHierarchy(from: result),
            facts: facts
        )
        return buildObservation(
            from: projection,
            result: result
        )
    }

    private static func buildObservationProjection(
        hierarchy: [AccessibilityHierarchy],
        facts: InterfaceObservationBuildFacts
    ) -> InterfaceObservationBuildProjection {
        let indexedElements = hierarchy.pathIndexedElements
        let identityContext = buildContainerIdentityContext(
            hierarchy: hierarchy,
            scrollableContainerPaths: facts.scroll.contextContainerPaths
        )
        let containerNamesByPath = buildContainerNamesByPath(
            hierarchy: hierarchy,
            identityContext: identityContext
        )

        let entries = buildObservationEntries(
            indexedElements: indexedElements,
            facts: facts
        )

        var logEvents: [InterfaceObservationBuildLogEvent] = []
        for entry in entries {
            if let observedScrollContentActivationPoint = entry.treeElement.observedScrollContentActivationPoint,
               let scrollMembership = entry.treeElement.scrollMembership {
                logEvents.append(
                    .capturedObservedScrollContentActivationPoint(
                        heistId: entry.heistId,
                        containerPath: scrollMembership.containerPath,
                        index: scrollMembership.index,
                        point: observedScrollContentActivationPoint.point.cgPoint
                    )
                )
            }
        }

        let firstResponders = entries.filter(\.isFirstResponder)
        if firstResponders.count > 1 {
            logEvents.append(.multipleFirstResponders(firstResponders.map(\.heistId)))
        }

        let heistIdsByPath = Dictionary(
            uniqueKeysWithValues: entries.map { ($0.path, $0.heistId) }
        )
        let snapshot = LiveCapture.Snapshot(
            hierarchy: hierarchy,
            containerNamesByPath: containerNamesByPath,
            heistIdsByPath: heistIdsByPath,
            containerContentFramesByPath: identityContext.contentFramesByPath,
            containerScrollMembershipsByPath: identityContext.scrollMembershipsByPath,
            containerObservedScrollContentActivationPointsByPath: facts.scroll.containerObservedScrollContentActivationPointsByPath,
            scrollInventoriesByPath: facts.scroll.inventoriesByPath
        )
        let tree = InterfaceTree(
            elements: Dictionary(
                uniqueKeysWithValues: entries.map { ($0.heistId, $0.treeElement) }
            ),
            containers: semanticContainers(
                hierarchy: hierarchy,
                containerNamesByPath: containerNamesByPath,
                containerContentFramesByPath: identityContext.contentFramesByPath,
                containerScrollMembershipsByPath: identityContext.scrollMembershipsByPath,
                containerObservedScrollContentActivationPointsByPath: facts.scroll.containerObservedScrollContentActivationPointsByPath,
                scrollInventoriesByPath: facts.scroll.inventoriesByPath
            ),
            viewportCapture: snapshot
        )
        return InterfaceObservationBuildProjection(
            tree: tree,
            snapshot: snapshot,
            entries: entries,
            logEvents: logEvents
        )
    }

    private static func buildObservation(
        from projection: InterfaceObservationBuildProjection,
        result: ParseResult
    ) -> InterfaceObservation {
        let liveReferences = InterfaceObservationBuildLiveReferences(
            result: result,
            hierarchy: projection.snapshot.hierarchy,
            entries: projection.entries
        )
        let liveElementTable = makeLiveElementTable(
            entries: projection.entries,
            liveReferences: liveReferences
        )
        let liveCapture = LiveCapture(
            snapshot: projection.snapshot,
            liveElementTable: liveElementTable,
            containerRefsByPath: liveReferences.containerRefsByPath,
            scrollableContainerViewsByPath: liveReferences.scrollableContainerViewsByPath
        )
        return InterfaceObservation(
            tree: projection.tree,
            liveCapture: liveCapture
        )
    }

    private static func buildObservationEntries(
        indexedElements: [PathIndexedAccessibilityElement],
        facts: InterfaceObservationBuildFacts
    ) -> [InterfaceObservationBuildEntry] {
        let heistIds = TheStash.IdAssignment.assign(indexedElements.map(\.element))
        precondition(
            heistIds.count == indexedElements.count,
            "IdAssignment must return one HeistId for each screen-build element"
        )
        return indexedElements.indices.map { index in
            let indexedElement = indexedElements[index]
            let heistId = heistIds[index]
            let scrollFacts = facts.scroll.element(at: indexedElement.path)
            return InterfaceObservationBuildEntry(
                path: indexedElement.path,
                treeElement: InterfaceTree.Element(
                    heistId: heistId,
                    scrollMembership: scrollFacts?.membership,
                    observedScrollContentActivationPoint: scrollFacts?.observedScrollContentActivationPoint,
                    element: indexedElement.element
                ),
                isFirstResponder: facts.focus.isFirstResponder(at: indexedElement.path)
            )
        }
    }

    private static func makeLiveElementTable(
        entries: [InterfaceObservationBuildEntry],
        liveReferences: InterfaceObservationBuildLiveReferences
    ) -> LiveCapture.LiveElementTable {
        do {
            return try LiveCapture.LiveElementTable(entries: entries.map { entry in
                LiveCapture.LiveElementEntry(
                    path: entry.path,
                    treeElement: entry.treeElement,
                    ref: liveReferences.elementRef(for: entry),
                    isFirstResponder: entry.isFirstResponder
                )
            })
        } catch let error as LiveCapture.LiveElementTableValidationError {
            preconditionFailure(error.description)
        } catch {
            preconditionFailure("InterfaceObservation build failed to validate live element table: \(error)")
        }
    }

    private static func semanticContainers(
        hierarchy: [AccessibilityHierarchy],
        containerNamesByPath: [TreePath: ContainerName],
        containerContentFramesByPath: [TreePath: ContentRect],
        containerScrollMembershipsByPath: [TreePath: InterfaceTree.ScrollMembership],
        containerObservedScrollContentActivationPointsByPath: [TreePath: InterfaceTree.ObservedScrollContentActivationPoint],
        scrollInventoriesByPath: [TreePath: ScrollInventory]
    ) -> [TreePath: InterfaceTree.Container] {
        Dictionary(
            uniqueKeysWithValues: hierarchy.pathIndexedContainers.map { item in
                (
                    item.path,
                    InterfaceTree.Container(
                        container: item.container,
                        path: item.path,
                        containerName: containerNamesByPath[item.path],
                        contentRect: containerContentFramesByPath[item.path],
                        scrollMembership: containerScrollMembershipsByPath[item.path],
                        observedScrollContentActivationPoint: containerObservedScrollContentActivationPointsByPath[item.path],
                        scrollInventory: scrollInventoriesByPath[item.path]
                    )
                )
            }
        )
    }

    /// The snapshot parser emits geometry in its parsing root's local
    /// coordinate space. Button Heist's interface tree and wire/element-inflation
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

    private static func logObservationBuildEvents(_ events: [InterfaceObservationBuildLogEvent]) {
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
                ?? ContentRect(container.frame.cgRect)
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

    private struct InterfaceObservationBuildEntry: Equatable {
        let path: TreePath
        let treeElement: InterfaceTree.Element
        let isFirstResponder: Bool

        var heistId: HeistId {
            treeElement.heistId
        }
    }

    private struct InterfaceObservationBuildLiveReferences {
        private let objectsByPath: [TreePath: NSObject]
        private let scrollViewsByPath: [TreePath: UIScrollView]
        let containerRefsByPath: [TreePath: LiveCapture.ContainerRef]
        let scrollableContainerViewsByPath: [TreePath: LiveCapture.ScrollableViewRef]

        init(
            result: ParseResult,
            hierarchy: [AccessibilityHierarchy],
            entries: [InterfaceObservationBuildEntry]
        ) {
            let elementPaths = Set(entries.map(\.path))
            for path in result.objectsByPath.keys.sorted() where !elementPaths.contains(path) {
                preconditionFailure(
                    "InterfaceObservation build received live element object for non-element entry path \(path.indices)"
                )
            }
            for path in result.containerObjectsByPath.keys.sorted() {
                guard case .container = hierarchy.node(at: path) else {
                    preconditionFailure(
                        "InterfaceObservation build received live container object for non-container path \(path.indices)"
                    )
                }
            }
            for path in result.scrollViewsByPath.keys.sorted() {
                guard case .container(let container, _) = hierarchy.node(at: path),
                      container.isScrollable else {
                    preconditionFailure(
                        "InterfaceObservation build received live scroll view for non-scrollable container path \(path.indices)"
                    )
                }
            }

            objectsByPath = result.objectsByPath
            scrollViewsByPath = result.scrollViewsByPath
            containerRefsByPath = result.containerObjectsByPath.mapValues {
                LiveCapture.ContainerRef(object: $0)
            }
            scrollableContainerViewsByPath = result.scrollViewsByPath.mapValues {
                LiveCapture.ScrollableViewRef(view: $0)
            }
        }

        func elementRef(for entry: InterfaceObservationBuildEntry) -> LiveCapture.ElementRef? {
            let object = objectsByPath[entry.path]
            let scrollView = entry.treeElement.scrollMembership.flatMap { membership in
                scrollViewsByPath[membership.containerPath]
            }
            guard object != nil || scrollView != nil else { return nil }
            return LiveCapture.ElementRef(
                object: object,
                scrollView: scrollView
            )
        }
    }

    private struct InterfaceObservationBuildProjection {
        let tree: InterfaceTree
        let snapshot: LiveCapture.Snapshot
        let entries: [InterfaceObservationBuildEntry]
        let logEvents: [InterfaceObservationBuildLogEvent]
    }

    private enum InterfaceObservationBuildLogEvent: Equatable {
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
            identifier: identifier,
            scrollableContentSize: scrollableContentSize,
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
