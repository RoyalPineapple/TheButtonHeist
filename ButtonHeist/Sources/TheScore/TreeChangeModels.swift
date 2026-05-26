import Foundation
import AccessibilitySnapshotModel

// MARK: - Tree Edit Types

/// Stable identity namespace for a node in `Interface.tree`.
public enum TreeNodeKind: String, Codable, Sendable, Equatable, Hashable {
    case element
    case container
}

/// A stable reference to an existing tree node.
public struct TreeNodeRef: Codable, Sendable, Equatable, Hashable {
    public let id: String
    public let kind: TreeNodeKind

    public init(id: String, kind: TreeNodeKind) {
        self.id = id
        self.kind = kind
    }
}

/// A location in the interface tree. `parentId == nil` means the root forest.
public struct TreeLocation: Codable, Sendable, Equatable {
    public let parentId: HeistContainer?
    public let index: Int

    public init(parentId: HeistContainer?, index: Int) {
        self.parentId = parentId
        self.index = index
    }
}

/// A node inserted into `Interface.tree`.
public struct TreeInsertion: Codable, Sendable, Equatable {
    public let location: TreeLocation
    public let node: AccessibilityHierarchy
    public let annotations: InterfaceAnnotations

    public init(
        location: TreeLocation,
        node: AccessibilityHierarchy,
        annotations: InterfaceAnnotations = .empty
    ) {
        self.location = location
        self.node = node
        self.annotations = annotations
    }
}

/// A node removed from `Interface.tree`.
public struct TreeRemoval: Codable, Sendable, Equatable {
    public let ref: TreeNodeRef
    public let location: TreeLocation

    public init(ref: TreeNodeRef, location: TreeLocation) {
        self.ref = ref
        self.location = location
    }
}

/// An existing node moved within `Interface.tree`.
public struct TreeMove: Codable, Sendable, Equatable {
    public let ref: TreeNodeRef
    public let from: TreeLocation
    public let to: TreeLocation

    public init(ref: TreeNodeRef, from: TreeLocation, to: TreeLocation) {
        self.ref = ref
        self.from = from
        self.to = to
    }
}

/// Which accessibility property changed on an element.
public enum ElementProperty: String, Codable, Sendable, CaseIterable {
    case label
    case value
    case traits
    case hint
    case actions
    case frame
    case activationPoint
    case customContent
    case rotors

    /// Geometry properties: frame position/size and activation point coordinates.
    public var isGeometry: Bool {
        self == .frame || self == .activationPoint
    }
}

/// A single property change: what property, old value, new value.
public struct PropertyChange: Codable, Sendable, Equatable {
    public let property: ElementProperty
    public let old: String?
    public let new: String?

    public init(property: ElementProperty, old: String?, new: String?) {
        self.property = property
        self.old = old
        self.new = new
    }
}

/// An element whose state changed — carries the heistId and which properties differ.
public struct ElementUpdate: Codable, Sendable, Equatable {
    public let heistId: HeistId
    public let changes: [PropertyChange]

    public init(heistId: HeistId, changes: [PropertyChange]) {
        self.heistId = heistId
        self.changes = changes
    }
}
