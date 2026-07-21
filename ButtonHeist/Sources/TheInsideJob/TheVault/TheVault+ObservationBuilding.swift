#if canImport(UIKit)
#if DEBUG
import CryptoKit
import UIKit

import TheScore
import ThePlans

import AccessibilitySnapshotParser

extension TheVault {

    // MARK: - Build Interface Observation From Parse

    /// Build an `InterfaceObservation` from a parse result. UIKit/Objective-C reads are
    /// extracted into typed facts first; projection then assigns heistIds,
    /// resolves context, computes container names, and applies live facts.
    static func buildObservation(from result: CaptureResult) -> InterfaceObservation {
        do {
            return try admitObservation(from: result)
        } catch {
            preconditionFailure("InterfaceObservation build failed validation: \(error)")
        }
    }

    static func admitObservation(from result: CaptureResult) throws -> InterfaceObservation {
        let hierarchy = screenCoordinateHierarchy(from: result)
        let identityContext = buildIdentityContext(
            hierarchy: hierarchy,
            scrollableContainerPaths: BuildFacts.scrollContextContainerPaths(
                from: result
            )
        )
        let facts = BuildFacts.extract(
            from: result,
            identityContext: identityContext
        )
        let projection = buildObservationProjection(
            identityContext: identityContext,
            facts: facts,
            offscreenScrollElements: result.inventoryEnumeration.offscreenElements
        )
        logObservationBuildEvents(projection.logEvents)
        return try admitObservation(
            from: projection,
            result: result
        )
    }

    /// Entry used by focused tests with synthetic facts. Projection stays pure;
    /// live refs are attached afterward at the live-capture boundary.
    static func buildObservation(from result: CaptureResult, facts: BuildFacts) -> InterfaceObservation {
        let identityContext = buildIdentityContext(
            hierarchy: screenCoordinateHierarchy(from: result),
            scrollableContainerPaths: facts.scroll.contextContainerPaths
        )
        let projection = buildObservationProjection(
            identityContext: identityContext,
            facts: facts,
            offscreenScrollElements: []
        )
        return requireObservation(
            from: projection,
            result: result
        )
    }

    private static func buildObservationProjection(
        identityContext: IdentityContext,
        facts: BuildFacts,
        offscreenScrollElements: [OffscreenScrollElement]
    ) -> ObservationBuildProjection {
        let containerNamesByPath = buildContainerNamesByPath(
            identityContext: identityContext
        )

        let entries = buildObservationEntries(
            indexedElements: identityContext.elements,
            offscreenScrollElements: offscreenScrollElements,
            facts: facts
        )
        let heistIdsByPath = Dictionary(
            uniqueKeysWithValues: entries.compactMap { entry in
                entry.isInViewportCapture ? (entry.path, entry.heistId) : nil
            }
        )
        let containersByPath = viewportContainers(
            identityContext: identityContext,
            containerNamesByPath: containerNamesByPath,
            facts: facts
        )

        var logEvents: [ObservationBuildLogEvent] = []
        for entry in entries {
            if let observedScrollContentActivationPoint = entry.treeElement.observedScrollContentActivationPoint {
                logEvents.append(
                    .capturedObservedScrollContentActivationPoint(
                        heistId: entry.heistId,
                        containerPath: observedScrollContentActivationPoint.ownerPath,
                        index: entry.treeElement.scrollMembership?.index,
                        point: observedScrollContentActivationPoint.point.cgPoint
                    )
                )
            }
        }

        let firstResponders = entries.filter(\.isFirstResponder)
        if firstResponders.count > 1 {
            logEvents.append(.multipleFirstResponders(firstResponders.map(\.heistId)))
        }
        let firstResponderHeistId = firstResponders.count == 1
            ? firstResponders.first?.heistId
            : nil

        let snapshot = LiveCapture.Snapshot(
            hierarchy: identityContext.hierarchy,
            heistIdsByPath: heistIdsByPath,
            firstResponderHeistId: firstResponderHeistId
        )
        let tree = InterfaceTree(
            elements: Dictionary(
                uniqueKeysWithValues: entries.map { ($0.heistId, $0.treeElement) }
            ),
            containers: containersByPath,
            viewportCapture: snapshot
        )
        return ObservationBuildProjection(
            tree: tree,
            entries: entries,
            logEvents: logEvents
        )
    }

