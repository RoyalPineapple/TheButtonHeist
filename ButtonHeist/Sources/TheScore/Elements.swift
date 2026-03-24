import Foundation
import CoreGraphics

// MARK: - Element Actions

/// Actions that can be performed on a UI element.
/// Built-in actions encode as plain strings ("activate", "increment", "decrement").
/// Custom actions encode as their name string directly.
public enum ElementAction: Equatable, Hashable, Sendable {
    case activate
    case increment
    case decrement
    case custom(String)
}

extension ElementAction: CustomStringConvertible {
    public var description: String {
        switch self {
        case .activate: return "activate"
        case .increment: return "increment"
        case .decrement: return "decrement"
        case .custom(let name): return name
        }
    }
}

extension ElementAction: Codable {
    private enum CodingKeys: String, CodingKey {
        case custom
    }

    public init(from decoder: Decoder) throws {
        // Try tagged object first: {"custom":"name"}
        if let keyed = try? decoder.container(keyedBy: CodingKeys.self),
           let name = try? keyed.decode(String.self, forKey: .custom) {
            self = .custom(name)
            return
        }
        // Fall back to plain string for built-in actions and legacy custom actions
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
        case "activate": self = .activate
        case "increment": self = .increment
        case "decrement": self = .decrement
        default: self = .custom(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .activate, .increment, .decrement:
            var container = encoder.singleValueContainer()
            try container.encode(description)
        case .custom(let name):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .custom)
        }
    }
}

// MARK: - Interface

public struct Interface: Codable, Sendable {
    public let timestamp: Date
    public let elements: [HeistElement]
    /// Optional tree structure for grouped display
    public let tree: [ElementNode]?

    public init(timestamp: Date, elements: [HeistElement], tree: [ElementNode]? = nil) {
        self.timestamp = timestamp
        self.elements = elements
        self.tree = tree
    }
}

// MARK: - Tree Types

/// A container group in the element tree
public struct Group: Codable, Equatable, Hashable, Sendable {
    /// Group type: "semanticGroup", "list", "landmark", "dataTable", "tabBar"
    public let type: String
    public let label: String?
    public let value: String?
    public let identifier: String?
    public let frameX: Double
    public let frameY: Double
    public let frameWidth: Double
    public let frameHeight: Double

    public init(
        type: String,
        label: String?,
        value: String?,
        identifier: String?,
        frameX: Double,
        frameY: Double,
        frameWidth: Double,
        frameHeight: Double
    ) {
        self.type = type
        self.label = label
        self.value = value
        self.identifier = identifier
        self.frameX = frameX
        self.frameY = frameY
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
    }
}

/// A node in the element tree
public indirect enum ElementNode: Codable, Equatable, Sendable {
    /// A leaf node representing an element by its order
    case element(order: Int)
    /// A container node grouping children
    case container(Group, children: [ElementNode])
}

// MARK: - Heist Element

/// A UI element captured from the accessibility hierarchy.
/// Wraps the parser's AccessibilityElement with all its rich data in a wire-friendly form.
public struct HeistElement: Codable, Equatable, Hashable, Sendable {
    /// Element order in the snapshot (0-based)
    public var order: Int
    /// Human-readable description of the element
    public var description: String
    public var label: String?
    public var value: String?
    public var identifier: String?
    /// Accessibility hint (read by VoiceOver after the description)
    public var hint: String?
    /// Accessibility traits as human-readable strings (e.g. ["button", "adjustable"])
    public var traits: [String]
    /// Raw UIAccessibilityTraits bitmask — preserves private traits (e.g. back button 0x8000000)
    /// that aren't in the named mapping. Used for topology-based screen change detection.
    public var rawTraits: UInt64?
    public var frameX: Double
    public var frameY: Double
    public var frameWidth: Double
    public var frameHeight: Double
    /// Activation point X coordinate (where VoiceOver would tap)
    public var activationPointX: Double
    /// Activation point Y coordinate
    public var activationPointY: Double
    /// Whether the element responds to user interaction
    public var respondsToUserInteraction: Bool
    /// Custom content label/value pairs provided by the element
    public var customContent: [HeistCustomContent]?
    /// Available actions for this element
    public var actions: [ElementAction]

    public init(
        order: Int,
        description: String,
        label: String?,
        value: String?,
        identifier: String?,
        hint: String? = nil,
        traits: [String] = [],
        rawTraits: UInt64? = nil,
        frameX: Double,
        frameY: Double,
        frameWidth: Double,
        frameHeight: Double,
        activationPointX: Double = 0,
        activationPointY: Double = 0,
        respondsToUserInteraction: Bool = true,
        customContent: [HeistCustomContent]? = nil,
        actions: [ElementAction]
    ) {
        self.order = order
        self.description = description
        self.label = label
        self.value = value
        self.identifier = identifier
        self.hint = hint
        self.traits = traits
        self.rawTraits = rawTraits
        self.frameX = frameX
        self.frameY = frameY
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        self.activationPointX = activationPointX
        self.activationPointY = activationPointY
        self.respondsToUserInteraction = respondsToUserInteraction
        self.customContent = customContent
        self.actions = actions
    }
}

/// Custom content attached to a HeistElement (maps to AccessibilityElement.CustomContent)
public struct HeistCustomContent: Codable, Equatable, Hashable, Sendable {
    public var label: String
    public var value: String
    public var isImportant: Bool

    public init(label: String, value: String, isImportant: Bool) {
        self.label = label
        self.value = value
        self.isImportant = isImportant
    }
}

// MARK: - Convenience Extensions

extension HeistElement {
    /// Computed frame as CGRect
    public var frame: CGRect {
        CGRect(x: frameX, y: frameY, width: frameWidth, height: frameHeight)
    }

    /// Computed activation point as CGPoint
    public var activationPoint: CGPoint {
        CGPoint(x: activationPointX, y: activationPointY)
    }
}
