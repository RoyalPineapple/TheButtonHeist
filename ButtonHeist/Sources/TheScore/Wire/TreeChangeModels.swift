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
    case actions(ElementActionSet)
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
            self = .actions(try container.decode(ElementActionSet.self, forKey: .actions))
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
            return actions.displayText
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

}

public struct ElementPropertyValueChange<Value: Codable & Sendable & Equatable>: Codable, Sendable, Equatable {
    public let old: Value?
    public let new: Value?

    public init(old: Value?, new: Value?) {
        precondition(old != new, "property changes must carry different old and new values")
        self.old = old
        self.new = new
    }

    fileprivate func satisfies<Checker>(
        _ expected: PropertyChangeCore<Checker>,
        matches: (Checker, Value?) -> Bool
    ) -> Bool {
        if let before = expected.before, !matches(before, old) { return false }
        if let after = expected.after, !matches(after, new) { return false }
        return true
    }
}

/// A single typed property change. Each case pins the property to the only
/// value type it can carry.
public enum PropertyChange: Sendable, Equatable {
    case label(ElementPropertyValueChange<String>)
    case identifier(ElementPropertyValueChange<String>)
    case value(ElementPropertyValueChange<String>)
    case traits(ElementPropertyValueChange<[HeistTrait]>)
    case hint(ElementPropertyValueChange<String>)
    case actions(ElementPropertyValueChange<ElementActionSet>)
    case frame(ElementPropertyValueChange<ElementPropertyFrame>)
    case activationPoint(ElementPropertyValueChange<ElementPropertyPoint>)
    case customContent(ElementPropertyValueChange<[HeistCustomContent]>)
    case rotors(ElementPropertyValueChange<[HeistRotor]>)

    public static func label(old: String?, new: String?) -> Self {
        .label(ElementPropertyValueChange(old: old, new: new))
    }

    public static func identifier(old: String?, new: String?) -> Self {
        .identifier(ElementPropertyValueChange(old: old, new: new))
    }

    public static func value(old: String?, new: String?) -> Self {
        .value(ElementPropertyValueChange(old: old, new: new))
    }

    public static func traits(old: [HeistTrait]?, new: [HeistTrait]?) -> Self {
        let old = old.map(Self.canonicalTraits)
        let new = new.map(Self.canonicalTraits)
        return .traits(ElementPropertyValueChange(old: old, new: new))
    }

    public static func hint(old: String?, new: String?) -> Self {
        .hint(ElementPropertyValueChange(old: old, new: new))
    }

    public static func actions(old: ElementActionSet?, new: ElementActionSet?) -> Self {
        .actions(ElementPropertyValueChange(old: old, new: new))
    }

    public static func actions(old: [ElementAction]?, new: [ElementAction]?) -> Self {
        .actions(
            old: old.map { ElementActionSet($0) },
            new: new.map { ElementActionSet($0) }
        )
    }

    public static func frame(old: ElementPropertyFrame?, new: ElementPropertyFrame?) -> Self {
        .frame(ElementPropertyValueChange(old: old, new: new))
    }

    public static func activationPoint(old: ElementPropertyPoint?, new: ElementPropertyPoint?) -> Self {
        .activationPoint(ElementPropertyValueChange(old: old, new: new))
    }

    public static func customContent(old: [HeistCustomContent]?, new: [HeistCustomContent]?) -> Self {
        .customContent(ElementPropertyValueChange(old: old, new: new))
    }

    public static func rotors(old: [HeistRotor]?, new: [HeistRotor]?) -> Self {
        .rotors(ElementPropertyValueChange(old: old, new: new))
    }

    public var property: ElementProperty {
        switch self {
        case .label: return .label
        case .identifier: return .identifier
        case .value: return .value
        case .traits: return .traits
        case .hint: return .hint
        case .actions: return .actions
        case .frame: return .frame
        case .activationPoint: return .activationPoint
        case .customContent: return .customContent
        case .rotors: return .rotors
        }
    }

