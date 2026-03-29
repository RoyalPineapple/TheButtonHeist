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
        if let keyed = try? decoder.container(keyedBy: CodingKeys.self),
           let name = try? keyed.decode(String.self, forKey: .custom) {
            self = .custom(name)
            return
        }
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
        case "activate": self = .activate
        case "increment": self = .increment
        case "decrement": self = .decrement
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown ElementAction: \"\(value)\". Use {\"custom\":\"\(value)\"} for custom actions."
            )
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

/// Named accessibility traits — aligned 1:1 with the AccessibilitySnapshot parser's
/// `knownTraits` in `AccessibilityHierarchy+Codable.swift`.
/// Standard UIAccessibilityTraits plus private traits the parser exposes.
public enum HeistTrait: Equatable, Hashable, Sendable {
    // Standard traits
    case button, link, image, staticText, header, adjustable
    case searchField, selected, notEnabled, keyboardKey
    case summaryElement, updatesFrequently, playsSound
    case startsMediaSession, allowsDirectInteraction
    case causesPageTurn, tabBar
    // Private traits (from UIAccessibility+SnapshotAdditions)
    case textEntry, isEditing, backButton, tabBarItem, scrollable, switchButton
    /// Unknown trait from a newer server — preserved for round-tripping.
    case unknown(String)
}

extension HeistTrait: CaseIterable {
    /// All known cases (excludes `.unknown`).
    public static var allCases: [HeistTrait] {
        [.button, .link, .image, .staticText, .header, .adjustable,
         .searchField, .selected, .notEnabled, .keyboardKey,
         .summaryElement, .updatesFrequently, .playsSound,
         .startsMediaSession, .allowsDirectInteraction,
         .causesPageTurn, .tabBar,
         .textEntry, .isEditing, .backButton, .tabBarItem, .scrollable, .switchButton]
    }
}

extension HeistTrait: RawRepresentable {
    private static let nameToTrait: [String: HeistTrait] = {
        var map: [String: HeistTrait] = [:]
        for c in allCases { map[c.nameValue] = c }
        return map
    }()

    /// Returns nil for unknown trait strings. Use Codable for forward-compatible decoding.
    public init?(rawValue: String) {
        guard let known = Self.nameToTrait[rawValue] else { return nil }
        self = known
    }

    /// The string name for known cases. `.unknown` stores its own value.
    private var nameValue: String {
        switch self {
        case .unknown(let value): return value
        default: return String(describing: self)
        }
    }

    public var rawValue: String { nameValue }
}

extension HeistTrait: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = HeistTrait(rawValue: value) ?? .unknown(value)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Group Type

/// Container group classification in the element tree.
public enum GroupType: Equatable, Hashable, Sendable {
    case semanticGroup, list, landmark, dataTable, tabBar, scrollable
    case unknown(String)
}

extension GroupType: CaseIterable {
    public static var allCases: [GroupType] {
        [.semanticGroup, .list, .landmark, .dataTable, .tabBar, .scrollable]
    }
}

extension GroupType: RawRepresentable {
    public init?(rawValue: String) {
        switch rawValue {
        case "semanticGroup": self = .semanticGroup
        case "list": self = .list
        case "landmark": self = .landmark
        case "dataTable": self = .dataTable
        case "tabBar": self = .tabBar
        case "scrollable": self = .scrollable
        default: return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .semanticGroup: return "semanticGroup"
        case .list: return "list"
        case .landmark: return "landmark"
        case .dataTable: return "dataTable"
        case .tabBar: return "tabBar"
        case .scrollable: return "scrollable"
        case .unknown(let value): return value
        }
    }
}

extension GroupType: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = GroupType(rawValue: value) ?? .unknown(value)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
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
/// All non-nil fields must match (AND semantics). Wire type — the matching
/// logic itself lives as an extension on AccessibilityHierarchy in TheInsideJob,
/// where it operates on the canonical tree directly.
///
/// Trait values use the HeistTrait enum (e.g. .button, .header, .selected).
/// The hierarchy-level matcher bridges these to UIAccessibilityTraits bitmasks
/// via AccessibilitySnapshotParser's knownTraits.
public struct ElementMatcher: Codable, Sendable, Equatable {
    /// Case-insensitive substring match against element label
    public let label: String?
    /// Case-insensitive substring match against accessibility identifier
    public let identifier: String?
    /// Case-insensitive substring match against element value
    public let value: String?
    /// All listed traits must be present on the element (AND)
    public let traits: [HeistTrait]?
    /// None of the listed traits may be present on the element
    public let excludeTraits: [HeistTrait]?

    public init(
        label: String? = nil,
        identifier: String? = nil,
        value: String? = nil,
        traits: [HeistTrait]? = nil,
        excludeTraits: [HeistTrait]? = nil
    ) {
        self.label = label
        self.identifier = identifier
        self.value = value
        self.traits = traits
        self.excludeTraits = excludeTraits
    }

    public var hasTraitPredicates: Bool {
        (traits?.isEmpty == false) || (excludeTraits?.isEmpty == false)
    }

    /// Whether any property predicate is set (label, identifier, value, traits, or excludeTraits).
    public var hasPredicates: Bool {
        label != nil || identifier != nil || value != nil || hasTraitPredicates
    }

    public var nonEmpty: Self? { hasPredicates ? self : nil }
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

    /// Known trait values. Used to reject unknown traits in matcher queries (fail-safe).
    private static let knownTraits = Set(HeistTrait.allCases)

    /// Match this wire element against an ElementMatcher predicate.
    /// Used for client-side filtering of serialized interface data (get_interface).
    /// String fields use case-insensitive substring matching, consistent with
    /// AccessibilityElement.matches in TheBagman+Matching.
    /// Unknown traits in required/excluded cause a miss (fail-safe).
    public func matches(_ matcher: ElementMatcher) -> Bool {
        if let matchLabel = matcher.label {
            guard let label, label.localizedCaseInsensitiveContains(matchLabel) else { return false }
        }
        if let matchId = matcher.identifier {
            guard let identifier, identifier.localizedCaseInsensitiveContains(matchId) else { return false }
        }
        if let matchVal = matcher.value {
            guard let value, value.localizedCaseInsensitiveContains(matchVal) else { return false }
        }
        let traitSet = matcher.hasTraitPredicates ? Set(traits) : []
        if let required = matcher.traits, !required.isEmpty {
            for t in required where !Self.knownTraits.contains(t) { return false }
            for t in required where !traitSet.contains(t) { return false }
        }
        if let excluded = matcher.excludeTraits, !excluded.isEmpty {
            for t in excluded where !Self.knownTraits.contains(t) { return false }
            for t in excluded where traitSet.contains(t) { return false }
        }
        return true
    }
}
