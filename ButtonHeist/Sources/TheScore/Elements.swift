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
        do {
            let keyed = try decoder.container(keyedBy: CodingKeys.self)
            if keyed.contains(.custom) {
                let name = try keyed.decode(String.self, forKey: .custom)
                self = .custom(name)
                return
            }
        } catch DecodingError.typeMismatch {
            // Not a keyed container — fall through to single-value decoding
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
    // Standard traits (public UIAccessibilityTraits, bits 0-14, 16-17)
    case button, link, image, staticText, header, adjustable
    case searchField, selected, notEnabled, keyboardKey
    case summaryElement, updatesFrequently, playsSound
    case startsMediaSession, allowsDirectInteraction
    case causesPageTurn, tabBar
    // Private traits — core set (used for element classification)
    case textEntry, isEditing, backButton, tabBarItem, textArea, switchButton
    // Private traits — extended set (from AXRuntime, surfaced for diagnostics)
    case webContent, pickerElement, radioButton, launchIcon, statusBarElement
    case secureTextField, inactive, footer, autoCorrectCandidate, deleteKey
    case selectionDismissesItem, visited, spacer, tableIndex, map
    case textOperationsAvailable, draggable, popupButton, menuItem, alert
    /// Unknown trait from a newer server — preserved for round-tripping.
    case unknown(String)

    /// Whether this trait is from the extended AXRuntime private set (not standard UIKit).
    /// Clients can use this to show/hide private diagnostic traits in their UI.
    public var isExtendedPrivate: Bool {
        Self.extendedPrivateSet.contains(self)
    }

    private static let extendedPrivateSet: Set<HeistTrait> = [
        .webContent, .pickerElement, .radioButton, .launchIcon, .statusBarElement,
        .secureTextField, .inactive, .footer, .autoCorrectCandidate, .deleteKey,
        .selectionDismissesItem, .visited, .spacer, .tableIndex, .map,
        .textOperationsAvailable, .draggable, .popupButton, .menuItem, .alert,
    ]
}