    public var oldValue: ElementPropertyValue? {
        switch self {
        case .label(let change), .identifier(let change), .value(let change), .hint(let change):
            return change.old.map(ElementPropertyValue.text)
        case .traits(let change): return change.old.map(ElementPropertyValue.traits)
        case .actions(let change): return change.old.map(ElementPropertyValue.actions)
        case .frame(let change): return change.old.map(ElementPropertyValue.frame)
        case .activationPoint(let change): return change.old.map(ElementPropertyValue.activationPoint)
        case .customContent(let change): return change.old.map(ElementPropertyValue.customContent)
        case .rotors(let change): return change.old.map(ElementPropertyValue.rotors)
        }
    }

    public var newValue: ElementPropertyValue? {
        switch self {
        case .label(let change), .identifier(let change), .value(let change), .hint(let change):
            return change.new.map(ElementPropertyValue.text)
        case .traits(let change): return change.new.map(ElementPropertyValue.traits)
        case .actions(let change): return change.new.map(ElementPropertyValue.actions)
        case .frame(let change): return change.new.map(ElementPropertyValue.frame)
        case .activationPoint(let change): return change.new.map(ElementPropertyValue.activationPoint)
        case .customContent(let change): return change.new.map(ElementPropertyValue.customContent)
        case .rotors(let change): return change.new.map(ElementPropertyValue.rotors)
        }
    }

    public var oldDisplayText: String? {
        oldValue?.displayText
    }

    public var newDisplayText: String? {
        newValue?.displayText
    }

