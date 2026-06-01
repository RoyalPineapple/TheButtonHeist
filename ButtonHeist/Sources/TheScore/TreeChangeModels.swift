import Foundation
import AccessibilitySnapshotModel

/// Which accessibility property changed on an element.
public enum ElementProperty: String, Codable, Sendable, CaseIterable {
    // No `label`/`identifier`: those are element identity (diff pairing key), so a
    // change to them is a remove+add, never a property update.
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

/// An element whose state changed — carries the element itself (so the change
/// is self-describing on the wire) and which properties differ.
public struct ElementUpdate: Codable, Sendable, Equatable {
    public let element: HeistElement
    public let changes: [PropertyChange]

    public init(element: HeistElement, changes: [PropertyChange]) {
        self.element = element
        self.changes = changes
    }
}
