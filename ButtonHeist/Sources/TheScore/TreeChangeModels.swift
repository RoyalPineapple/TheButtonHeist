import ThePlans
import Foundation
import AccessibilitySnapshotModel

/// Integer-projected accessibility frame used for stable element diffing.
public struct ElementPropertyFrame: Codable, Sendable, Equatable, Hashable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var displayText: String {
        "\(x),\(y),\(width),\(height)"
    }
}

/// Integer-projected accessibility activation point used for stable element diffing.
public struct ElementPropertyPoint: Codable, Sendable, Equatable, Hashable {
    public let x: Int
    public let y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    public var displayText: String {
        "\(x),\(y)"
    }
}

/// Typed element property value used by diffs. Human-readable strings are
/// derived at projection/rendering edges through `displayText`.
public enum ElementPropertyValue: Codable, Sendable, Equatable {
    case text(String)
    case traits([HeistTrait])
    case actions([ElementAction])
    case frame(ElementPropertyFrame)
    case activationPoint(ElementPropertyPoint)
    case customContent([HeistCustomContent])
    case rotors([HeistRotor])

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
        case traits
        case actions
        case frame
        case activationPoint
        case customContent
        case rotors
    }

    private enum Kind: String, Codable {
        case text
        case traits
        case actions
        case frame
        case activationPoint
        case customContent
        case rotors
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .text:
            self = .text(try container.decode(String.self, forKey: .value))
        case .traits:
            self = .traits(try container.decode([HeistTrait].self, forKey: .traits))
        case .actions:
            self = .actions(try container.decode([ElementAction].self, forKey: .actions))
        case .frame:
            self = .frame(try container.decode(ElementPropertyFrame.self, forKey: .frame))
        case .activationPoint:
            self = .activationPoint(try container.decode(ElementPropertyPoint.self, forKey: .activationPoint))
        case .customContent:
            self = .customContent(try container.decode([HeistCustomContent].self, forKey: .customContent))
        case .rotors:
            self = .rotors(try container.decode([HeistRotor].self, forKey: .rotors))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value):
            try container.encode(Kind.text, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .traits(let traits):
            try container.encode(Kind.traits, forKey: .kind)
            try container.encode(traits, forKey: .traits)
        case .actions(let actions):
            try container.encode(Kind.actions, forKey: .kind)
            try container.encode(actions, forKey: .actions)
        case .frame(let frame):
            try container.encode(Kind.frame, forKey: .kind)
            try container.encode(frame, forKey: .frame)
        case .activationPoint(let point):
            try container.encode(Kind.activationPoint, forKey: .kind)
            try container.encode(point, forKey: .activationPoint)
        case .customContent(let content):
            try container.encode(Kind.customContent, forKey: .kind)
            try container.encode(content, forKey: .customContent)
        case .rotors(let rotors):
            try container.encode(Kind.rotors, forKey: .kind)
            try container.encode(rotors, forKey: .rotors)
        }
    }

    public static func == (lhs: ElementPropertyValue, rhs: ElementPropertyValue) -> Bool {
        switch (lhs, rhs) {
        case (.text(let lhs), .text(let rhs)):
            return lhs == rhs
        case (.traits(let lhs), .traits(let rhs)):
            return Set(lhs) == Set(rhs)
        case (.actions(let lhs), .actions(let rhs)):
            return lhs == rhs
        case (.frame(let lhs), .frame(let rhs)):
            return lhs == rhs
        case (.activationPoint(let lhs), .activationPoint(let rhs)):
            return lhs == rhs
        case (.customContent(let lhs), .customContent(let rhs)):
            return lhs == rhs
        case (.rotors(let lhs), .rotors(let rhs)):
            return lhs == rhs
        default:
            return false
        }
    }

    public var displayText: String {
        switch self {
        case .text(let value):
            return value
        case .traits(let traits):
            return traits.map(\.rawValue).joined(separator: ", ")
        case .actions(let actions):
            return actions.map(\.description).joined(separator: ", ")
        case .frame(let frame):
            return frame.displayText
        case .activationPoint(let point):
            return point.displayText
        case .customContent(let content):
            return content.compactMap { item -> String? in
                switch (item.label.isEmpty, item.value.isEmpty) {
                case (false, false): return "\(item.label): \(item.value)"
                case (false, true): return item.label
                case (true, false): return item.value
                case (true, true): return nil
                }
            }.joined(separator: "; ")
        case .rotors(let rotors):
            return rotors.map(\.name).joined(separator: ", ")
        }
    }

    var stringMatchText: String? {
        displayText
    }

    var traitSet: Set<HeistTrait>? {
        guard case .traits(let traits) = self else { return nil }
        return Set(traits)
    }

    static func value(for property: ElementProperty, in element: HeistElement) -> ElementPropertyValue? {
        switch property {
        case .value:
            return element.value.map(ElementPropertyValue.text)
        case .traits:
            return .traits(element.traits)
        case .hint:
            return element.hint.map(ElementPropertyValue.text)
        case .actions:
            return .actions(element.actions)
        case .frame:
            return .frame(ElementPropertyFrame(
                x: Int(element.frameX),
                y: Int(element.frameY),
                width: Int(element.frameWidth),
                height: Int(element.frameHeight)
            ))
        case .activationPoint:
            return .activationPoint(ElementPropertyPoint(
                x: Int(element.activationPointX),
                y: Int(element.activationPointY)
            ))
        case .customContent:
            let content = element.customContent?.filter { !$0.label.isEmpty || !$0.value.isEmpty } ?? []
            return content.isEmpty ? nil : .customContent(content)
        case .rotors:
            let rotors = element.rotors?.filter { !$0.name.isEmpty } ?? []
            return rotors.isEmpty ? nil : .rotors(rotors)
        }
    }

}

