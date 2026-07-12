#if canImport(UIKit)
#if DEBUG
import UIKit
import os.log

import TheScore
import ThePlans

import AccessibilitySnapshotParser

private let wireConversionLogger = ButtonHeistLog.logger(.insideJob(.wireConversion))

// MARK: - Float Sanitization

extension CGFloat {
    /// Replace NaN/infinity with 0 so JSONEncoder doesn't throw.
    /// UIPickerView's 3D-transformed cells can produce non-finite frame coordinates.
    var sanitizedForJSON: CGFloat {
        isFinite ? self : 0
    }
}

extension Double {
    /// Replace NaN/infinity with 0 so JSONEncoder doesn't throw.
    /// Portable parser points use Double instead of UIKit's CGFloat.
    var sanitizedForJSON: Double {
        isFinite ? self : 0
    }
}

// MARK: - Wire Conversion

extension TheStash {

    /// Convert internal accessibility types (`AccessibilityElement`,
    /// `AccessibilityHierarchy`, `Screen`) to their wire-facing projections.
    /// Pure transform — no stored state. Delta projection is capture-backed in
    /// TheScore.
    @MainActor enum WireConversion { // swiftlint:disable:this agent_main_actor_value_type

    // MARK: - Element Conversion

    static func convert(_ element: AccessibilityElement) -> HeistElement {
        let frame = element.bhFrame
        let activationPoint = activationPointEvidence(for: element)
        return HeistElement(
            description: element.description,
            label: element.label,
            value: element.value,
            identifier: element.identifier,
            hint: element.hint,
            traits: element.traits.heistTraits,
            frameX: frame.origin.x.sanitizedForJSON,
            frameY: frame.origin.y.sanitizedForJSON,
            frameWidth: frame.size.width.sanitizedForJSON,
            frameHeight: frame.size.height.sanitizedForJSON,
            activationPointEvidence: activationPoint,
            respondsToUserInteraction: element.respondsToUserInteraction,
            customContent: {
                let valid = element.customContent.filter { !$0.label.isEmpty || !$0.value.isEmpty }
                return valid.isEmpty ? nil : valid.map {
                    HeistCustomContent(label: $0.label, value: $0.value, isImportant: $0.isImportant)
                }
            }(),
            rotors: {
                let valid = element.customRotors.filter { !$0.name.isEmpty }
                return valid.isEmpty ? nil : valid.map { HeistRotor(name: $0.name) }
            }(),
            actions: buildActions(for: element)
        )
    }

    private static func activationPointEvidence(for element: AccessibilityElement) -> ActivationPointEvidence {
        let point = element.bhResolvedActivationPoint
        guard point.x.isFinite, point.y.isFinite else { return .unavailable }
        let screenPoint = ScreenPoint(x: Double(point.x), y: Double(point.y))
        return element.usesDefaultActivationPoint
            ? .defaultCenter(screenPoint)
            : .explicit(screenPoint)
    }

    static func buildActions(for element: AccessibilityElement) -> [ElementAction] {
        let isInteractive = Interactivity.isInteractive(element: element)
        let activate: [ElementAction] = isInteractive ? [.activate] : []
        let textEntry: [ElementAction] = AccessibilityPolicy.supportsTextEntry(element.traits.heistTraits)
            ? [.typeText]
            : []
        let adjustable: [ElementAction] = (isInteractive && element.traits.contains(.adjustable))
            ? [.increment, .decrement]
            : []
        let custom = element.customActions
            .map { $0.name }
            .filter { !$0.isEmpty }
            .map(ElementAction.custom)
        return activate + textEntry + adjustable + custom
    }

    // MARK: - Interface Conversion

    /// Convert a Screen into the canonical interface capture. The parser
    /// hierarchy remains the tree; Button Heist metadata is attached as
    /// annotations keyed by capture-local tree path.
    static func toInterface(from screen: Screen, timestamp: Date = Date()) -> Interface {
        Interface(
            timestamp: timestamp,
            tree: screen.liveCapture.hierarchy,
            annotations: InterfaceAnnotations(
                elements: elementAnnotations(from: screen),
                containers: containerAnnotations(from: screen)
            ),
            traceIdentities: traceIdentities(from: screen)
        )
    }

