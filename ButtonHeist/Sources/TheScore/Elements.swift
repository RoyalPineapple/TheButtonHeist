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

// MARK: - Heist Trait

/// Named accessibility traits as a typed enum.
/// Maps 1:1 to UIAccessibilityTraits bitmask values via TheBagman's traitMapping.
public enum HeistTrait: String, CaseIterable, Codable, Sendable {
    case button, link, image, staticText, header, adjustable
    case searchField, selected, notEnabled, keyboardKey
    case summaryElement, updatesFrequently, playsSound
    case startsMediaSession, allowsDirectInteraction
    case causesPageTurn, tabBar, backButton
}

// MARK: - Group Type

/// Container group classification in the element tree.
public enum GroupType: String, Codable, Sendable, CaseIterable, Equatable, Hashable {
    case semanticGroup, list, landmark, dataTable, tabBar
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
    public let type: GroupType
    public let label: String?
    public let value: String?
    public let identifier: String?
    public let frameX: Double
    public let frameY: Double
    public let frameWidth: Double
    public let frameHeight: Double

    public init(
        type: GroupType,
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
    /// Stable, deterministic identifier for targeting this element.
    /// Developer-provided `accessibilityIdentifier` if present, otherwise synthesized
    /// from traits + label (or value as fallback). Unique within a snapshot.
    public var heistId: String
    /// Element order in the snapshot (0-based)
    public var order: Int
    /// Human-readable description of the element
    public var description: String
    public var label: String?
    public var value: String?
    public var identifier: String?
    /// Accessibility hint (read by VoiceOver after the description)
    public var hint: String?
    /// Accessibility traits as typed enum values (e.g. [.button, .adjustable])
    public var traits: [HeistTrait]
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
        heistId: String = "",
        order: Int,
        description: String,
        label: String?,
        value: String?,
        identifier: String?,
        hint: String? = nil,
        traits: [HeistTrait] = [],
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
        self.heistId = heistId
        self.order = order
        self.description = description
        self.label = label
        self.value = value
        self.identifier = identifier
        self.hint = hint
        self.traits = traits
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

// MARK: - Element Matcher

/// Composable predicate for scanning the accessibility tree.
/// Controls which node types the matcher evaluates when walking the
/// accessibility hierarchy. Leaf elements are always eligible; containers
/// (nodes with children) are only evaluated when `containers` or `both`
/// is specified.
public enum MatchScope: String, Codable, Sendable, CaseIterable {
    /// Match leaf elements only (default behavior).
    case elements
    /// Match container nodes only.
    case containers
    /// Match both leaf elements and container nodes.
    case both
}

/// All non-nil fields must match (AND semantics). Wire type — the matching
/// logic itself lives as an extension on AccessibilityHierarchy in TheInsideJob,
/// where it operates on the canonical tree directly.
///
/// Trait values use the HeistTrait enum (e.g. .button, .header, .selected).
/// The hierarchy-level matcher bridges these to UIAccessibilityTraits bitmasks
/// via TheBagman's traitMapping.
public struct ElementMatcher: Codable, Sendable, Equatable {
    /// Exact match against element label
    public let label: String?
    /// Exact match against accessibility identifier
    public let identifier: String?
    /// Exact match against synthesized heistId (wire-level only)
    public let heistId: String?
    /// Exact match against element value
    public let value: String?
    /// All listed traits must be present on the element (AND)
    public let traits: [HeistTrait]?
    /// None of the listed traits may be present on the element
    public let excludeTraits: [HeistTrait]?
    /// Which node types to match: elements (leaves), containers, or both.
    /// Nil defaults to `.elements` for backward compatibility.
    public let scope: MatchScope?
    /// When true, the caller asserts no matching element exists.
    /// The matcher itself always checks property predicates; callers
    /// interpret `absent` based on their context.
    public let absent: Bool?

    public init(
        label: String? = nil,
        identifier: String? = nil,
        heistId: String? = nil,
        value: String? = nil,
        traits: [HeistTrait]? = nil,
        excludeTraits: [HeistTrait]? = nil,
        scope: MatchScope? = nil,
        absent: Bool? = nil
    ) {
        self.label = label
        self.identifier = identifier
        self.heistId = heistId
        self.value = value
        self.traits = traits
        self.excludeTraits = excludeTraits
        self.scope = scope
        self.absent = absent
    }

    /// Resolved scope — defaults to `.elements` when nil.
    public var resolvedScope: MatchScope { scope ?? .elements }
    public var isAbsent: Bool { absent ?? false }
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