extension HeistTrait: CaseIterable {
    /// All known cases (excludes `.unknown`).
    public static var allCases: [HeistTrait] {
        [// Standard
         .button, .link, .image, .staticText, .header, .adjustable,
         .searchField, .selected, .notEnabled, .keyboardKey,
         .summaryElement, .updatesFrequently, .playsSound,
         .startsMediaSession, .allowsDirectInteraction,
         .causesPageTurn, .tabBar,
         // Private — core
         .textEntry, .isEditing, .backButton, .tabBarItem, .textArea, .switchButton,
         // Private — extended (AXRuntime)
         .webContent, .pickerElement, .radioButton, .launchIcon, .statusBarElement,
         .secureTextField, .inactive, .footer, .autoCorrectCandidate, .deleteKey,
         .selectionDismissesItem, .visited, .spacer, .tableIndex, .map,
         .textOperationsAvailable, .draggable, .popupButton, .menuItem, .alert]
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

// MARK: - Interface

/// A snapshot of the current accessibility interface returned by the server.
///
/// The wire shape carries a single canonical tree of `InterfaceNode` values
/// with `HeistElement` payloads at the leaves. There is no parallel flat
/// element array on the wire; `elements` is a depth-first flatten for source
/// compatibility with the few callers that want a flat list.
public struct Interface: Codable, Sendable {
    public let timestamp: Date
    public let tree: [InterfaceNode]

    // MARK: - Computed Properties

    /// Depth-first flatten of the tree. Returns every leaf element in
    /// VoiceOver traversal order. Computed; not stored on the wire.
    public var elements: [HeistElement] {
        tree.flatten()
    }

    /// Deterministic one-line screen summary built from element metadata.
    /// Format: "{screen name} — {interactive element counts}"
    public var screenDescription: String {
        Self.buildScreenDescription(from: elements)
    }

    /// Slugified screen name for machine use (e.g. "controls_demo").
    /// Derived from the first header element's label.
    public var screenId: String? {
        let screenName = elements
            .first(where: { $0.traits.contains(.header) })
            .flatMap(\.label)
        return slugify(screenName)
    }

    /// Structured navigation context extracted from element traits.
    /// Provides screen title, back button, and tab bar items with heistIds
    /// so agents can orient and navigate without scanning the element list.
    public var navigation: NavigationContext {
        Self.buildNavigation(from: elements)
    }

    public init(timestamp: Date, tree: [InterfaceNode]) {
        self.timestamp = timestamp
        self.tree = tree
    }

    // MARK: - Navigation Context

    static func buildNavigation(from elements: [HeistElement]) -> NavigationContext {
        let screenTitle = elements
            .first(where: { $0.traits.contains(.header) })
            .flatMap(\.label)

        let backButton = elements
            .first(where: { $0.traits.contains(.backButton) })
            .map { NavigationContext.NavigationItem(heistId: $0.heistId, label: $0.label, value: $0.value) }

        let tabBarItems = elements
            .filter { $0.traits.contains(.tabBarItem) }
            .map { element in
                NavigationContext.TabBarItem(
                    heistId: element.heistId,
                    label: element.label,
                    value: element.value,
                    selected: element.traits.contains(.selected)
                )
            }

        return NavigationContext(
            screenTitle: screenTitle,
            backButton: backButton,
            tabBarItems: tabBarItems.isEmpty ? nil : tabBarItems
        )
    }

    // MARK: - Deterministic Screen Description

    /// Build a one-line screen summary from element metadata.
    static func buildScreenDescription(from elements: [HeistElement]) -> String {
        let screenName = elements
            .first(where: { $0.traits.contains(.header) })
            .flatMap(\.label)

        var textFields = 0
        var buttons = 0
        var switches = 0
        var sliders = 0
        var searchFields = 0
        var links = 0
        var secureFields = 0

        for element in elements {
            let traits = element.traits
            if traits.contains(.secureTextField) {
                secureFields += 1
            } else if traits.contains(.textEntry) {
                textFields += 1
            } else if traits.contains(.searchField) {
                searchFields += 1
            } else if traits.contains(.switchButton) {
                switches += 1
            } else if traits.contains(.adjustable) {
                sliders += 1
            } else if traits.contains(.link) {
                links += 1
            } else if traits.contains(.button) && !traits.contains(.backButton) {
                buttons += 1
            }
        }

        var parts: [String] = []
        if textFields > 0 { parts.append("\(textFields) text field\(textFields == 1 ? "" : "s")") }
        if secureFields > 0 { parts.append("\(secureFields) password field\(secureFields == 1 ? "" : "s")") }
        if searchFields > 0 { parts.append("\(searchFields) search field\(searchFields == 1 ? "" : "s")") }
        if buttons > 0 { parts.append("\(buttons) button\(buttons == 1 ? "" : "s")") }
        if switches > 0 { parts.append("\(switches) toggle\(switches == 1 ? "" : "s")") }
        if sliders > 0 { parts.append("\(sliders) slider\(sliders == 1 ? "" : "s")") }
        if links > 0 { parts.append("\(links) link\(links == 1 ? "" : "s")") }

        let summary = parts.joined(separator: ", ")

        if let name = screenName, !summary.isEmpty {
            return "\(name) — \(summary)"
        } else if let name = screenName {
            return name
        } else if !summary.isEmpty {
            return summary
        } else {
            return "\(elements.count) elements"
        }
    }
}

// MARK: - Navigation Context

/// Structured navigation context derived from element traits.
/// Gives agents immediate orientation — screen title, back button, and tab bar —
/// with heistIds for direct activation.
public struct NavigationContext: Codable, Equatable, Sendable {
    public struct NavigationItem: Codable, Equatable, Sendable {
        public let heistId: String
        public let label: String?
        public let value: String?

        public init(heistId: String, label: String?, value: String?) {
            self.heistId = heistId
            self.label = label
            self.value = value
        }
    }

    public struct TabBarItem: Codable, Equatable, Sendable {
        public let heistId: String
        public let label: String?
        public let value: String?
        public let selected: Bool

        public init(heistId: String, label: String?, value: String?, selected: Bool) {
            self.heistId = heistId
            self.label = label
            self.value = value
            self.selected = selected
        }
    }

    public let screenTitle: String?
    public let backButton: NavigationItem?
    public let tabBarItems: [TabBarItem]?

    public init(screenTitle: String?, backButton: NavigationItem?, tabBarItems: [TabBarItem]?) {
        self.screenTitle = screenTitle
        self.backButton = backButton
        self.tabBarItems = tabBarItems
    }
}

// MARK: - Slugify

/// Slugify a string for use as a machine-readable identifier.
/// Lowercase, replace non-alphanumeric runs with `_`, trim underscores, cap at 24 characters.
/// Shared by heistId synthesis (TheStash) and screenId derivation (Interface, ActionResult).
public func slugify(_ text: String?) -> String? {
    guard let text, !text.isEmpty else { return nil }
    let slug = text.lowercased()
        .replacing(/[^a-z0-9]+/, with: "_")
        .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    guard !slug.isEmpty else { return nil }
    return String(slug.prefix(24))
}

// MARK: - Identifier Stability

/// Whether an accessibility identifier is stable (developer-assigned) vs runtime-generated.
/// Returns false for identifiers containing UUIDs — these are SwiftUI runtime artifacts
/// that change across app launches and should not be used for element identity.
/// Shared by heistId synthesis (TheStash) and heist matcher construction (TheBookKeeper).
public func isStableIdentifier(_ identifier: String) -> Bool {
    identifier.range(of: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}",
                     options: .regularExpression) == nil
}

// MARK: - Interface Tree (canonical wire shape)

/// Container metadata for the canonical interface tree. Mirrors
/// `AccessibilitySnapshotParser.AccessibilityContainer` 1:1 but lives in
/// TheScore so CLI/MCP don't pull UIKit. Created by the iOS server when
/// converting the persistent registry tree to wire format.
public struct ContainerInfo: Equatable, Hashable, Sendable {
    public enum ContainerType: Equatable, Hashable, Sendable {
        case semanticGroup(label: String?, value: String?, identifier: String?)
        case list
        case landmark
        case dataTable(rowCount: Int, columnCount: Int)
        case tabBar
        case scrollable(contentWidth: Double, contentHeight: Double)
    }