    /// Convert a Screen into the public discovery interface.
    ///
    /// The latest live capture is still the tree authority. Known off-viewport
    /// elements and containers discovered by scroll exploration are grafted
    /// under their owning semantic scroll container so public `get_interface`
    /// does not discard the command's exploration work.
    static func toDiscoveryInterface(from screen: Screen, timestamp: Date = Date()) -> Interface {
        var elementAnnotations = elementAnnotations(from: screen)
        var containerAnnotations = containerAnnotations(from: screen)
        var traceIdentitiesByPath = traceIdentities(from: screen).byPath
        let containerAnnotationsByPath = Dictionary(
            containerAnnotations.map { ($0.path, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        let liveIds = screen.liveCapture.heistIds
        let liveContainerPaths = Set(containerAnnotations.map(\.path))
        var emittedHeistIds = liveIds
        var emittedContainerPaths = liveContainerPaths
        var nextTraversalIndex = (screen.liveCapture.hierarchy.pathIndexedElements.map(\.traversalIndex).max() ?? -1) + 1

        var childrenByContainerPath = DiscoveryChildren(
            screen: screen,
            liveIds: liveIds,
            liveContainerPaths: liveContainerPaths
        )

        func appendDiscoveryChildren(
            for containerPath: TreePath,
            to children: inout [AccessibilityHierarchy],
            path: TreePath
        ) {
            for child in childrenByContainerPath.removeChildren(parent: containerPath) {
                switch child.kind {
                case .element(let entry):
                    guard emittedHeistIds.insert(entry.heistId).inserted else { continue }
                    let childPath = path.appending(children.count)
                    children.append(.element(entry.element, traversalIndex: nextTraversalIndex))
                    nextTraversalIndex += 1
                    traceIdentitiesByPath[childPath] = entry.heistId.traceElementIdentity
                    elementAnnotations.append(InterfaceElementAnnotation(
                        path: childPath,
                        actions: buildActions(for: entry.element)
                    ))
                case .container(let entry):
                    guard emittedContainerPaths.insert(entry.path).inserted else {
                        continue
                    }
                    let childPath = path.appending(children.count)
                    var nestedChildren: [AccessibilityHierarchy] = []
                    appendDiscoveryChildren(
                        for: entry.path,
                        to: &nestedChildren,
                        path: childPath
                    )
                    children.append(.container(entry.container, children: nestedChildren))
                    containerAnnotations.append(InterfaceContainerAnnotation(
                        path: childPath,
                        containerName: entry.containerName,
                        scrollInventory: entry.scrollInventory
                    ))
                }
            }
        }

        func convert(_ node: AccessibilityHierarchy, path: TreePath) -> AccessibilityHierarchy {
            switch node {
            case .element:
                return node
            case .container(let container, let children):
                var convertedChildren = children.enumerated().map { index, child in
                    convert(child, path: path.appending(index))
                }
                if containerAnnotationsByPath[path] != nil {
                    appendDiscoveryChildren(for: path, to: &convertedChildren, path: path)
                }
                return .container(container, children: convertedChildren)
            }
        }

        let tree = screen.liveCapture.hierarchy.enumerated().map { index, node in
            convert(node, path: TreePath([index]))
        }
        return Interface(
            timestamp: timestamp,
            tree: tree,
            annotations: InterfaceAnnotations(
                elements: elementAnnotations,
                containers: containerAnnotations
            ),
            traceIdentities: InterfaceTraceIdentities(traceIdentitiesByPath)
        )
    }

    /// Convert the committed semantic screen into a trace-facing interface.
    ///
    /// Exploration commits the full targetable element set into
    /// `screen.knownInterface`; the latest live capture remains viewport-local
    /// evidence for action dispatch. Post-action traces compare semantic
    /// captures, so known off-viewport elements must be present here even when
    /// they are absent from the latest live parser hierarchy.
    static func toSemanticInterface(from screen: Screen, timestamp: Date = Date()) -> Interface {
        semanticInterfaceProjection(from: screen, timestamp: timestamp).interface
    }

    static func semanticInterfaceProjection(
        from screen: Screen,
        timestamp: Date = Date()
    ) -> SemanticInterfaceProjection {
        let entries = screen.orderedElements
        return semanticInterfaceProjection(entries: entries, screen: screen, timestamp: timestamp)
    }

    private static func semanticInterfaceProjection(
        entries: [SemanticScreen.Element],
        screen: Screen,
        timestamp: Date
    ) -> SemanticInterfaceProjection {
        var pathAllocator = SemanticProjectionPathAllocator()
        let containerPlacements = semanticContainerPlacements(
            containersByPath: screen.semantic.containers,
            pathAllocator: &pathAllocator
        )
        let containersByProjectedPath = Dictionary(
            uniqueKeysWithValues: containerPlacements.map { ($0.path, $0.entry) }
        )
        let projectedContainerPathByOriginalPath = Dictionary(
            uniqueKeysWithValues: containerPlacements.map { ($0.entry.path, $0.path) }
        )
        let elementPlacements = semanticElementPlacements(
            entries: entries,
            projectedContainerPathByOriginalPath: projectedContainerPathByOriginalPath,
            pathAllocator: &pathAllocator
        )
        let elementsByPath = Dictionary(uniqueKeysWithValues: elementPlacements.map { ($0.path, $0.entry) })
        let traversalIndexByHeistId = Dictionary(uniqueKeysWithValues: entries.enumerated().map { index, entry in
            (entry.heistId, index)
        })
        let childPathsByParent = Dictionary(
            grouping: Array(elementsByPath.keys) + Array(containersByProjectedPath.keys)
        ) { path in
            path.parent ?? .root
        }.mapValues { paths in
            Array(Set(paths)).sorted()
        }

        var traversalIndex = 0
        var elementAnnotations: [InterfaceElementAnnotation] = []
        var containerAnnotations: [InterfaceContainerAnnotation] = []
        var traceIdentities: [TreePath: TraceElementIdentity] = [:]

        func buildNode(path: TreePath) -> AccessibilityHierarchy? {
            if let entry = elementsByPath[path] {
                let index = traversalIndex
                traversalIndex += 1
                elementAnnotations.append(InterfaceElementAnnotation(
                    path: path,
                    actions: buildActions(for: entry.element)
                ))
                traceIdentities[path] = entry.heistId.traceElementIdentity
                return .element(entry.element, traversalIndex: traversalIndexByHeistId[entry.heistId] ?? index)
            }
            guard let entry = containersByProjectedPath[path] else { return nil }
            containerAnnotations.append(InterfaceContainerAnnotation(
                path: path,
                containerName: entry.containerName,
                scrollInventory: entry.scrollInventory
            ))
            let children = (childPathsByParent[path] ?? []).compactMap(buildNode)
            return .container(entry.container, children: children)
        }

        let roots = (childPathsByParent[.root] ?? []).compactMap(buildNode)
        let interface = Interface(
            timestamp: timestamp,
            tree: roots,
            annotations: InterfaceAnnotations(
                elements: elementAnnotations,
                containers: containerAnnotations
            ),
            traceIdentities: InterfaceTraceIdentities(traceIdentities)
        )
        do {
            _ = try InterfaceGraph(interface: interface)
        } catch {
            wireConversionLogger.fault("Invalid semantic interface projection: \(String(describing: error), privacy: .public)")
            preconditionFailure("Invalid semantic interface projection: \(error)")
        }
        return SemanticInterfaceProjection(
            interface: interface,
            elementByProjectedPath: elementsByPath,
            containerByProjectedPath: containersByProjectedPath
        )
    }

    private static func semanticContainerPlacements(
        containersByPath: [TreePath: SemanticScreen.Container],
        pathAllocator: inout SemanticProjectionPathAllocator
    ) -> [SemanticContainerPlacement] {
        var projectedPathByOriginalPath: [TreePath: TreePath] = [:]

        return containersByPath.values
            .sorted { $0.path < $1.path }
            .map { entry in
                let parent = semanticContainerRepairParent(
                    for: entry,
                    projectedPathByOriginalPath: projectedPathByOriginalPath
                )
                let path = pathAllocator.nextChildPath(parent: parent)
                projectedPathByOriginalPath[entry.path] = path
                return SemanticContainerPlacement(path: path, entry: entry)
            }
    }

    private static func semanticElementPlacements(
        entries: [SemanticScreen.Element],
        projectedContainerPathByOriginalPath: [TreePath: TreePath],
        pathAllocator: inout SemanticProjectionPathAllocator
    ) -> [SemanticElementPlacement] {
        entries.map { entry in
            let parent = semanticElementRepairParent(
                for: entry,
                projectedContainerPathByOriginalPath: projectedContainerPathByOriginalPath
            )
            let path = pathAllocator.nextChildPath(parent: parent)
            return SemanticElementPlacement(path: path, entry: entry)
        }
    }

    private static func semanticContainerRepairParent(
        for entry: SemanticScreen.Container,
        projectedPathByOriginalPath: [TreePath: TreePath]
    ) -> TreePath {
        if let containerPath = entry.scrollMembership?.containerPath,
           let projectedPath = projectedPathByOriginalPath[containerPath] {
            return projectedPath
        }

        var parent = entry.path.parent
        while let candidate = parent {
            if candidate == .root { return .root }
            if let projectedPath = projectedPathByOriginalPath[candidate] {
                return projectedPath
            }
            parent = candidate.parent
        }
        return .root
    }

    private static func semanticElementRepairParent(
        for entry: SemanticScreen.Element,
        projectedContainerPathByOriginalPath: [TreePath: TreePath]
    ) -> TreePath {
        if let containerPath = entry.scrollMembership?.containerPath,
           let projectedPath = projectedContainerPathByOriginalPath[containerPath] {
            return projectedPath
        }

        var parent = entry.path.parent
        while let candidate = parent {
            if candidate == .root { return .root }
            if let projectedPath = projectedContainerPathByOriginalPath[candidate] {
                return projectedPath
            }
            parent = candidate.parent
        }
        return .root
    }

    // MARK: - Private Helpers

    private static func elementAnnotations(from screen: Screen) -> [InterfaceElementAnnotation] {
        screen.liveCapture.hierarchy.compactMapSubtrees { node, path in
            guard case .element(let element, _) = node else { return nil }
            return InterfaceElementAnnotation(
                path: path,
                actions: buildActions(for: element)
            )
        }
    }

    private static func traceIdentities(from screen: Screen) -> InterfaceTraceIdentities {
        InterfaceTraceIdentities(Dictionary(uniqueKeysWithValues: screen.liveCapture.heistIdsByPath.map { path, heistId in
            (path, heistId.traceElementIdentity)
        }))
    }

    private static func containerAnnotations(from screen: Screen) -> [InterfaceContainerAnnotation] {
        screen.liveCapture.hierarchy.compactMapSubtrees { node, path in
            guard case .container = node else { return nil }
            return InterfaceContainerAnnotation(
                path: path,
                containerName: screen.liveCapture.containerNamesByPath[path],
                scrollInventory: screen.liveCapture.scrollInventory(forPath: path)
            )
        }
    }
    }
}

struct SemanticInterfaceProjection {
    let interface: Interface
    let elementByProjectedPath: [TreePath: SemanticScreen.Element]
    let containerByProjectedPath: [TreePath: SemanticScreen.Container]
}

extension SemanticInterfaceProjection {
    func screenElements(matching matchSet: ElementMatchSet) -> [SemanticScreen.Element] {
        matchSet.matches.map { match in
            guard let screenElement = elementByProjectedPath[match.path] else {
                preconditionFailure("Semantic interface match path is not backed by a screen element")
            }
            return screenElement
        }
    }

    func screenElements(scopedBy target: AccessibilityTarget) -> [SemanticScreen.Element] {
        screenElements(scopedBy: target, ancestorPaths: nil)
    }

    func containers(matching predicate: ContainerPredicate) -> [SemanticScreen.Container] {
        containerPaths(matching: predicate, ancestorPaths: nil).map { path in
            guard let container = containerByProjectedPath[path] else {
                preconditionFailure("Semantic interface container path is not backed by a screen container")
            }
            return container
        }
    }

    private func screenElements(
        scopedBy target: AccessibilityTarget,
        ancestorPaths: [TreePath]?
    ) -> [SemanticScreen.Element] {
        switch target {
        case .predicate:
            return screenElements(ancestorPaths: ancestorPaths)
        case .within(let container, let nestedTarget):
            guard let predicate = try? container.resolve(in: .empty) else { return [] }
            let matchedContainerPaths = containerPaths(matching: predicate, ancestorPaths: ancestorPaths)
            guard !matchedContainerPaths.isEmpty else { return [] }
            return screenElements(scopedBy: nestedTarget, ancestorPaths: matchedContainerPaths)
        case .container(let container, let ordinal):
            guard let predicate = try? container.resolve(in: .empty) else { return [] }
            let matchedContainerPaths = containerPaths(matching: predicate, ancestorPaths: ancestorPaths)
            if let ordinal {
                guard matchedContainerPaths.indices.contains(ordinal) else { return [] }
                return screenElements(ancestorPaths: [matchedContainerPaths[ordinal]])
            }
            return screenElements(ancestorPaths: matchedContainerPaths)
        case .ref:
            return []
        }
    }

    private func screenElements(ancestorPaths: [TreePath]?) -> [SemanticScreen.Element] {
        interface.graph.elementsInTraversalOrder.map { record in
            guard record.path.isDescendant(ofAny: ancestorPaths) else { return nil }
            guard let screenElement = elementByProjectedPath[record.path] else {
                preconditionFailure("Semantic interface element path is not backed by a screen element")
            }
            return screenElement
        }.compactMap { $0 }
    }

    private func containerPaths(
        matching predicate: ContainerPredicate,
        ancestorPaths: [TreePath]?
    ) -> [TreePath] {
        interface.graph.nodesInPathOrder.compactMap { record in
            guard record.path.isDescendant(ofAny: ancestorPaths),
                  case .container(let containerRecord) = record.kind,
                  predicate.matches(containerRecord.container.containerPredicateFacts)
            else { return nil }
            return record.path
        }
    }
}

private extension TreePath {
    func isDescendant(ofAny ancestors: [TreePath]?) -> Bool {
        guard let ancestors else { return true }
        return ancestors.contains { hasPrefix($0) }
    }
}

private struct SemanticElementPlacement {
    let path: TreePath
    let entry: SemanticScreen.Element
}

private struct SemanticContainerPlacement {
    let path: TreePath
    let entry: SemanticScreen.Container
}

private struct SemanticProjectionPathAllocator {
    private var nextChildIndexByParent: [TreePath: Int] = [:]

    mutating func nextChildPath(parent: TreePath) -> TreePath {
        let index = nextChildIndexByParent[parent, default: 0]
        nextChildIndexByParent[parent] = index + 1
        return parent.appending(index)
    }
}

private struct DiscoveryChildren {
    enum ChildKind {
        case element(SemanticScreen.Element)
        case container(SemanticScreen.Container)
    }

    struct Child {
        let sortKey: SortKey
        let kind: ChildKind
    }

    struct SortKey: Comparable {
        let index: Int?
        let stableName: String

        static func < (lhs: SortKey, rhs: SortKey) -> Bool {
            switch (lhs.index, rhs.index) {
            case let (left?, right?) where left != right:
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                break
            }
            return lhs.stableName < rhs.stableName
        }
    }

    private var childrenByParent: [TreePath: [Child]]

    init(
        screen: Screen,
        liveIds: Set<HeistId>,
        liveContainerPaths: Set<TreePath>
    ) {
        var childrenByParent: [TreePath: [Child]] = [:]
        for entry in screen.semantic.elements.values {
            guard !liveIds.contains(entry.heistId),
                  let membership = entry.scrollMembership
            else { continue }
            childrenByParent[membership.containerPath, default: []].append(Child(
                sortKey: SortKey(
                    index: membership.index,
                    stableName: entry.heistId.rawValue
                ),
                kind: .element(entry)
            ))
        }
        for entry in screen.semantic.containers.values {
            guard !liveContainerPaths.contains(entry.path),
                  let membership = entry.scrollMembership
            else { continue }
            let stableName = entry.containerName?.rawValue ?? entry.path.indices.map(String.init).joined(separator: ".")
            childrenByParent[membership.containerPath, default: []].append(Child(
                sortKey: SortKey(
                    index: membership.index,
                    stableName: stableName
                ),
                kind: .container(entry)
            ))
        }
        self.childrenByParent = childrenByParent.mapValues { children in
            children.sorted { $0.sortKey < $1.sortKey }
        }
    }

    mutating func removeChildren(parent: TreePath) -> [Child] {
        childrenByParent.removeValue(forKey: parent) ?? []
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