/// A single property change: what property, old value, new value.
public struct PropertyChange: Sendable, Equatable {
    public let property: ElementProperty
    public let oldValue: ElementPropertyValue?
    public let newValue: ElementPropertyValue?

    public init(property: ElementProperty, oldValue: ElementPropertyValue?, newValue: ElementPropertyValue?) {
        self.property = property
        self.oldValue = oldValue
        self.newValue = newValue
    }

    public var displayTransition: String {
        "\(oldValue?.displayText ?? "nil") → \(newValue?.displayText ?? "nil")"
    }
}

extension PropertyChange: Codable {
    private enum CodingKeys: String, CodingKey {
        case property
        case old
        case new
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let property = try container.decode(ElementProperty.self, forKey: .property)
        self.init(
            property: property,
            oldValue: try Self.decodeValueIfPresent(from: container, forKey: .old, property: property),
            newValue: try Self.decodeValueIfPresent(from: container, forKey: .new, property: property)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(property, forKey: .property)
        try Self.encodeValueIfPresent(oldValue, to: &container, forKey: .old, property: property)
        try Self.encodeValueIfPresent(newValue, to: &container, forKey: .new, property: property)
    }

    private static func decodeValueIfPresent(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys,
        property: ElementProperty
    ) throws -> ElementPropertyValue? {
        guard container.contains(key) else { return nil }
        if try container.decodeNil(forKey: key) { return nil }
        switch property {
        case .value:
            return .text(try container.decode(String.self, forKey: key))
        case .traits:
            return .traits(try container.decode([HeistTrait].self, forKey: key))
        case .hint:
            return .text(try container.decode(String.self, forKey: key))
        case .actions:
            return .actions(try container.decode([ElementAction].self, forKey: key))
        case .frame:
            return .frame(try container.decode(ElementPropertyFrame.self, forKey: key))
        case .activationPoint:
            return .activationPoint(try container.decode(ElementPropertyPoint.self, forKey: key))
        case .customContent:
            return .customContent(try container.decode([HeistCustomContent].self, forKey: key))
        case .rotors:
            return .rotors(try container.decode([HeistRotor].self, forKey: key))
        }
    }

    private static func encodeValueIfPresent(
        _ value: ElementPropertyValue?,
        to container: inout KeyedEncodingContainer<CodingKeys>,
        forKey key: CodingKeys,
        property: ElementProperty
    ) throws {
        guard let value else { return }
        switch (property, value) {
        case (.value, .text(let text)), (.hint, .text(let text)):
            try container.encode(text, forKey: key)
        case (.traits, .traits(let traits)):
            try container.encode(traits, forKey: key)
        case (.actions, .actions(let actions)):
            try container.encode(actions, forKey: key)
        case (.frame, .frame(let frame)):
            try container.encode(frame, forKey: key)
        case (.activationPoint, .activationPoint(let point)):
            try container.encode(point, forKey: key)
        case (.customContent, .customContent(let content)):
            try container.encode(content, forKey: key)
        case (.rotors, .rotors(let rotors)):
            try container.encode(rotors, forKey: key)
        default:
            try container.encode(value.displayText, forKey: key)
        }
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
