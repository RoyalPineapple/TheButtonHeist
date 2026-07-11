import Foundation

// MARK: - Element Actions

/// Actions that can be performed on a UI element.
/// Built-in actions encode as plain strings ("activate", "typeText", "increment", "decrement").
/// Custom actions encode as their name string directly.
public enum ElementAction: Equatable, Hashable, Sendable {
    case activate
    case typeText
    case increment
    case decrement
    case custom(String)
}

extension ElementAction: CustomStringConvertible {
    public var description: String {
        switch self {
        case .activate: return "activate"
        case .typeText: return "typeText"
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
        case "typeText": self = .typeText
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
        case .activate, .typeText, .increment, .decrement:
            var container = encoder.singleValueContainer()
            try container.encode(description)
        case .custom(let name):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .custom)
        }
    }
}

package extension Set where Element == ElementAction {
    var canonicalElementActionArray: [ElementAction] {
        sorted { lhs, rhs in
            lhs.canonicalSortKey < rhs.canonicalSortKey
        }
    }
}

package extension ElementAction {
    var canonicalSortKey: String {
        switch self {
        case .activate:
            return "0:activate"
        case .typeText:
            return "1:typeText"
        case .increment:
            return "2:increment"
        case .decrement:
            return "3:decrement"
        case .custom(let name):
            return "4:\(name)"
        }
    }
}

// MARK: - Heist Trait

/// Named accessibility traits ButtonHeist exposes publicly.
/// Standard UIAccessibilityTraits plus private UIKit traits the parser can capture.
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

    /// Returns nil for unknown trait strings. Codable remains the wire-contract decoder.
    public init?(rawValue: String) {
        guard let known = Self.nameToTrait[rawValue] else { return nil }
        self = known
    }

    /// The string name for known cases.
    private var nameValue: String {
        switch self {
        case .button: return "button"
        case .link: return "link"
        case .image: return "image"
        case .staticText: return "staticText"
        case .header: return "header"
        case .adjustable: return "adjustable"
        case .searchField: return "searchField"
        case .selected: return "selected"
        case .notEnabled: return "notEnabled"
        case .keyboardKey: return "keyboardKey"
        case .summaryElement: return "summaryElement"
        case .updatesFrequently: return "updatesFrequently"
        case .playsSound: return "playsSound"
        case .startsMediaSession: return "startsMediaSession"
        case .allowsDirectInteraction: return "allowsDirectInteraction"
        case .causesPageTurn: return "causesPageTurn"
        case .tabBar: return "tabBar"
        case .textEntry: return "textEntry"
        case .isEditing: return "isEditing"
        case .backButton: return "backButton"
        case .tabBarItem: return "tabBarItem"
        case .textArea: return "textArea"
        case .switchButton: return "switchButton"
        case .webContent: return "webContent"
        case .pickerElement: return "pickerElement"
        case .radioButton: return "radioButton"
        case .launchIcon: return "launchIcon"
        case .statusBarElement: return "statusBarElement"
        case .secureTextField: return "secureTextField"
        case .inactive: return "inactive"
        case .footer: return "footer"
        case .autoCorrectCandidate: return "autoCorrectCandidate"
        case .deleteKey: return "deleteKey"
        case .selectionDismissesItem: return "selectionDismissesItem"
        case .visited: return "visited"
        case .spacer: return "spacer"
        case .tableIndex: return "tableIndex"
        case .map: return "map"
        case .textOperationsAvailable: return "textOperationsAvailable"
        case .draggable: return "draggable"
        case .popupButton: return "popupButton"
        case .menuItem: return "menuItem"
        case .alert: return "alert"
        }
    }

    public var rawValue: String { nameValue }
}

extension HeistTrait: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let trait = HeistTrait(rawValue: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "enum one of \(HeistTrait.allCases.map(\.rawValue).joined(separator: ", "))"
            )
        }
        self = trait
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

package extension Sequence where Element == HeistTrait {
    var heistTraitSet: Set<HeistTrait> {
        Set(self)
    }

    var canonicalHeistTraitArray: [HeistTrait] {
        heistTraitSet.canonicalHeistTraitArray
    }
}

package extension Set where Element == HeistTrait {
    var canonicalHeistTraitArray: [HeistTrait] {
        sorted { $0.rawValue < $1.rawValue }
    }
}
