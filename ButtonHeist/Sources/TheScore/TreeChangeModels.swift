import ThePlans
import Foundation
import AccessibilitySnapshotModel

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

/// An element whose state changed — carries both sides of the transition and
/// which properties differ.
public struct ElementUpdate: Codable, Sendable, Equatable {
    public let before: HeistElement
    public let after: HeistElement
    public let changes: [PropertyChange]

    public init(before: HeistElement, after: HeistElement, changes: [PropertyChange]) {
        self.before = before
        self.after = after
        self.changes = changes
    }
}