    private static func admitObservation(
        from projection: ObservationBuildProjection,
        result: CaptureResult
    ) throws -> InterfaceObservation {
        let liveReferences = ObservationLiveReferences(
            result: result,
            hierarchy: projection.tree.viewportCapture.hierarchy,
            entries: projection.entries
        )
        let dispatchReferences = LiveCapture.DispatchReferences(
            elementRefs: Dictionary(
                uniqueKeysWithValues: projection.entries.compactMap { entry in
                    liveReferences.elementRef(for: entry).map { (entry.heistId, $0) }
                }
            ),
            containerRefsByPath: liveReferences.containerRefsByPath,
            scrollableContainerViewsByPath: liveReferences.scrollableContainerViewsByPath
        )
        return try InterfaceObservation.build(
            tree: projection.tree,
            dispatchReferences: dispatchReferences
        )
    }

    private static func requireObservation(
        from projection: ObservationBuildProjection,
        result: CaptureResult
    ) -> InterfaceObservation {
        do {
            return try admitObservation(from: projection, result: result)
        } catch {
            preconditionFailure("InterfaceObservation build failed validation: \(error)")
        }
    }

    private static func buildObservationEntries(
        indexedElements: [ElementIdentity],
        offscreenScrollElements: [OffscreenScrollElement],
        facts: BuildFacts
    ) -> [ObservationBuildEntry] {
        let candidates = indexedElements.map(ObservationElementCandidate.viewport)
            + offscreenScrollElements.map(ObservationElementCandidate.offscreenScrollInventory)
        let heistIds = TheVault.IdAssignment.assign(candidates.map(\.element))
        precondition(
            heistIds.count == candidates.count,
            "IdAssignment must return one HeistId for each screen-build element"
        )
        return candidates.indices.map { index in
            let candidate = candidates[index]
            let heistId = heistIds[index]
            return ObservationBuildEntry(
                path: candidate.path,
                treeElement: InterfaceTree.Element(
                    heistId: heistId,
                    path: candidate.path,
                    scrollMembership: candidate.scrollMembership(facts: facts),
                    observedScrollContentActivationPoint: candidate.observedScrollContentActivationPoint(facts: facts),
                    element: candidate.element
                ),
                isFirstResponder: candidate.isFirstResponder(facts: facts),
                isInViewportCapture: candidate.isInViewportCapture
            )
        }
    }

    private static func viewportContainers(
        identityContext: IdentityContext,
        containerNamesByPath: [TreePath: ContainerName],
        facts: BuildFacts
    ) -> [TreePath: InterfaceTree.Container] {
        Dictionary(
            uniqueKeysWithValues: identityContext.containers.map { identity in
                (
                    identity.path,
                    InterfaceTree.Container(
                        container: identity.container,
                        path: identity.path,
                        containerName: containerNamesByPath[identity.path],
                        contentRect: identity.contentFrame,
                        scrollMembership: identity.scrollMembership,
                        observedScrollContentActivationPoint: facts.scroll
                            .containerObservedScrollContentActivationPointsByPath[identity.path],
                        scrollInventory: facts.scroll.inventoriesByPath[identity.path]
                    )
                )
            }
        )
    }

