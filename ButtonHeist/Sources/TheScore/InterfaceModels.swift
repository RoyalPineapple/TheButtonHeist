import Foundation
import AccessibilitySnapshotModel

// MARK: - Interface

/// Position of a node in an accessibility hierarchy forest.
///
/// Paths are root-relative child indexes. The first root is `[0]`; its second
/// child is `[0, 1]`. They are capture-local, not durable identities.
public struct TreePath: Codable, Equatable, Hashable, Sendable {
    public let indices: [Int]

    public init(_ indices: [Int]) {
        self.indices = indices
    }

    public static let root = TreePath([])

    public func appending(_ index: Int) -> TreePath {
        TreePath(indices + [index])
    }
}

extension TreePath: Comparable {
    public static func < (lhs: TreePath, rhs: TreePath) -> Bool {
        for (left, right) in zip(lhs.indices, rhs.indices) where left != right {
            return left < right
        }
        return lhs.indices.count < rhs.indices.count
    }
}

/// Button Heist metadata attached to one parser element.
///
/// `AccessibilityElement` is the accessibility fact. These annotations are
/// BH affordances derived from a parse: targeting handle plus supported action
/// names. They are keyed by capture-local tree path so the accessibility tree
/// itself stays full-fidelity and unmodified.
public struct InterfaceElementAnnotation: Codable, Equatable, Hashable, Sendable {
    public let path: TreePath
    public let heistId: HeistId
    public let actions: [ElementAction]

    public init(path: TreePath, heistId: HeistId, actions: [ElementAction]) {
        self.path = path
        self.heistId = heistId
        self.actions = actions
    }
}

/// Button Heist metadata attached to one parser container.
///
/// Container type, modal state, and geometry live on `AccessibilityContainer`.
/// The only BH addition is the capture-local stable id used for subtree
/// targeting and tree-diff references.
public struct InterfaceContainerAnnotation: Codable, Equatable, Hashable, Sendable {
    public let path: TreePath
    public let stableId: HeistContainer?

    public init(path: TreePath, stableId: HeistContainer?) {
        self.path = path
        self.stableId = stableId
    }
}

/// Button Heist annotations for an `AccessibilityHierarchy` capture.
public struct InterfaceAnnotations: Codable, Equatable, Hashable, Sendable {
    public static let empty = InterfaceAnnotations()

    public let elements: [InterfaceElementAnnotation]
    public let containers: [InterfaceContainerAnnotation]

    public init(
        elements: [InterfaceElementAnnotation] = [],
        containers: [InterfaceContainerAnnotation] = []
    ) {
        self.elements = elements
        self.containers = containers
    }

    public var elementByPath: [TreePath: InterfaceElementAnnotation] {
        Dictionary(elements.map { ($0.path, $0) }, uniquingKeysWith: { _, latest in latest })
    }

    public var containerByPath: [TreePath: InterfaceContainerAnnotation] {
        Dictionary(containers.map { ($0.path, $0) }, uniquingKeysWith: { _, latest in latest })
    }
}

/// A snapshot of the current accessibility interface returned by the server.
///
/// The wire shape carries the parser's full-fidelity `AccessibilityHierarchy`
/// plus Button Heist annotations. There is no parallel lossy tree on the wire;
/// flat elements are an explicit projection for matching and formatting.
public struct Interface: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let tree: [AccessibilityHierarchy]
    public let annotations: InterfaceAnnotations

    private enum CodingKeys: String, CodingKey {
        case timestamp
        case tree
        case annotations
    }

    /// Button Heist element projection in VoiceOver traversal order.
    public var projectedElements: [HeistElement] {
        let annotationsByPath = annotations.elementByPath
        return tree.pathIndexedElements.map { element, path, _ in
            HeistElement(
                accessibilityElement: element,
                annotation: annotationsByPath[path]
            )
        }
    }

    public init(
        timestamp: Date,
        tree: [AccessibilityHierarchy],
        annotations: InterfaceAnnotations = .empty
    ) {
        self.timestamp = timestamp
        self.tree = tree
        self.annotations = annotations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        tree = try container
            .decode([InterfaceTreeWireNode].self, forKey: .tree)
            .map { $0.hierarchy }
        annotations = try container.decode(InterfaceAnnotations.self, forKey: .annotations)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(tree.map(InterfaceTreeWireNode.init), forKey: .tree)
        try container.encode(annotations, forKey: .annotations)
    }

    public func annotations(
        forSubtree node: AccessibilityHierarchy,
        originalPath: TreePath,
        rootPath: TreePath
    ) -> InterfaceAnnotations {
        let elementsByPath = annotations.elementByPath
        let elements = node.compactMapSubtrees(path: rootPath) { node, newPath -> InterfaceElementAnnotation? in
            guard case .element = node else { return nil }
            let relativePath = Array(newPath.indices.dropFirst(rootPath.indices.count))
            let oldPath = TreePath(originalPath.indices + relativePath)
            guard let annotation = elementsByPath[oldPath] else { return nil }
            return InterfaceElementAnnotation(
                path: newPath,
                heistId: annotation.heistId,
                actions: annotation.actions
            )
        }
        let containersByPath = annotations.containerByPath
        let containers = node.compactMapSubtrees(path: rootPath) { node, newPath -> InterfaceContainerAnnotation? in
            guard case .container = node else { return nil }
            let relativePath = Array(newPath.indices.dropFirst(rootPath.indices.count))
            let oldPath = TreePath(originalPath.indices + relativePath)
            guard let annotation = containersByPath[oldPath] else { return nil }
            return InterfaceContainerAnnotation(
                path: newPath,
                stableId: annotation.stableId
            )
        }
        return InterfaceAnnotations(elements: elements, containers: containers)
    }

}