    public var displayTransition: String {
        "\(oldDisplayText ?? "nil") → \(newDisplayText ?? "nil")"
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
        switch property {
        case .label:
            self = .label(try Self.decodeChange(String.self, from: container))
        case .identifier:
            self = .identifier(try Self.decodeChange(String.self, from: container))
        case .value:
            self = .value(try Self.decodeChange(String.self, from: container))
        case .traits:
            self = .traits(try Self.decodeTraitsChange(from: container))
        case .hint:
            self = .hint(try Self.decodeChange(String.self, from: container))
        case .actions:
            self = .actions(try Self.decodeChange(ElementActionSet.self, from: container))
        case .frame:
            self = .frame(try Self.decodeChange(ElementPropertyFrame.self, from: container))
        case .activationPoint:
            self = .activationPoint(try Self.decodeChange(ElementPropertyPoint.self, from: container))
        case .customContent:
            self = .customContent(try Self.decodeChange([HeistCustomContent].self, from: container))
        case .rotors:
            self = .rotors(try Self.decodeChange([HeistRotor].self, from: container))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(property, forKey: .property)
        switch self {
        case .label(let change):
            try Self.encodeChange(change, to: &container)
        case .identifier(let change):
            try Self.encodeChange(change, to: &container)
        case .value(let change):
            try Self.encodeChange(change, to: &container)
        case .traits(let change):
            try Self.encodeChange(change, to: &container)
        case .hint(let change):
            try Self.encodeChange(change, to: &container)
        case .actions(let change):
            try Self.encodeChange(change, to: &container)
        case .frame(let change):
            try Self.encodeChange(change, to: &container)
        case .activationPoint(let change):
            try Self.encodeChange(change, to: &container)
        case .customContent(let change):
            try Self.encodeChange(change, to: &container)
        case .rotors(let change):
            try Self.encodeChange(change, to: &container)
        }
    }

    private static func encodeChange<Value>(
        _ change: ElementPropertyValueChange<Value>,
        to container: inout KeyedEncodingContainer<CodingKeys>
    ) throws where Value: Codable & Sendable & Equatable {
        try container.encodeIfPresent(change.old, forKey: .old)
        try container.encodeIfPresent(change.new, forKey: .new)
    }

    private static func decodeChange<Value>(
        _ value: Value.Type,
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> ElementPropertyValueChange<Value> where Value: Codable & Sendable & Equatable {
        let old = try container.decodeIfPresent(Value.self, forKey: .old)
        let new = try container.decodeIfPresent(Value.self, forKey: .new)
        guard old != new else {
            throw DecodingError.dataCorruptedError(
                forKey: .property,
                in: container,
                debugDescription: "property change must carry different old and new values"
            )
        }
        return ElementPropertyValueChange(
            old: old,
            new: new
        )
    }

    private static func decodeTraitsChange(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> ElementPropertyValueChange<[HeistTrait]> {
        let old = try container.decodeIfPresent([HeistTrait].self, forKey: .old).map(Self.canonicalTraits)
        let new = try container.decodeIfPresent([HeistTrait].self, forKey: .new).map(Self.canonicalTraits)
        guard old != new else {
            throw DecodingError.dataCorruptedError(
                forKey: .property,
                in: container,
                debugDescription: "property change must carry different old and new values"
            )
        }
        return ElementPropertyValueChange(old: old, new: new)
    }

    private static func canonicalTraits(_ traits: [HeistTrait]) -> [HeistTrait] {
        Set(traits).sorted { $0.rawValue < $1.rawValue }
    }
}

extension PropertyChange {
    package func satisfies(_ expected: ResolvedElementPropertyChange) -> Bool {
        switch (self, expected.core) {
        case (.value(let observed), .value(let change)), (.hint(let observed), .hint(let change)):
            return observed.satisfies(change) { ResolvedStringMatch(core: $0).matches(optional: $1) }
        case (.traits(let observed), .traits(let change)):
            return observed.satisfies(change, matches: Self.matchesTraits)
        case (.actions(let observed), .actions(let change)):
            return observed.satisfies(change, matches: Self.matchesActions)
        case (.frame(let observed), .frame(let change)):
            return observed.satisfies(change, matches: Self.matchesFrame)
        case (.activationPoint(let observed), .activationPoint(let change)):
            return observed.satisfies(change, matches: Self.matchesPoint)
        case (.customContent(let observed), .customContent(let change)):
            return observed.satisfies(change, matches: Self.matchesCustomContent)
        case (.rotors(let observed), .rotors(let change)):
            return observed.satisfies(change, matches: Self.matchesRotors)
        default:
            return false
        }
    }

    private static func matchesTraits(_ checker: TraitSetMatch, _ value: [HeistTrait]?) -> Bool {
        guard let value else { return false }
        let traits = Set(value)
        return checker.include.isSubset(of: traits)
            && checker.exclude.isDisjoint(with: traits)
    }

    private static func matchesActions(_ checker: ActionSetMatch, _ value: ElementActionSet?) -> Bool {
        guard let value else { return false }
        return checker.include.isSubset(of: value.actions)
            && checker.exclude.isDisjoint(with: value.actions)
    }

    private static func matchesFrame(_ checker: ElementFrameMatch, _ value: ElementPropertyFrame?) -> Bool {
        guard let value else { return false }
        return checker.x.map { $0 == value.x } ?? true
            && checker.y.map { $0 == value.y } ?? true
            && checker.width.map { $0 == value.width } ?? true
            && checker.height.map { $0 == value.height } ?? true
    }

    private static func matchesPoint(_ checker: ElementPointMatch, _ value: ElementPropertyPoint?) -> Bool {
        guard let value else { return false }
        return checker.x.map { $0 == value.x } ?? true
            && checker.y.map { $0 == value.y } ?? true
    }

    private static func matchesCustomContent(
        _ checker: CustomContentMatchCore<String>,
        _ value: [HeistCustomContent]?
    ) -> Bool {
        guard let value else { return false }
        return value.contains { checker.matches($0) }
    }

    private static func matchesRotors(_ checker: RotorSetMatchCore<String>, _ value: [HeistRotor]?) -> Bool {
        guard let value else { return false }
        let rotorNames = value.map(\.name)
        return checker.include.allSatisfy { rotorNames.contains(matching: $0) }
            && checker.exclude.allSatisfy { !rotorNames.contains(matching: $0) }
    }
}

private extension CustomContentMatchCore where Text == String {
    func matches(_ content: HeistCustomContent) -> Bool {
        label.matches(content.label)
            && value.matches(content.value)
            && (isImportant.map { $0 == content.isImportant } ?? true)
    }
}

private extension Optional where Wrapped == StringMatchCore<String> {
    func matches(_ text: String) -> Bool {
        map { ResolvedStringMatch(core: $0).matches(text) } ?? true
    }
}

private extension Collection where Element == String {
    func contains(matching match: StringMatchCore<String>) -> Bool {
        contains { ResolvedStringMatch(core: match).matches($0) }
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