    /// The snapshot parser emits geometry in its parsing root's local
    /// coordinate space. Button Heist's interface tree and wire/element-inflation
    /// surfaces need UIKit accessibility screen coordinates, so restore those by
    /// applying each parse root's screen offset at the parser boundary.
    private static func screenCoordinateHierarchy(from result: CaptureResult) -> [AccessibilityHierarchy] {
        func translated(_ hierarchy: AccessibilityHierarchy, at path: TreePath, inherited: CGPoint) -> AccessibilityHierarchy {
            let offset = result.screenCoordinateOffsetsByPath[path] ?? inherited
            switch hierarchy {
            case .element(let element, let traversalIndex):
                return .element(element.translatedBy(x: offset.x, y: offset.y), traversalIndex: traversalIndex)
            case .container(let container, let children):
                return .container(
                    container.translatedBy(x: offset.x, y: offset.y),
                    children: children.enumerated().map { index, child in
                        translated(child, at: path.appending(index), inherited: offset)
                    }
                )
            }
        }
        return result.hierarchy.enumerated().map { rootIndex, root in
            translated(root, at: TreePath([rootIndex]), inherited: .zero)
        }
    }

    private static func logObservationBuildEvents(_ events: [ObservationBuildLogEvent]) {
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
        identityContext: IdentityContext
    ) -> [TreePath: ContainerName] {
        let candidates = identityContext.containers.map { identity in
            let readableName = containerName(
                for: identity.container,
                contentFrame: identity.contentFrame
            )
            return ContainerNameCandidate(
                path: identity.path,
                node: identity.subtree,
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
        ContainerName(stringLiteral: "\(readableName.rawValue)-\(containerHash(node: node, path: path))")
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

    private enum ObservationElementCandidate {
        case viewport(ElementIdentity)
        case offscreenScrollInventory(OffscreenScrollElement)

        var path: TreePath {
            switch self {
            case .viewport(let identity):
                identity.path
            case .offscreenScrollInventory(let element):
                element.path
            }
        }

        var element: AccessibilityElement {
            switch self {
            case .viewport(let identity):
                identity.element
            case .offscreenScrollInventory(let element):
                element.element
            }
        }

        var isInViewportCapture: Bool {
            switch self {
            case .viewport:
                true
            case .offscreenScrollInventory:
                false
            }
        }

        func scrollMembership(facts: BuildFacts) -> InterfaceTree.ScrollMembership? {
            switch self {
            case .viewport(let identity):
                facts.scroll.element(at: identity.path)?.membership
            case .offscreenScrollInventory(let element):
                InterfaceTree.ScrollMembership(
                    containerPath: element.scrollContainerPath,
                    index: element.scrollIndex
                )
            }
        }

        func observedScrollContentActivationPoint(
            facts: BuildFacts
        ) -> InterfaceTree.ObservedScrollContentActivationPoint? {
            switch self {
            case .viewport(let identity):
                facts.scroll.element(at: identity.path)?.observedScrollContentActivationPoint
            case .offscreenScrollInventory(let element):
                element.observedScrollContentActivationPoint
            }
        }

        func isFirstResponder(facts: BuildFacts) -> Bool {
            switch self {
            case .viewport(let identity):
                facts.focus.isFirstResponder(at: identity.path)
            case .offscreenScrollInventory:
                false
            }
        }
    }

    private struct ObservationBuildEntry: Equatable {
        let path: TreePath
        let treeElement: InterfaceTree.Element
        let isFirstResponder: Bool
        let isInViewportCapture: Bool

        var heistId: HeistId {
            treeElement.heistId
        }
    }

    private struct ObservationLiveReferences {
        private let objectsByPath: [TreePath: NSObject]
        private let scrollViewsByPath: [TreePath: UIScrollView]
        let containerRefsByPath: [TreePath: LiveCapture.ContainerRef]
        let scrollableContainerViewsByPath: [TreePath: LiveCapture.ScrollableViewRef]

        init(
            result: CaptureResult,
            hierarchy: [AccessibilityHierarchy],
            entries: [ObservationBuildEntry]
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

        func elementRef(for entry: ObservationBuildEntry) -> LiveCapture.ElementRef? {
            guard entry.isInViewportCapture else { return nil }
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

    private struct ObservationBuildProjection {
        let tree: InterfaceTree
        let entries: [ObservationBuildEntry]
        let logEvents: [ObservationBuildLogEvent]
    }

    private enum ObservationBuildLogEvent: Equatable {
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
            respondsToUserInteraction: respondsToUserInteraction,
            visibility: visibility
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
