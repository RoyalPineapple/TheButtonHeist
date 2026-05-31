import Foundation
import AccessibilitySnapshotModel

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