    public let type: ContainerType
    public let frameX: Double
    public let frameY: Double
    public let frameWidth: Double
    public let frameHeight: Double

    public init(
        type: ContainerType,
        frameX: Double,
        frameY: Double,
        frameWidth: Double,
        frameHeight: Double
    ) {
        self.type = type
        self.frameX = frameX
        self.frameY = frameY
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
    }
}

/// Coding keys shared by `ContainerInfo` and `InterfaceNode`'s container case
/// so the discriminator + payload + frame all live at one level on the wire,
/// matching the documented protocol shape.
private enum ContainerCodingKey: String, CodingKey {
    case type
    case label, value, identifier
    case contentWidth, contentHeight
    case rowCount, columnCount
    case frameX, frameY, frameWidth, frameHeight
    case children
}

extension ContainerInfo: Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ContainerCodingKey.self)
        try Self.encodeShape(self, into: &container)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ContainerCodingKey.self)
        self = try Self.decodeShape(from: container)
    }

    fileprivate static func encodeShape(
        _ info: ContainerInfo,
        into container: inout KeyedEncodingContainer<ContainerCodingKey>
    ) throws {
        switch info.type {
        case let .semanticGroup(label, value, identifier):
            try container.encode("semanticGroup", forKey: .type)
            try container.encodeIfPresent(label, forKey: .label)
            try container.encodeIfPresent(value, forKey: .value)
            try container.encodeIfPresent(identifier, forKey: .identifier)
        case .list:
            try container.encode("list", forKey: .type)
        case .landmark:
            try container.encode("landmark", forKey: .type)
        case let .dataTable(rowCount, columnCount):
            try container.encode("dataTable", forKey: .type)
            try container.encode(rowCount, forKey: .rowCount)
            try container.encode(columnCount, forKey: .columnCount)
        case .tabBar:
            try container.encode("tabBar", forKey: .type)
        case let .scrollable(contentWidth, contentHeight):
            try container.encode("scrollable", forKey: .type)
            try container.encode(contentWidth, forKey: .contentWidth)
            try container.encode(contentHeight, forKey: .contentHeight)
        }
        try container.encode(info.frameX, forKey: .frameX)
        try container.encode(info.frameY, forKey: .frameY)
        try container.encode(info.frameWidth, forKey: .frameWidth)
        try container.encode(info.frameHeight, forKey: .frameHeight)
    }

    fileprivate static func decodeShape(
        from container: KeyedDecodingContainer<ContainerCodingKey>
    ) throws -> ContainerInfo {
        let typeName = try container.decode(String.self, forKey: .type)
        let type: ContainerType
        switch typeName {
        case "semanticGroup":
            type = .semanticGroup(
                label: try container.decodeIfPresent(String.self, forKey: .label),
                value: try container.decodeIfPresent(String.self, forKey: .value),
                identifier: try container.decodeIfPresent(String.self, forKey: .identifier)
            )
        case "list":
            type = .list
        case "landmark":
            type = .landmark
        case "dataTable":
            type = .dataTable(
                rowCount: try container.decode(Int.self, forKey: .rowCount),
                columnCount: try container.decode(Int.self, forKey: .columnCount)
            )
        case "tabBar":
            type = .tabBar
        case "scrollable":
            type = .scrollable(
                contentWidth: try container.decode(Double.self, forKey: .contentWidth),
                contentHeight: try container.decode(Double.self, forKey: .contentHeight)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: ContainerCodingKey.type,
                in: container,
                debugDescription: "Unknown container type: \(typeName)"
            )
        }
        return ContainerInfo(
            type: type,
            frameX: try container.decode(Double.self, forKey: .frameX),
            frameY: try container.decode(Double.self, forKey: .frameY),
            frameWidth: try container.decode(Double.self, forKey: .frameWidth),
            frameHeight: try container.decode(Double.self, forKey: .frameHeight)
        )
    }
}

