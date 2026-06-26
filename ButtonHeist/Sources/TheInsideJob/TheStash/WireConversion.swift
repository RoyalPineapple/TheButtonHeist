#if canImport(UIKit)
#if DEBUG
import UIKit
import os.log

import TheScore
import ThePlans

import AccessibilitySnapshotParser

private let wireConversionLogger = Logger(subsystem: "com.buttonheist.theinsidejob", category: "wireConversion")

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
        let activationPoint = element.bhResolvedActivationPoint
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
            activationPointX: activationPoint.x.sanitizedForJSON,
            activationPointY: activationPoint.y.sanitizedForJSON,
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

    static func buildActions(for element: AccessibilityElement) -> [ElementAction] {
        let isInteractive = Interactivity.isInteractive(element: element)
        let activate: [ElementAction] = isInteractive ? [.activate] : []
        let adjustable: [ElementAction] = (isInteractive && element.traits.contains(.adjustable))
            ? [.increment, .decrement]
            : []
        let custom = element.customActions
            .map { $0.name }
            .filter { !$0.isEmpty }
            .map(ElementAction.custom)
        return activate + adjustable + custom
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
            )
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
        let containerAnnotationsByPath = Dictionary(
            containerAnnotations.map { ($0.path, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        let liveIds = screen.liveCapture.heistIds
        let liveContainerNames = Set(containerAnnotations.compactMap(\.containerName))
        var emittedHeistIds = liveIds
        var emittedContainerNames = liveContainerNames
        var nextTraversalIndex = (screen.liveCapture.hierarchy.pathIndexedElements.map(\.traversalIndex).max() ?? -1) + 1

        var childrenByContainerName = DiscoveryChildren(
            screen: screen,
            liveIds: liveIds,
            liveContainerNames: liveContainerNames
        )

        func appendDiscoveryChildren(
            for containerName: ContainerName,
            to children: inout [AccessibilityHierarchy],
            path: TreePath
        ) {
            for child in childrenByContainerName.removeChildren(parent: containerName) {
                switch child.kind {
                case .element(let entry):
                    guard emittedHeistIds.insert(entry.heistId).inserted else { continue }
                    let childPath = path.appending(children.count)
                    children.append(.element(entry.element, traversalIndex: nextTraversalIndex))
                    nextTraversalIndex += 1
                    elementAnnotations.append(InterfaceElementAnnotation(
                        path: childPath,
                        actions: buildActions(for: entry.element),
                        contentSpaceOrigin: entry.contentSpaceOrigin.map(AccessibilityPoint.init)
                    ))
                case .container(let entry):
                    if let containerName = entry.containerName,
                       !emittedContainerNames.insert(containerName).inserted {
                        continue
                    }
                    let childPath = path.appending(children.count)
                    var nestedChildren: [AccessibilityHierarchy] = []
                    if let nestedContainerName = entry.containerName {
                        appendDiscoveryChildren(
                            for: nestedContainerName,
                            to: &nestedChildren,
                            path: childPath
                        )
                    }
                    children.append(.container(entry.container, children: nestedChildren))
                    containerAnnotations.append(InterfaceContainerAnnotation(
                        path: childPath,
                        containerName: entry.containerName
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
                if let containerName = containerAnnotationsByPath[path]?.containerName {
                    appendDiscoveryChildren(for: containerName, to: &convertedChildren, path: path)
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
            )
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
        let entries = screen.orderedElements
        let tree = entries.enumerated().map { index, entry in
            AccessibilityHierarchy.element(entry.element, traversalIndex: index)
        }
        let annotations = entries.enumerated().map { index, entry in
            InterfaceElementAnnotation(
                path: TreePath([index]),
                actions: buildActions(for: entry.element),
                contentSpaceOrigin: entry.contentSpaceOrigin.map(AccessibilityPoint.init)
            )
        }
        return Interface(
            timestamp: timestamp,
            tree: tree,
            annotations: InterfaceAnnotations(elements: annotations)
        )
    }

    // MARK: - Private Helpers

    private static func elementAnnotations(from screen: Screen) -> [InterfaceElementAnnotation] {
        screen.liveCapture.hierarchy.compactMapSubtrees { node, path in
            guard case .element(let element, _) = node else { return nil }
            let contentSpaceOrigin = screen.liveCapture.heistId(for: element)
                .flatMap { screen.semantic.elements[$0]?.contentSpaceOrigin }
            return InterfaceElementAnnotation(
                path: path,
                actions: buildActions(for: element),
                contentSpaceOrigin: contentSpaceOrigin.map(AccessibilityPoint.init)
            )
        }
    }

    private static func containerAnnotations(from screen: Screen) -> [InterfaceContainerAnnotation] {
        screen.liveCapture.hierarchy.compactMapSubtrees { node, path in
            guard case .container(let container, _) = node else { return nil }
            return InterfaceContainerAnnotation(
                path: path,
                containerName: screen.liveCapture.containerNamesByPath[path]
                    ?? screen.liveCapture.containerNames[container]
            )
        }
    }
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
        let y: CGFloat
        let x: CGFloat
        let stableName: String

        static func < (lhs: SortKey, rhs: SortKey) -> Bool {
            if lhs.y != rhs.y { return lhs.y < rhs.y }
            if lhs.x != rhs.x { return lhs.x < rhs.x }
            return lhs.stableName < rhs.stableName
        }
    }

    private var childrenByParent: [ContainerName: [Child]]

    init(
        screen: Screen,
        liveIds: Set<HeistId>,
        liveContainerNames: Set<ContainerName>
    ) {
        var childrenByParent: [ContainerName: [Child]] = [:]
        for entry in screen.semantic.elements.values {
            guard !liveIds.contains(entry.heistId),
                  let location = entry.scrollContentLocation
            else { continue }
            childrenByParent[location.scrollContainer, default: []].append(Child(
                sortKey: SortKey(
                    y: location.origin.y,
                    x: location.origin.x,
                    stableName: entry.heistId.rawValue
                ),
                kind: .element(entry)
            ))
        }
        for entry in screen.semantic.containers.values {
            guard let containerName = entry.containerName,
                  !liveContainerNames.contains(containerName),
                  let location = entry.scrollContentLocation
            else { continue }
            childrenByParent[location.scrollContainer, default: []].append(Child(
                sortKey: SortKey(
                    y: location.origin.y,
                    x: location.origin.x,
                    stableName: containerName.rawValue
                ),
                kind: .container(entry)
            ))
        }
        self.childrenByParent = childrenByParent.mapValues { children in
            children.sorted { $0.sortKey < $1.sortKey }
        }
    }

    mutating func removeChildren(parent: ContainerName) -> [Child] {
        childrenByParent.removeValue(forKey: parent) ?? []
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