// MARK: - Interface Tree Wire Shape

private enum InterfaceTreeWireNode: Codable {
    case element(AccessibilityElement, traversalIndex: Int)
    case container(AccessibilityContainer, children: [InterfaceTreeWireNode])

    private enum CodingKeys: String, CodingKey {
        case element
        case container
    }

    init(_ hierarchy: AccessibilityHierarchy) {
        switch hierarchy {
        case .element(let element, let traversalIndex):
            self = .element(element, traversalIndex: traversalIndex)
        case .container(let container, let children):
            self = .container(container, children: children.map(Self.init))
        }
    }

    var hierarchy: AccessibilityHierarchy {
        switch self {
        case .element(let element, let traversalIndex):
            return .element(element, traversalIndex: traversalIndex)
        case .container(let container, let children):
            return .container(container, children: children.map { $0.hierarchy })
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch (container.contains(.element), container.contains(.container)) {
        case (true, false):
            let payload = try container.decode(InterfaceElementWirePayload.self, forKey: .element)
            self = .element(payload.element, traversalIndex: payload.traversalIndex)
        case (false, true):
            let payload = try container.decode(InterfaceContainerWirePayload.self, forKey: .container)
            self = .container(payload.container, children: payload.children)
        case (true, true):
            throw DecodingError.dataCorruptedError(
                forKey: .element,
                in: container,
                debugDescription: "Interface tree node must contain exactly one of element or container"
            )
        case (false, false):
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Interface tree node requires element or container"
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .element(let element, let traversalIndex):
            try container.encode(
                InterfaceElementWirePayload(element: element, traversalIndex: traversalIndex),
                forKey: .element
            )
        case .container(let node, let children):
            try container.encode(
                InterfaceContainerWirePayload(container: node, children: children),
                forKey: .container
            )
        }
    }
}

private struct InterfaceElementWirePayload: Codable {
    let element: AccessibilityElement
    let traversalIndex: Int

    private enum CodingKeys: String, CodingKey {
        case traversalIndex
    }

    init(element: AccessibilityElement, traversalIndex: Int) {
        self.element = element
        self.traversalIndex = traversalIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        traversalIndex = try container.decode(Int.self, forKey: .traversalIndex)
        element = try AccessibilityElement(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        // The public wire shape intentionally flattens parser fields beside
        // Button Heist traversal metadata instead of exposing Swift enum wrappers.
        try element.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(traversalIndex, forKey: .traversalIndex)
    }
}

private struct InterfaceContainerWirePayload: Codable {
    let container: AccessibilityContainer
    let children: [InterfaceTreeWireNode]

    private enum CodingKeys: String, CodingKey {
        case children
    }

    init(container: AccessibilityContainer, children: [InterfaceTreeWireNode]) {
        self.container = container
        self.children = children
    }

    init(from decoder: Decoder) throws {
        let codingContainer = try decoder.container(keyedBy: CodingKeys.self)
        children = try codingContainer.decode([InterfaceTreeWireNode].self, forKey: .children)
        container = try AccessibilityContainer(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        // The public wire shape intentionally flattens parser fields beside
        // Button Heist hierarchy metadata instead of exposing Swift enum wrappers.
        try container.encode(to: encoder)
        var codingContainer = encoder.container(keyedBy: CodingKeys.self)
        try codingContainer.encode(children, forKey: .children)
    }
}

// MARK: - Parser Hierarchy Algebra

public extension AccessibilityHierarchy {
    func pathIndexedElements(path: TreePath = .root) -> [(element: AccessibilityElement, path: TreePath, traversalIndex: Int)] {
        switch self {
        case .element(let element, let traversalIndex):
            return [(element, path, traversalIndex)]
        case .container(_, let children):
            return children.enumerated().flatMap { index, child in
                child.pathIndexedElements(path: path.appending(index))
            }
        }
    }

