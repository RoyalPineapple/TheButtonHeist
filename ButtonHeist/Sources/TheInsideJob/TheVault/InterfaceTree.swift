#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore
import ThePlans

import AccessibilitySnapshotParser

// MARK: - Interface Tree

/// Button Heist's durable, targetable representation of the accessibility tree.
///
/// `InterfaceTree` contains targetable accessibility identity and value-only
/// reveal evidence. Its viewport snapshot records the latest parser hierarchy
/// and path identity used to reconcile the next observation; semantic values
/// are not projected into a second store. Live UIKit references remain in
/// `InterfaceObservation.liveCapture` and are reacquired for every action.
struct InterfaceTree: Sendable, Equatable {
    private let topology: Topology
    let viewportCapture: LiveCapture.Snapshot

    static let empty = InterfaceTree(elements: [:], containers: [:], viewportCapture: .empty)

    init(
        elements: [HeistId: Element],
        containers: [TreePath: Container] = [:],
        viewportCapture: LiveCapture.Snapshot = .empty
    ) {
        topology = Topology(
            elements: elements,
            containers: containers,
            preferredOrder: Self.viewportOrder(in: viewportCapture)
        )
        self.viewportCapture = viewportCapture
    }

    /// Indexed views admitted from the one semantic topology.
    ///
    /// The indexes accelerate target resolution; they do not own hierarchy or
    /// traversal order.
    var elements: [HeistId: Element] {
        topology.elements
    }

    var containers: [TreePath: Container] {
        topology.containers
    }

    var elementIDs: Set<HeistId> {
        Set(elements.keys)
    }

    var viewportElementIDs: Set<HeistId> {
        Set(elements.values.compactMap { element in
            guard case .onscreen = element.geometry.screen else { return nil }
            return element.heistId
        })
    }

    var firstResponderHeistId: HeistId? {
        viewportCapture.firstResponderHeistId.flatMap { elements[$0]?.heistId }
    }

    func findElement(heistId: HeistId) -> Element? {
        topology.findElement(heistId: heistId)
    }

    /// Where every visible element sits, for asking whether the tree moved.
    ///
    /// Geometry is not durable identity: a predicate asks about labels and
    /// values, and a scroll that reveals nothing new is not a semantic change.
    /// But an element sliding into place *is* movement, and a reading taken
    /// mid-slide is not a still one — so stillness needs a separate question.
    ///
    /// Only viewport elements carry live geometry, so only they are asked.
    /// Frames are exact here; the comparison that reads them applies a
    /// touch-target tolerance, which is what keeps sub-pixel layout noise from
    /// preventing a `.noChange` event forever. See `CoarseFrameComparison`.
    var viewportFrames: [HeistId: CGRect] {
        var frames: [HeistId: CGRect] = [:]
        for element in elements.values {
            guard case .onscreen(let frame, _) = element.geometry.screen,
                  let rect = frame.rect
            else { continue }
            frames[element.heistId] = rect.cgRect
        }
        return frames
    }

    var orderedContainers: [Container] {
        topology.orderedContainers
    }

    var orderedElements: [Element] {
        topology.orderedElements
    }

    var viewportOnly: InterfaceTree {
        let containerPaths = Set(viewportCapture.hierarchy.pathIndexedContainers.map(\.path))
        return InterfaceTree(
            elements: elements.filter { viewportElementIDs.contains($0.key) },
            containers: containers.filter { containerPaths.contains($0.key) },
            viewportCapture: viewportCapture
        )
    }

    func merging(_ other: InterfaceTree) -> InterfaceTree {
        let nextVisible = other.viewportElementIDs
        let retainedElements = elements.mapValues { element in
            guard case .onscreen = element.geometry.screen,
                  !nextVisible.contains(element.heistId)
            else { return element }
            return element.withScreenSpace(.offscreen)
        }
        return Self(
            elements: retainedElements.merging(other.elements) { _, new in new },
            containers: containers.merging(other.containers) { _, new in new },
            viewportCapture: other.viewportCapture
        )
    }

