import Foundation
import CoreGraphics
import AccessibilitySnapshotModel

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
/// names. They are keyed by parser traversal index so the accessibility tree
/// itself stays full-fidelity and unmodified.
public struct InterfaceElementAnnotation: Codable, Equatable, Hashable, Sendable {
    public let traversalIndex: Int
    public let heistId: String
    public let actions: [ElementAction]

    public init(traversalIndex: Int, heistId: String, actions: [ElementAction]) {
        self.traversalIndex = traversalIndex
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
    public let stableId: String?

    public init(path: TreePath, stableId: String?) {
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

    public var elementByTraversalIndex: [Int: InterfaceElementAnnotation] {
        Dictionary(uniqueKeysWithValues: elements.map { ($0.traversalIndex, $0) })
    }

    public var containerByPath: [TreePath: InterfaceContainerAnnotation] {
        Dictionary(uniqueKeysWithValues: containers.map { ($0.path, $0) })
    }
}

/// A snapshot of the current accessibility interface returned by the server.
///
/// The wire shape carries the parser's full-fidelity `AccessibilityHierarchy`
/// plus Button Heist annotations. There is no parallel lossy tree on the wire;
/// `elements` is a projection for matching and formatting.
public struct Interface: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let tree: [AccessibilityHierarchy]
    public let annotations: InterfaceAnnotations

    // MARK: - Computed Properties

    /// Button Heist element projection in VoiceOver traversal order.
    ///
    /// Computed from `tree + annotations`; not stored as a second source of
    /// truth on the wire.
    public var elements: [HeistElement] {
        let annotationsByIndex = annotations.elementByTraversalIndex
        return tree.indexedElements.map { element, traversalIndex in
            HeistElement(
                accessibilityElement: element,
                annotation: annotationsByIndex[traversalIndex]
            )
        }
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

    public init(
        timestamp: Date,
        tree: [AccessibilityHierarchy],
        annotations: InterfaceAnnotations = .empty
    ) {
        self.timestamp = timestamp
        self.tree = tree
        self.annotations = annotations
    }

    public func annotations(
        forSubtree node: AccessibilityHierarchy,
        originalPath: TreePath,
        rootPath: TreePath
    ) -> InterfaceAnnotations {
        let traversalIndices = Set(node.indexedElements.map(\.traversalIndex))
        let elements = annotations.elements.filter { traversalIndices.contains($0.traversalIndex) }
        let containersByPath = annotations.containerByPath
        let containers = node.compactMapSubtrees(path: rootPath) { node, newPath -> InterfaceContainerAnnotation? in
            guard case .container = node else { return nil }
            let relativePath = Array(newPath.indices.dropFirst(rootPath.indices.count))
            let oldPath = TreePath(originalPath.indices + relativePath)
            return InterfaceContainerAnnotation(
                path: newPath,
                stableId: containersByPath[oldPath]?.stableId
            )
        }
        return InterfaceAnnotations(elements: elements, containers: containers)
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

// MARK: - Parser Hierarchy Algebra

public extension AccessibilityHierarchy {
    var indexedElements: [(element: AccessibilityElement, traversalIndex: Int)] {
        switch self {
        case .element(let element, let traversalIndex):
            return [(element, traversalIndex)]
        case .container(_, let children):
            return children.flatMap(\.indexedElements)
        }
    }

    func folded<Result>(
        onElement: (AccessibilityElement, Int) -> Result,
        onContainer: (AccessibilityContainer, [Result]) -> Result
    ) -> Result {
        switch self {
        case .element(let element, let traversalIndex):
            return onElement(element, traversalIndex)
        case .container(let container, let children):
            return onContainer(
                container,
                children.map { $0.folded(onElement: onElement, onContainer: onContainer) }
            )
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

    func subtrees(where predicate: (AccessibilityHierarchy, TreePath) -> Bool) -> [AccessibilityHierarchy] {
        compactMapSubtrees { node, path in predicate(node, path) ? node : nil }
    }
}

public extension Array where Element == AccessibilityHierarchy {
    var indexedElements: [(element: AccessibilityElement, traversalIndex: Int)] {
        flatMap(\.indexedElements).sorted { $0.traversalIndex < $1.traversalIndex }
    }

    func compactMapSubtrees<Result>(
        _ transform: (AccessibilityHierarchy, TreePath) -> Result?
    ) -> [Result] {
        enumerated().flatMap { index, root in
            root.compactMapSubtrees(path: TreePath([index]), transform)
        }
    }

    func subtrees(where predicate: (AccessibilityHierarchy, TreePath) -> Bool) -> [AccessibilityHierarchy] {
        var results: [AccessibilityHierarchy] = []
        for (index, root) in enumerated() {
            results.append(contentsOf: root.subtrees { node, path in
                predicate(node, TreePath([index] + path.indices))
            })
        }
        return results
    }
}

public extension AccessibilityTraits {
    var heistTraits: [HeistTrait] {
        namesIncludingUnknownBits.map { HeistTrait(rawValue: $0) ?? .unknown($0) }
    }

    var namesIncludingUnknownBits: [String] {
        var result = traitNames
        var remaining = rawValue
        for (trait, _) in Self.knownTraits where contains(trait) {
            remaining &= ~trait.rawValue
        }
        if remaining != 0 {
            result.append("unknown(0x\(String(remaining, radix: 16)))")
        }
        return result
    }
}

// MARK: - Container Matching

/// Stable names for parser accessibility container categories.
public enum ContainerTypeName: String, Codable, CaseIterable, Sendable {
    case semanticGroup
    case list
    case landmark
    case dataTable
    case tabBar
    case scrollable
}

/// Exact selector for container nodes in an interface tree.
///
/// This is intentionally separate from `ElementMatcher`: elements and
/// containers have different identity fields and are matched in different tree
/// positions.
public struct ContainerMatcher: Codable, Sendable, Equatable {
    public let stableId: String?
    public let type: ContainerTypeName?
    public let label: String?
    public let value: String?
    public let identifier: String?
    public let isModalBoundary: Bool?

    public init(
        stableId: String? = nil,
        type: ContainerTypeName? = nil,
        label: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        isModalBoundary: Bool? = nil
    ) {
        self.stableId = stableId
        self.type = type
        self.label = label
        self.value = value
        self.identifier = identifier
        self.isModalBoundary = isModalBoundary
    }

    public var hasPredicates: Bool {
        stableId?.isEmpty == false || type != nil || label?.isEmpty == false ||
            value?.isEmpty == false || identifier?.isEmpty == false || isModalBoundary != nil
    }
}

// MARK: - Heist Element

/// A UI element captured from the accessibility hierarchy.
/// Wraps the parser's AccessibilityElement with all its rich data in a wire-friendly form.
public struct HeistElement: Codable, Equatable, Hashable, Sendable {
    /// Stable, deterministic identifier for targeting this element.
    /// Developer-provided `accessibilityIdentifier` if present, otherwise synthesized
    /// from traits + label (or value as fallback). Unique within a snapshot.
    public let heistId: String
    public let description: String
    public let label: String?
    public let value: String?
    public let identifier: String?
    /// Read by VoiceOver after the label/value.
    public let hint: String?
    public let traits: [HeistTrait]
    public let frameX: Double
    public let frameY: Double
    public let frameWidth: Double
    public let frameHeight: Double
    /// Where VoiceOver would tap, in screen coordinates. May fall outside `frame`.
    public let activationPointX: Double
    public let activationPointY: Double
    public let respondsToUserInteraction: Bool
    public let customContent: [HeistCustomContent]?
    public let rotors: [HeistRotor]?
    public let actions: [ElementAction]

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
        rotors: [HeistRotor]? = nil,
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
        self.rotors = rotors
        self.actions = actions
    }

}

public extension HeistElement {
    init(
        accessibilityElement element: AccessibilityElement,
        annotation: InterfaceElementAnnotation? = nil
    ) {
        let frame = element.shape.frame
        let validCustomContent = element.customContent.filter { !$0.label.isEmpty || !$0.value.isEmpty }
        let validRotors = element.customRotors.filter { !$0.name.isEmpty }
        self.init(
            heistId: annotation?.heistId ?? "",
            description: element.description,
            label: element.label,
            value: element.value,
            identifier: element.identifier,
            hint: element.hint,
            traits: element.traits.heistTraits,
            frameX: sanitizedDouble(frame.origin.x),
            frameY: sanitizedDouble(frame.origin.y),
            frameWidth: sanitizedDouble(frame.size.width),
            frameHeight: sanitizedDouble(frame.size.height),
            activationPointX: sanitizedDouble(element.activationPoint.x),
            activationPointY: sanitizedDouble(element.activationPoint.y),
            respondsToUserInteraction: element.respondsToUserInteraction,
            customContent: validCustomContent.isEmpty ? nil : validCustomContent.map {
                HeistCustomContent(label: $0.label, value: $0.value, isImportant: $0.isImportant)
            },
            rotors: validRotors.isEmpty ? nil : validRotors.map { HeistRotor(name: $0.name) },
            actions: annotation?.actions ?? []
        )
    }
}

private func sanitizedDouble(_ value: CGFloat) -> Double {
    value.isFinite ? Double(value) : 0
}

/// Rotor metadata attached to a HeistElement.
///
/// This intentionally describes availability only. Rotor results are discovered
/// live through a command because rotor movement is contextual and can be
/// direction-dependent or unbounded.
public struct HeistRotor: Codable, Equatable, Hashable, Sendable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

/// Custom content attached to a HeistElement (maps to AccessibilityElement.CustomContent)
public struct HeistCustomContent: Codable, Equatable, Hashable, Sendable {
    public let label: String
    public let value: String
    public let isImportant: Bool

    public init(label: String, value: String, isImportant: Bool) {
        self.label = label
        self.value = value
        self.isImportant = isImportant
    }
}

// MARK: - Element Matcher

/// Composable predicate for scanning the accessibility tree.
/// All non-nil fields must match (AND semantics).
///
/// Matching is **exact or miss**: `heistId` must equal the current leaf handle;
/// string fields (`label`, `identifier`, `value`) must equal the matcher value,
/// compared case-insensitively after typography folding (smart quotes/dashes/
/// ellipsis fold to ASCII; emoji, accents, and CJK pass through). Trait fields
/// use exact bitmask comparison.
///
/// There is no substring fallback. On miss, the resolver returns `.notFound`
/// with structured suggestions ("did you mean 'Save Draft' or 'Save All'?")
/// produced by the diagnostic / near-miss path. Agents who relied on substring
/// fallback must use the full label.
///
/// Trait values use the HeistTrait enum (e.g. .button, .header, .selected).
/// The hierarchy-level matcher bridges these to UIAccessibilityTraits bitmasks
/// via AccessibilitySnapshotParser's knownTraits.
public struct ElementMatcher: Codable, Sendable, Equatable {
    /// Exact match against the Button Heist leaf element handle
    public let heistId: String?
    /// Case-insensitive equality match against element label (typography-folded)
    public let label: String?
    /// Case-insensitive equality match against accessibility identifier (typography-folded)
    public let identifier: String?
    /// Case-insensitive equality match against element value (typography-folded)
    public let value: String?
    /// All listed traits must be present on the element (AND)
    public let traits: [HeistTrait]?
    /// None of the listed traits may be present on the element
    public let excludeTraits: [HeistTrait]?

    public init(
        heistId: String? = nil,
        label: String? = nil,
        identifier: String? = nil,
        value: String? = nil,
        traits: [HeistTrait]? = nil,
        excludeTraits: [HeistTrait]? = nil
    ) {
        self.heistId = heistId
        self.label = label
        self.identifier = identifier
        self.value = value
        self.traits = traits
        self.excludeTraits = excludeTraits
    }

    public var hasTraitPredicates: Bool {
        (traits?.isEmpty == false) || (excludeTraits?.isEmpty == false)
    }

    /// Whether any property predicate is set (heistId, label, identifier, value, traits, or excludeTraits).
    /// Empty strings are treated as unset — they match nothing rather than everything.
    public var hasPredicates: Bool {
        heistId?.isEmpty == false || label?.isEmpty == false || identifier?.isEmpty == false ||
            value?.isEmpty == false || hasTraitPredicates
    }

    /// Returns `self` when at least one predicate field is set, else `nil`.
    /// Useful for chaining: an empty matcher shouldn't be sent over the wire,
    /// so callers can drop it with `matcher.nonEmpty`.
    public var nonEmpty: Self? { hasPredicates ? self : nil }
}

/// Selector for projecting an `Interface` to one matched node.
///
/// `.element` searches leaf `HeistElement` nodes with `ElementMatcher`.
/// `.container` searches parser container nodes with `ContainerMatcher`.
/// `ordinal` is applied after collecting matches in stable tree order.
public enum SubtreeSelector: Codable, Sendable, Equatable {
    case element(ElementMatcher, ordinal: Int? = nil)
    case container(ContainerMatcher, ordinal: Int? = nil)

    private enum CodingKeys: String, CodingKey {
        case element
        case container
        case ordinal
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let hasElement = container.contains(.element)
        let hasContainer = container.contains(.container)
        guard hasElement != hasContainer else {
            throw DecodingError.dataCorruptedError(
                forKey: .element,
                in: container,
                debugDescription: "SubtreeSelector requires exactly one of element or container"
            )
        }
        let ordinal = try container.decodeIfPresent(Int.self, forKey: .ordinal)
        if hasElement {
            self = .element(try container.decode(ElementMatcher.self, forKey: .element), ordinal: ordinal)
        } else {
            self = .container(try container.decode(ContainerMatcher.self, forKey: .container), ordinal: ordinal)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .element(let matcher, let ordinal):
            try container.encode(matcher, forKey: .element)
            try container.encodeIfPresent(ordinal, forKey: .ordinal)
        case .container(let matcher, let ordinal):
            try container.encode(matcher, forKey: .container)
            try container.encodeIfPresent(ordinal, forKey: .ordinal)
        }
    }

    public var ordinal: Int? {
        switch self {
        case .element(_, let ordinal), .container(_, let ordinal):
            return ordinal
        }
    }

    public var hasPredicates: Bool {
        switch self {
        case .element(let matcher, _):
            return matcher.hasPredicates
        case .container(let matcher, _):
            return matcher.hasPredicates
        }
    }
}

// MARK: - Convenience Extensions

extension HeistElement {
    public var frame: CGRect {
        CGRect(x: frameX, y: frameY, width: frameWidth, height: frameHeight)
    }

    public var activationPoint: CGPoint {
        CGPoint(x: activationPointX, y: activationPointY)
    }

    /// Known trait values. Used to reject unknown traits in matcher queries (fail-safe).
    private static let knownTraits = Set(HeistTrait.allCases)

    /// Match this wire element against an ElementMatcher predicate.
    ///
    /// Exact-or-miss semantics: string fields (`label`, `identifier`, `value`)
    /// must equal the matcher value, compared case-insensitively after typography
    /// folding (smart quotes/dashes/ellipsis fold to ASCII; emoji, accents, and
    /// CJK pass through). Trait fields use exact bitmask comparison. This is
    /// identical to the server-side `AccessibilityElement.matches` so the same
    /// `ElementMatcher` evaluated client-side and server-side produces the same
    /// answer.
    ///
    /// Used for client-side filtering of serialized interface data (`get_interface`)
    /// and for action-expectation matchers (`elementAppeared`, `elementDisappeared`).
    /// Unknown traits in `traits` or `excludeTraits` cause a miss (fail-safe).
    public func matches(_ matcher: ElementMatcher) -> Bool {
        if let matchHeistId = matcher.heistId {
            if matchHeistId.isEmpty { return false }
            guard heistId == matchHeistId else { return false }
        }
        if let matchLabel = matcher.label {
            if matchLabel.isEmpty { return false }
            guard let label, ElementMatcher.stringEquals(label, matchLabel) else { return false }
        }
        if let matchId = matcher.identifier {
            if matchId.isEmpty { return false }
            guard let identifier, ElementMatcher.stringEquals(identifier, matchId) else { return false }
        }
        if let matchVal = matcher.value {
            if matchVal.isEmpty { return false }
            guard let value, ElementMatcher.stringEquals(value, matchVal) else { return false }
        }
        let traitSet = matcher.hasTraitPredicates ? Set(traits) : []
        if let required = matcher.traits, !required.isEmpty {
            for trait in required where !Self.knownTraits.contains(trait) { return false }
            for trait in required where !traitSet.contains(trait) { return false }
        }
        if let excluded = matcher.excludeTraits, !excluded.isEmpty {
            for trait in excluded where !Self.knownTraits.contains(trait) { return false }
            for trait in excluded where traitSet.contains(trait) { return false }
        }
        return true
    }
}

// MARK: - String Comparison Helpers

extension ElementMatcher {
    /// Case-insensitive equality with typography folding. The canonical comparison
    /// used by both client-side `HeistElement.matches` and server-side
    /// `AccessibilityElement.matches`. Folding turns smart quotes / dashes /
    /// ellipsis / non-breaking spaces into their ASCII equivalents so labels
    /// authored with typographic punctuation match patterns typed with ASCII
    /// (and vice versa). Real Unicode without an ASCII equivalent — emoji,
    /// accents, CJK — is left untouched.
    public static func stringEquals(_ candidate: String, _ pattern: String) -> Bool {
        normalizeTypography(candidate)
            .localizedCaseInsensitiveCompare(normalizeTypography(pattern)) == .orderedSame
    }

    /// Case-insensitive substring with typography folding. Suggestion-only —
    /// used by the diagnostic / near-miss path to surface "did you mean X?"
    /// hints when an exact match fails. Never used by resolution.
    public static func stringContains(_ candidate: String, _ pattern: String) -> Bool {
        normalizeTypography(candidate)
            .localizedCaseInsensitiveContains(normalizeTypography(pattern))
    }

    /// Fold typographic punctuation that has an ASCII equivalent.
    /// Shared between client-side and server-side matchers so the same input
    /// produces the same comparison on both sides.
    public static func normalizeTypography(_ string: String) -> String {
        guard string.unicodeScalars.contains(where: { typographicAsciiFold[$0] != nil }) else {
            return string
        }
        var result = ""
        result.reserveCapacity(string.count)
        for scalar in string.unicodeScalars {
            if let replacement = typographicAsciiFold[scalar] {
                result.append(replacement)
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    private static let typographicAsciiFold: [Unicode.Scalar: String] = [
        // Single quotes / apostrophes
        "\u{2018}": "'",  // ' LEFT SINGLE QUOTATION MARK
        "\u{2019}": "'",  // ' RIGHT SINGLE QUOTATION MARK / typographic apostrophe
        "\u{201A}": "'",  // ‚ SINGLE LOW-9 QUOTATION MARK
        "\u{201B}": "'",  // ‛ SINGLE HIGH-REVERSED-9 QUOTATION MARK
        "\u{2032}": "'",  // ′ PRIME
        // Double quotes
        "\u{201C}": "\"", // " LEFT DOUBLE QUOTATION MARK
        "\u{201D}": "\"", // " RIGHT DOUBLE QUOTATION MARK
        "\u{201E}": "\"", // „ DOUBLE LOW-9 QUOTATION MARK
        "\u{201F}": "\"", // ‟ DOUBLE HIGH-REVERSED-9 QUOTATION MARK
        "\u{2033}": "\"", // ″ DOUBLE PRIME
        // Dashes / hyphens
        "\u{2010}": "-",  // ‐ HYPHEN
        "\u{2011}": "-",  // ‑ NON-BREAKING HYPHEN
        "\u{2012}": "-",  // ‒ FIGURE DASH
        "\u{2013}": "-",  // – EN DASH
        "\u{2014}": "-",  // — EM DASH
        "\u{2015}": "-",  // ― HORIZONTAL BAR
        "\u{2212}": "-",  // − MINUS SIGN
        // Ellipsis
        "\u{2026}": "...", // … HORIZONTAL ELLIPSIS
        // Non-breaking / typographic spaces
        "\u{00A0}": " ",  // NO-BREAK SPACE
        "\u{2007}": " ",  // FIGURE SPACE
        "\u{202F}": " ",  // NARROW NO-BREAK SPACE
    ]
}