/// A node in the canonical interface tree. Leaves carry the full
/// `HeistElement` payload — the tree is self-contained and there is no
/// parallel flat array on the wire.
public indirect enum InterfaceNode: Equatable, Hashable, Sendable {
    case element(HeistElement)
    case container(ContainerInfo, children: [InterfaceNode])
}

extension InterfaceNode: Codable {
    private enum NodeDiscriminator: String, CodingKey {
        case element
        case container
    }

    public func encode(to encoder: Encoder) throws {
        var outer = encoder.container(keyedBy: NodeDiscriminator.self)
        switch self {
        case .element(let element):
            try outer.encode(element, forKey: .element)
        case .container(let info, let children):
            var inner = outer.nestedContainer(keyedBy: ContainerCodingKey.self, forKey: .container)
            try ContainerInfo.encodeShape(info, into: &inner)
            try inner.encode(children, forKey: .children)
        }
    }

    public init(from decoder: Decoder) throws {
        let outer = try decoder.container(keyedBy: NodeDiscriminator.self)
        if outer.contains(.element) {
            self = .element(try outer.decode(HeistElement.self, forKey: .element))
        } else if outer.contains(.container) {
            let inner = try outer.nestedContainer(keyedBy: ContainerCodingKey.self, forKey: .container)
            let info = try ContainerInfo.decodeShape(from: inner)
            let children = try inner.decode([InterfaceNode].self, forKey: .children)
            self = .container(info, children: children)
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: NodeDiscriminator.element,
                in: outer,
                debugDescription: "InterfaceNode must be either .element or .container"
            )
        }
    }
}

public extension InterfaceNode {
    /// Depth-first flatten yielding every leaf element in traversal order.
    func flatten() -> [HeistElement] {
        switch self {
        case .element(let element):
            return [element]
        case .container(_, let children):
            return children.flatMap { $0.flatten() }
        }
    }
}

public extension Array where Element == InterfaceNode {
    /// Depth-first flatten across a forest.
    func flatten() -> [HeistElement] {
        flatMap { $0.flatten() }
    }
}

// MARK: - Heist Element

/// A UI element captured from the accessibility hierarchy.
/// Wraps the parser's AccessibilityElement with all its rich data in a wire-friendly form.
public struct HeistElement: Codable, Equatable, Hashable, Sendable {
    /// Stable, deterministic identifier for targeting this element.
    /// Developer-provided `accessibilityIdentifier` if present, otherwise synthesized
    /// from traits + label (or value as fallback). Unique within a snapshot.
    public var heistId: String
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
    /// Empty strings are treated as unset — they match nothing rather than everything.
    public var hasPredicates: Bool {
        label?.isEmpty == false || identifier?.isEmpty == false || value?.isEmpty == false || hasTraitPredicates
    }

    /// Returns `self` when at least one predicate field is set, else `nil`.
    /// Useful for chaining: an empty matcher shouldn't be sent over the wire,
    /// so callers can drop it with `matcher.nonEmpty`.
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
    /// AccessibilityElement.matches in TheStash+Matching.
    /// Unknown traits in required/excluded cause a miss (fail-safe).
    public func matches(_ matcher: ElementMatcher) -> Bool {
        if let matchLabel = matcher.label {
            if matchLabel.isEmpty { return false }
            guard let label, label.localizedCaseInsensitiveContains(matchLabel) else { return false }
        }
        if let matchId = matcher.identifier {
            if matchId.isEmpty { return false }
            guard let identifier, identifier.localizedCaseInsensitiveContains(matchId) else { return false }
        }
        if let matchVal = matcher.value {
            if matchVal.isEmpty { return false }
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