    func updatingViewport(with next: InterfaceTree) -> InterfaceTree {
        guard next != .empty else { return .empty }
        let previousVisible = viewportElementIDs
        let disappearedVisible = previousVisible.subtracting(next.viewportElementIDs)
        let previousContainerPaths = Set(viewportCapture.hierarchy.pathIndexedContainers.map(\.path))
        let nextContainerPaths = Set(next.viewportCapture.hierarchy.pathIndexedContainers.map(\.path))
        let disappearedContainers = previousContainerPaths.subtracting(nextContainerPaths)
        let nextElements = elements
            .filter { !disappearedVisible.contains($0.key) }
            .merging(next.elements) { _, new in new }
        let retainedContainers = containers.filter { path, _ in
            !disappearedContainers.contains(path) || nextElements.values.contains {
                ($0.scrollMembership?.containerPath ?? $0.path).hasPrefix(path)
            }
        }
        return Self(
            elements: nextElements,
            containers: retainedContainers.merging(next.containers) { _, new in new },
            viewportCapture: next.viewportCapture
        )
    }

    private static func viewportOrder(in capture: LiveCapture.Snapshot) -> [Topology.NodeIdentity] {
        let containers = capture.hierarchy.pathIndexedContainers.map { item in
            (item.path, Topology.NodeIdentity.container(item.path))
        }
        let elements = capture.hierarchy.pathIndexedElements.compactMap { item in
            capture.heistIdsByPath[item.path].map { (item.path, Topology.NodeIdentity.element($0)) }
        }
        return (containers + elements).sorted { $0.0 < $1.0 }.map(\.1)
    }

    // MARK: - Admitted Topology

    /// Ordered semantic ownership admitted once from capture and merge input.
    ///
    /// `nodes` is the authoritative topology. Its two indexes are admitted
    /// once for resolution; they do not own parentage or traversal order.
    private struct Topology: Sendable, Equatable {
        enum NodeIdentity: Hashable, Sendable {
            case element(HeistId)
            case container(TreePath)
        }

        enum Payload: Sendable, Equatable {
            case element(Element)
            case container(Container)
        }
        struct Node: Sendable, Equatable {
            let path: TreePath
            let identity: NodeIdentity
            let payload: Payload
        }

        let nodes: [Node]
        private let elementNodeOffsetByHeistId: [HeistId: Int]
        private let containerNodeOffsetByPath: [TreePath: Int]
        let projectedContainerPathBySourcePath: [TreePath: TreePath]

        /// Derived lookup projections of the admitted node sequence. Topology
        /// owns the payloads; these values intentionally own no copies.
        var elements: [HeistId: Element] {
            Dictionary(
                uniqueKeysWithValues: elementNodeOffsetByHeistId.compactMap { heistId, offset in
                    guard nodes.indices.contains(offset),
                          case .element(let element) = nodes[offset].payload
                    else { return nil }
                    return (heistId, element)
                }
            )
        }

        var containers: [TreePath: Container] {
            Dictionary(
                uniqueKeysWithValues: containerNodeOffsetByPath.compactMap { path, offset in
                    guard nodes.indices.contains(offset),
                          case .container(let container) = nodes[offset].payload
                    else { return nil }
                    return (path, container)
                }
            )
        }

        func findElement(heistId: HeistId) -> Element? {
            guard let offset = elementNodeOffsetByHeistId[heistId],
                  nodes.indices.contains(offset),
                  case .element(let element) = nodes[offset].payload
            else { return nil }
            return element
        }

        var orderedElements: [Element] {
            nodes.compactMap { node in
                guard case .element(let element) = node.payload else { return nil }
                return element
            }
        }

        var orderedContainers: [Container] {
            nodes.compactMap { node in
                guard case .container(let container) = node.payload else { return nil }
                return container
            }
        }