    func compactMapSubtrees<Result>(
        path: TreePath = .root,
        _ transform: (AccessibilityHierarchy, TreePath) -> Result?
    ) -> [Result] {
        var results: [Result] = []
        if let result = transform(self, path) {
            results.append(result)
        }
        if case .container(_, let children) = self {
            for (index, child) in children.enumerated() {
                results.append(contentsOf: child.compactMapSubtrees(path: path.appending(index), transform))
            }
        }
        return results
    }

}

public extension Array where Element == AccessibilityHierarchy {
    var pathIndexedElements: [(element: AccessibilityElement, path: TreePath, traversalIndex: Int)] {
        enumerated()
            .flatMap { index, root in root.pathIndexedElements(path: TreePath([index])) }
            .sorted {
                if $0.traversalIndex != $1.traversalIndex {
                    return $0.traversalIndex < $1.traversalIndex
                }
                return $0.path < $1.path
            }
    }

    func compactMapSubtrees<Result>(
        _ transform: (AccessibilityHierarchy, TreePath) -> Result?
    ) -> [Result] {
        enumerated().flatMap { index, root in
            root.compactMapSubtrees(path: TreePath([index]), transform)
        }
    }
}

public extension AccessibilityTraits {
    private static let heistKnownTraits: [(trait: AccessibilityTraits, name: String)] = [
        (.button, HeistTrait.button.rawValue),
        (.link, HeistTrait.link.rawValue),
        (.image, HeistTrait.image.rawValue),
        (.selected, HeistTrait.selected.rawValue),
        (.playsSound, HeistTrait.playsSound.rawValue),
        (.keyboardKey, HeistTrait.keyboardKey.rawValue),
        (.staticText, HeistTrait.staticText.rawValue),
        (.summaryElement, HeistTrait.summaryElement.rawValue),
        (.notEnabled, HeistTrait.notEnabled.rawValue),
        (.updatesFrequently, HeistTrait.updatesFrequently.rawValue),
        (.searchField, HeistTrait.searchField.rawValue),
        (.startsMediaSession, HeistTrait.startsMediaSession.rawValue),
        (.adjustable, HeistTrait.adjustable.rawValue),
        (.allowsDirectInteraction, HeistTrait.allowsDirectInteraction.rawValue),
        (.causesPageTurn, HeistTrait.causesPageTurn.rawValue),
        (.header, HeistTrait.header.rawValue),
        (.tabBar, HeistTrait.tabBar.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 17), HeistTrait.webContent.rawValue),
        (.textEntry, HeistTrait.textEntry.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 19), HeistTrait.pickerElement.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 20), HeistTrait.radioButton.rawValue),
        (.isEditing, HeistTrait.isEditing.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 22), HeistTrait.launchIcon.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 23), HeistTrait.statusBarElement.rawValue),
        (.secureTextField, HeistTrait.secureTextField.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 25), HeistTrait.inactive.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 26), HeistTrait.footer.rawValue),
        (.backButton, HeistTrait.backButton.rawValue),
        (.tabBarItem, HeistTrait.tabBarItem.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 29), HeistTrait.autoCorrectCandidate.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 30), HeistTrait.deleteKey.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 31), HeistTrait.selectionDismissesItem.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 32), HeistTrait.visited.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 34), HeistTrait.spacer.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 35), HeistTrait.tableIndex.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 36), HeistTrait.map.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 37), HeistTrait.textOperationsAvailable.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 38), HeistTrait.draggable.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 40), HeistTrait.popupButton.rawValue),
        (.textArea, HeistTrait.textArea.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 52), HeistTrait.menuItem.rawValue),
        (.switchButton, HeistTrait.switchButton.rawValue),
        (.alert, HeistTrait.alert.rawValue),
    ]

    static var knownTraitNames: Set<String> {
        Set(heistKnownTraits.map { $0.name })
    }

    static func fromNames(_ names: [String]) -> AccessibilityTraits {
        var value: UInt64 = 0
        for name in names {
            if let known = heistKnownTraits.first(where: { $0.name == name }) {
                value |= known.trait.rawValue
            }
        }
        return AccessibilityTraits(rawValue: value)
    }

    var heistTraits: [HeistTrait] {
        Self.heistKnownTraits.compactMap { contains($0.trait) ? HeistTrait(rawValue: $0.name) : nil }
    }

    var heistTraitNames: [String] {
        Self.heistKnownTraits.compactMap { contains($0.trait) ? $0.name : nil }
    }
}