        init(
            elements: [HeistId: Element],
            containers: [TreePath: Container],
            preferredOrder: [NodeIdentity]
        ) {
            let candidates = elements.map { heistId, element in
                Candidate.element(heistId: heistId, element: element)
            } + containers.map { path, container in
                Candidate.container(path: path, container: container)
            }
            let rank = Self.rank(candidates.map(\.identity), preferredOrder: preferredOrder)
            let children = Dictionary(grouping: candidates) { candidate in
                candidate.parent(admittedContainers: containers)
            }.mapValues { candidates in
                candidates.sorted {
                    rank[$0.identity, default: .max] < rank[$1.identity, default: .max]
                }
            }
            var admitted: [Node] = []
            func visit(_ candidates: [Candidate], parent: TreePath) {
                for (index, candidate) in candidates.enumerated() {
                    let path = parent.appending(index)
                    admitted.append(Node(
                        path: path,
                        identity: candidate.identity,
                        payload: candidate.payload
                    ))
                    if case .container(let container) = candidate.payload {
                        visit(children[container.path] ?? [], parent: path)
                    }
                }
            }
            visit(children[.root] ?? [], parent: .root)
            nodes = admitted
            var elementOffsets: [HeistId: Int] = [:]
            var containerOffsets: [TreePath: Int] = [:]
            var projectedPaths: [TreePath: TreePath] = [:]
            for (offset, node) in admitted.enumerated() {
                switch (node.identity, node.payload) {
                case (.element(let heistId), .element):
                    elementOffsets[heistId] = offset
                case (.container(let path), .container(let container)):
                    containerOffsets[path] = offset
                    projectedPaths[container.path] = node.path
                case (.element, .container), (.container, .element):
                    continue
                }
            }
            elementNodeOffsetByHeistId = elementOffsets
            containerNodeOffsetByPath = containerOffsets
            projectedContainerPathBySourcePath = projectedPaths
        }

        struct Candidate {
            let identity: NodeIdentity
            let payload: Payload
            static func element(heistId: HeistId, element: Element) -> Self {
                Self(identity: .element(heistId), payload: .element(element))
            }

            static func container(path: TreePath, container: Container) -> Self {
                Self(identity: .container(path), payload: .container(container))
            }

            /// Hierarchy ownership is carried by source paths. Scroll membership
            /// is reveal evidence, not topology: an explored off-viewport entry
            /// can retain it after its live scroll container leaves the capture.
            /// A partial discovery tree therefore promotes a missing ancestor to
            /// a root instead of depending on incidental flat-array order.
            func parent(admittedContainers: [TreePath: Container]) -> TreePath {
                guard let parent = sourcePath.parent,
                      admittedContainers[parent] != nil
                else { return .root }
                return parent
            }

            private var sourcePath: TreePath {
                switch payload {
                case .element(let element): element.path
                case .container(let container): container.path
                }
            }

        }

        private static func rank(
            _ identities: [NodeIdentity],
            preferredOrder: [NodeIdentity]
        ) -> [NodeIdentity: Int] {
            var ranks: [NodeIdentity: Int] = [:]
            for identity in preferredOrder where ranks[identity] == nil {
                ranks[identity] = ranks.count
            }
            for identity in identities.sorted(by: stableOrder) where ranks[identity] == nil {
                ranks[identity] = ranks.count
            }
            return ranks
        }

        private static func stableOrder(_ left: NodeIdentity, _ right: NodeIdentity) -> Bool {
            switch (left, right) {
            case let (.container(left), .container(right)): left < right
            case let (.element(left), .element(right)): left < right
            case (.container, .element): true
            case (.element, .container): false
            }
        }
    }

    var projectedContainerPathBySourcePath: [TreePath: TreePath] {
        topology.projectedContainerPathBySourcePath
    }

    func semanticInterface(timestamp: Date) -> Interface {
        let containerPaths = projectedContainerPathBySourcePath
        var elementAnnotations: [InterfaceElementAnnotation] = []
        var containerAnnotations: [InterfaceContainerAnnotation] = []
        var identities: [TreePath: Observation.ElementIdentity] = [:]
        var traversalIndex = 0
        var index = 0

        func project(parent: TreePath) -> [AccessibilityHierarchy] {
            var result: [AccessibilityHierarchy] = []
            while index < topology.nodes.count, topology.nodes[index].path.parent == parent {
                let node = topology.nodes[index]
                index += 1
                switch node.payload {
                case .element(let entry):
                    let ownerPath = entry.geometry.view.ownerPath
                    let projectedOwnerPath: TreePath
                    if ownerPath == .root {
                        projectedOwnerPath = .root
                    } else if let projected = containerPaths[ownerPath] {
                        projectedOwnerPath = projected
                    } else {
                        // Discovery may retain an off-viewport element after
                        // its source scroll container leaves the latest
                        // capture. The owner is live geometry evidence, so it
                        // cannot invent semantic topology; project it at the
                        // admitted root while retaining reveal membership on
                        // the semantic element itself.
                        projectedOwnerPath = .root
                    }
                    elementAnnotations.append(InterfaceElementAnnotation(
                        path: node.path,
                        actions: entry.element.projectedActionSet.orderedActions,
                        geometry: HeistElement.Geometry(
                            screen: entry.geometry.screen,
                            view: .init(
                                ownerPath: projectedOwnerPath,
                                frame: entry.geometry.view.frame,
                                activationPoint: entry.geometry.view.activationPoint
                            )
                        )
                    ))
                    identities[node.path] = entry.heistId.observationElementIdentity
                    result.append(.element(entry.element, traversalIndex: traversalIndex))
                    traversalIndex += 1
                case .container(let entry):
                    containerAnnotations.append(InterfaceContainerAnnotation(
                        path: node.path,
                        containerName: entry.containerName,
                        scrollInventory: entry.scrollInventory
                    ))
                    result.append(.container(entry.container, children: project(parent: node.path)))
                }
            }
            return result
        }

        let hierarchy = project(parent: .root)
        precondition(index == topology.nodes.count, "Admitted topology must be reachable from its roots")
        do {
            return try Interface(
                timestamp: timestamp,
                tree: hierarchy,
                annotations: InterfaceAnnotations(
                    elements: elementAnnotations,
                    containers: containerAnnotations
                ),
                observationIdentities: InterfaceElementIdentities(identities)
            )
        } catch {
            preconditionFailure("Admitted semantic topology must project a valid Interface: \(error)")
        }
    }

    // MARK: - Element Entry

    /// Durable scroll-container membership derived while walking the hierarchy.
    ///
    /// This is semantic placement evidence, not live action geometry: it records
    /// the owning scroll container and optional accessibility container index
    /// reported by UIKit. It deliberately cannot express an absolute scroll-content point.
    struct ScrollMembership: Sendable, Equatable {
        let containerPath: TreePath
        let index: Int?
    }

    struct Element: Sendable, Equatable {
        let heistId: HeistId
        let path: TreePath
        let scrollMembership: ScrollMembership?
        let geometry: HeistElement.Geometry
        /// Parsed accessibility identity/value retained in the interface tree.
        /// Do not treat its frame or activation point as live action geometry.
        let element: AccessibilityElement

        var scrollContainerPath: TreePath? {
            scrollMembership?.containerPath
        }

        var scrollIndex: Int? {
            scrollMembership?.index
        }

        init(
            heistId: HeistId,
            path: TreePath = .root,
            scrollMembership: ScrollMembership?,
            geometry: HeistElement.Geometry,
            element: AccessibilityElement
        ) {
            self.heistId = heistId
            self.path = path
            self.scrollMembership = scrollMembership
            self.geometry = geometry
            self.element = element
        }

        func withScreenSpace(
            _ screen: HeistElement.Geometry.ScreenSpace
        ) -> Self {
            Self(
                heistId: heistId,
                path: path,
                scrollMembership: scrollMembership,
                geometry: HeistElement.Geometry(
                    screen: screen,
                    view: geometry.view
                ),
                element: element
            )
        }
    }

    // MARK: - Container Entry

    /// Durable interface-tree container identity and scroll inventory evidence.
    ///
    /// UIKit object refs and live activation geometry remain in `LiveCapture`
    /// and are acquired only at dispatch time.
    struct Container: Sendable, Equatable {
        let container: AccessibilityContainer
        let path: TreePath
        let containerName: ContainerName?
        let viewSpace: HeistElement.Geometry.ViewSpace
        let scrollMembership: ScrollMembership?
        let scrollInventory: ScrollInventory?

        init(
            container: AccessibilityContainer,
            path: TreePath,
            containerName: ContainerName?,
            viewSpace: HeistElement.Geometry.ViewSpace,
            scrollMembership: ScrollMembership? = nil,
            scrollInventory: ScrollInventory? = nil
        ) {
            self.container = container
            self.path = path
            self.containerName = containerName
            self.viewSpace = viewSpace
            self.scrollMembership = scrollMembership
            self.scrollInventory = scrollInventory
        }
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
