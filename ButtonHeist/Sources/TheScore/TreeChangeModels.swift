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

public protocol ElementPropertyValueKind: ElementPropertyKind {
    associatedtype Value: Codable, Sendable, Equatable

    static func value(in element: HeistElement) -> Value?
    static func expectedChange(from change: AnyPropertyChange) -> ElementPropertyChange<Self>?
    static func valuesEqual(_ lhs: Value?, _ rhs: Value?) -> Bool
    static func displayText(for value: Value) -> String
    static func matches(_ checker: Checker, value: Value?) -> Bool
    static func erasedValue(_ value: Value) -> ElementPropertyValue
    static func change(old: Value?, new: Value?) -> PropertyChange
}

public extension ElementPropertyValueKind {
    static func valuesEqual(_ lhs: Value?, _ rhs: Value?) -> Bool {
        lhs == rhs
    }
}

public protocol ElementTextPropertyValueKind: ElementPropertyValueKind where Value == String, Checker == StringMatch<String> {}

public extension ElementTextPropertyValueKind {
    static func displayText(for value: String) -> String {
        value
    }

    static func matches(_ checker: StringMatch<String>, value: String?) -> Bool {
        guard let value else { return false }
        return checker.matches(value)
    }

    static func erasedValue(_ value: String) -> ElementPropertyValue {
        .text(value)
    }
}

public struct ElementPropertyValueChange<P: ElementPropertyValueKind>: Codable, Sendable {
    public let old: P.Value?
    public let new: P.Value?

    public init(old: P.Value?, new: P.Value?) {
        precondition(
            !P.valuesEqual(old, new),
            "\(P.property.rawValue) property changes must carry different old and new values"
        )
        self.old = old
        self.new = new
    }

    public var oldValue: ElementPropertyValue? {
        old.map(P.erasedValue)
    }

    public var newValue: ElementPropertyValue? {
        new.map(P.erasedValue)
    }

    public var oldDisplayText: String? {
        old.map { P.displayText(for: $0) }
    }

    public var newDisplayText: String? {
        new.map { P.displayText(for: $0) }
    }
}

extension ElementPropertyValueChange: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        P.valuesEqual(lhs.old, rhs.old) && P.valuesEqual(lhs.new, rhs.new)
    }
}

extension ElementPropertyValueChange {
    func satisfies(_ expected: AnyPropertyChange) -> Bool {
        guard let expected = P.expectedChange(from: expected) else { return false }
        return satisfies(expected)
    }

    func satisfies(_ expected: ElementPropertyChange<P>) -> Bool {
        if let before = expected.before {
            guard P.matches(before, value: old) else { return false }
        }
        if let after = expected.after {
            guard P.matches(after, value: new) else { return false }
        }
        return true
    }
}

/// A single typed property change. Each case pins the property to the only
/// value type it can carry.
public enum PropertyChange: Sendable, Equatable {
    case label(ElementPropertyValueChange<LabelProperty>)
    case identifier(ElementPropertyValueChange<IdentifierProperty>)
    case value(ElementPropertyValueChange<ValueProperty>)
    case traits(ElementPropertyValueChange<TraitsProperty>)
    case hint(ElementPropertyValueChange<HintProperty>)
    case actions(ElementPropertyValueChange<ActionsProperty>)
    case frame(ElementPropertyValueChange<FrameProperty>)
    case activationPoint(ElementPropertyValueChange<ActivationPointProperty>)
    case customContent(ElementPropertyValueChange<CustomContentProperty>)
    case rotors(ElementPropertyValueChange<RotorsProperty>)

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
        .traits(ElementPropertyValueChange(old: old, new: new))
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
        case .label:
            return LabelProperty.property
        case .identifier:
            return IdentifierProperty.property
        case .value:
            return ValueProperty.property
        case .traits:
            return TraitsProperty.property
        case .hint:
            return HintProperty.property
        case .actions:
            return ActionsProperty.property
        case .frame:
            return FrameProperty.property
        case .activationPoint:
            return ActivationPointProperty.property
        case .customContent:
            return CustomContentProperty.property
        case .rotors:
            return RotorsProperty.property
        }
    }

    public var oldValue: ElementPropertyValue? {
        switch self {
        case .label(let change):
            return change.oldValue
        case .identifier(let change):
            return change.oldValue
        case .value(let change):
            return change.oldValue
        case .traits(let change):
            return change.oldValue
        case .hint(let change):
            return change.oldValue
        case .actions(let change):
            return change.oldValue
        case .frame(let change):
            return change.oldValue
        case .activationPoint(let change):
            return change.oldValue
        case .customContent(let change):
            return change.oldValue
        case .rotors(let change):
            return change.oldValue
        }
    }

    public var newValue: ElementPropertyValue? {
        switch self {
        case .label(let change):
            return change.newValue
        case .identifier(let change):
            return change.newValue
        case .value(let change):
            return change.newValue
        case .traits(let change):
            return change.newValue
        case .hint(let change):
            return change.newValue
        case .actions(let change):
            return change.newValue
        case .frame(let change):
            return change.newValue
        case .activationPoint(let change):
            return change.newValue
        case .customContent(let change):
            return change.newValue
        case .rotors(let change):
            return change.newValue
        }
    }

    public var oldDisplayText: String? {
        switch self {
        case .label(let change):
            return change.oldDisplayText
        case .identifier(let change):
            return change.oldDisplayText
        case .value(let change):
            return change.oldDisplayText
        case .traits(let change):
            return change.oldDisplayText
        case .hint(let change):
            return change.oldDisplayText
        case .actions(let change):
            return change.oldDisplayText
        case .frame(let change):
            return change.oldDisplayText
        case .activationPoint(let change):
            return change.oldDisplayText
        case .customContent(let change):
            return change.oldDisplayText
        case .rotors(let change):
            return change.oldDisplayText
        }
    }

    public var newDisplayText: String? {
        switch self {
        case .label(let change):
            return change.newDisplayText
        case .identifier(let change):
            return change.newDisplayText
        case .value(let change):
            return change.newDisplayText
        case .traits(let change):
            return change.newDisplayText
        case .hint(let change):
            return change.newDisplayText
        case .actions(let change):
            return change.newDisplayText
        case .frame(let change):
            return change.newDisplayText
        case .activationPoint(let change):
            return change.newDisplayText
        case .customContent(let change):
            return change.newDisplayText
        case .rotors(let change):
            return change.newDisplayText
        }
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
            self = .label(try Self.decodeChange(LabelProperty.self, from: container))
        case .identifier:
            self = .identifier(try Self.decodeChange(IdentifierProperty.self, from: container))
        case .value:
            self = .value(try Self.decodeChange(ValueProperty.self, from: container))
        case .traits:
            self = .traits(try Self.decodeChange(TraitsProperty.self, from: container))
        case .hint:
            self = .hint(try Self.decodeChange(HintProperty.self, from: container))
        case .actions:
            self = .actions(try Self.decodeChange(ActionsProperty.self, from: container))
        case .frame:
            self = .frame(try Self.decodeChange(FrameProperty.self, from: container))
        case .activationPoint:
            self = .activationPoint(try Self.decodeChange(ActivationPointProperty.self, from: container))
        case .customContent:
            self = .customContent(try Self.decodeChange(CustomContentProperty.self, from: container))
        case .rotors:
            self = .rotors(try Self.decodeChange(RotorsProperty.self, from: container))
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

    private static func encodeChange<P: ElementPropertyValueKind>(
        _ change: ElementPropertyValueChange<P>,
        to container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        try container.encodeIfPresent(change.old, forKey: .old)
        try container.encodeIfPresent(change.new, forKey: .new)
    }

    private static func decodeChange<P: ElementPropertyValueKind>(
        _ property: P.Type,
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> ElementPropertyValueChange<P> {
        let old = try container.decodeIfPresent(P.Value.self, forKey: .old)
        let new = try container.decodeIfPresent(P.Value.self, forKey: .new)
        guard !P.valuesEqual(old, new) else {
            throw DecodingError.dataCorruptedError(
                forKey: .property,
                in: container,
                debugDescription: "\(P.property.rawValue) property change must carry different old and new values"
            )
        }
        return ElementPropertyValueChange(
            old: old,
            new: new
        )
    }
}

extension PropertyChange {
    package func satisfies(_ expected: AnyPropertyChange) -> Bool {
        switch self {
        case .label(let observed):
            return observed.satisfies(expected)
        case .identifier(let observed):
            return observed.satisfies(expected)
        case .value(let observed):
            return observed.satisfies(expected)
        case .traits(let observed):
            return observed.satisfies(expected)
        case .hint(let observed):
            return observed.satisfies(expected)
        case .actions(let observed):
            return observed.satisfies(expected)
        case .frame(let observed):
            return observed.satisfies(expected)
        case .activationPoint(let observed):
            return observed.satisfies(expected)
        case .customContent(let observed):
            return observed.satisfies(expected)
        case .rotors(let observed):
            return observed.satisfies(expected)
        }
    }
}

extension ValueProperty: ElementTextPropertyValueKind {
    public static func value(in element: HeistElement) -> String? {
        element.value
    }

    public static func expectedChange(from change: AnyPropertyChange) -> ElementPropertyChange<Self>? {
        guard case .value(let expected) = change else { return nil }
        return expected
    }

    public static func change(old: String?, new: String?) -> PropertyChange {
        .value(old: old, new: new)
    }
}

extension LabelProperty: ElementTextPropertyValueKind {
    public static func value(in element: HeistElement) -> String? {
        element.label
    }

    public static func expectedChange(from _: AnyPropertyChange) -> ElementPropertyChange<Self>? {
        nil
    }

    public static func change(old: String?, new: String?) -> PropertyChange {
        .label(old: old, new: new)
    }
}

extension IdentifierProperty: ElementTextPropertyValueKind {
    public static func value(in element: HeistElement) -> String? {
        element.identifier
    }

    public static func expectedChange(from _: AnyPropertyChange) -> ElementPropertyChange<Self>? {
        nil
    }

    public static func change(old: String?, new: String?) -> PropertyChange {
        .identifier(old: old, new: new)
    }
}

extension TraitsProperty: ElementPropertyValueKind {
    public typealias Value = [HeistTrait]

    public static func value(in element: HeistElement) -> [HeistTrait]? {
        element.traits
    }

    public static func expectedChange(from change: AnyPropertyChange) -> ElementPropertyChange<Self>? {
        guard case .traits(let expected) = change else { return nil }
        return expected
    }

    public static func valuesEqual(_ lhs: [HeistTrait]?, _ rhs: [HeistTrait]?) -> Bool {
        lhs.map(Set.init) == rhs.map(Set.init)
    }

    public static func displayText(for value: [HeistTrait]) -> String {
        value.orderedByRawValue.map(\.rawValue).joined(separator: ", ")
    }

    public static func matches(_ checker: TraitSetMatch, value: [HeistTrait]?) -> Bool {
        guard let value else { return false }
        let traits = Set(value)
        return checker.include.isSubset(of: traits)
            && checker.exclude.isDisjoint(with: traits)
    }

    public static func erasedValue(_ value: [HeistTrait]) -> ElementPropertyValue {
        .traits(value.orderedByRawValue)
    }

    public static func change(old: [HeistTrait]?, new: [HeistTrait]?) -> PropertyChange {
        .traits(old: old, new: new)
    }
}

extension HintProperty: ElementTextPropertyValueKind {
    public static func value(in element: HeistElement) -> String? {
        element.hint
    }

    public static func expectedChange(from change: AnyPropertyChange) -> ElementPropertyChange<Self>? {
        guard case .hint(let expected) = change else { return nil }
        return expected
    }

    public static func change(old: String?, new: String?) -> PropertyChange {
        .hint(old: old, new: new)
    }
}

extension ActionsProperty: ElementPropertyValueKind {
    public typealias Value = ElementActionSet

    public static func value(in element: HeistElement) -> ElementActionSet? {
        ElementActionSet(element.actions)
    }

    public static func expectedChange(from change: AnyPropertyChange) -> ElementPropertyChange<Self>? {
        guard case .actions(let expected) = change else { return nil }
        return expected
    }

    public static func displayText(for value: ElementActionSet) -> String {
        value.displayText
    }

    public static func matches(_ checker: ActionSetMatch, value: ElementActionSet?) -> Bool {
        guard let value else { return false }
        return checker.include.isSubset(of: value.actions)
            && checker.exclude.isDisjoint(with: value.actions)
    }

    public static func erasedValue(_ value: ElementActionSet) -> ElementPropertyValue {
        .actions(value)
    }

    public static func change(old: ElementActionSet?, new: ElementActionSet?) -> PropertyChange {
        .actions(old: old, new: new)
    }
}

extension FrameProperty: ElementPropertyValueKind {
    public typealias Value = ElementPropertyFrame

    public static func value(in element: HeistElement) -> ElementPropertyFrame? {
        let frame = element.screenFrame
        return ElementPropertyFrame(
            x: Int(frame.x),
            y: Int(frame.y),
            width: Int(frame.width),
            height: Int(frame.height)
        )
    }

    public static func expectedChange(from change: AnyPropertyChange) -> ElementPropertyChange<Self>? {
        guard case .frame(let expected) = change else { return nil }
        return expected
    }

    public static func displayText(for value: ElementPropertyFrame) -> String {
        value.displayText
    }

    public static func matches(_ checker: ElementFrameMatch, value: ElementPropertyFrame?) -> Bool {
        guard let value else { return false }
        return checker.x.map { $0 == value.x } ?? true
            && checker.y.map { $0 == value.y } ?? true
            && checker.width.map { $0 == value.width } ?? true
            && checker.height.map { $0 == value.height } ?? true
    }

    public static func erasedValue(_ value: ElementPropertyFrame) -> ElementPropertyValue {
        .frame(value)
    }

    public static func change(old: ElementPropertyFrame?, new: ElementPropertyFrame?) -> PropertyChange {
        .frame(old: old, new: new)
    }
}

extension ActivationPointProperty: ElementPropertyValueKind {
    public typealias Value = ElementPropertyPoint

    public static func value(in element: HeistElement) -> ElementPropertyPoint? {
        guard let point = element.activationPointEvidence.point else { return nil }
        return ElementPropertyPoint(
            x: Int(point.x),
            y: Int(point.y)
        )
    }

    public static func expectedChange(from change: AnyPropertyChange) -> ElementPropertyChange<Self>? {
        guard case .activationPoint(let expected) = change else { return nil }
        return expected
    }

    public static func displayText(for value: ElementPropertyPoint) -> String {
        value.displayText
    }

    public static func matches(_ checker: ElementPointMatch, value: ElementPropertyPoint?) -> Bool {
        guard let value else { return false }
        return checker.x.map { $0 == value.x } ?? true
            && checker.y.map { $0 == value.y } ?? true
    }

    public static func erasedValue(_ value: ElementPropertyPoint) -> ElementPropertyValue {
        .activationPoint(value)
    }

    public static func change(old: ElementPropertyPoint?, new: ElementPropertyPoint?) -> PropertyChange {
        .activationPoint(old: old, new: new)
    }
}

extension CustomContentProperty: ElementPropertyValueKind {
    public typealias Value = [HeistCustomContent]

    public static func value(in element: HeistElement) -> [HeistCustomContent]? {
        let content = element.customContent?.filter { !$0.label.isEmpty || !$0.value.isEmpty } ?? []
        return content.isEmpty ? nil : content
    }

    public static func expectedChange(from change: AnyPropertyChange) -> ElementPropertyChange<Self>? {
        guard case .customContent(let expected) = change else { return nil }
        return expected
    }

    public static func displayText(for value: [HeistCustomContent]) -> String {
        value.compactMap { item -> String? in
            switch (item.label.isEmpty, item.value.isEmpty) {
            case (false, false): return "\(item.label): \(item.value)"
            case (false, true): return item.label
            case (true, false): return item.value
            case (true, true): return nil
            }
        }.joined(separator: "; ")
    }

    public static func matches(_ checker: CustomContentMatch<String>, value: [HeistCustomContent]?) -> Bool {
        guard let value else { return false }
        return value.contains { checker.matches($0) }
    }

    public static func erasedValue(_ value: [HeistCustomContent]) -> ElementPropertyValue {
        .customContent(value)
    }

    public static func change(old: [HeistCustomContent]?, new: [HeistCustomContent]?) -> PropertyChange {
        .customContent(old: old, new: new)
    }
}

extension RotorsProperty: ElementPropertyValueKind {
    public typealias Value = [HeistRotor]

    public static func value(in element: HeistElement) -> [HeistRotor]? {
        let rotors = element.rotors?.filter { !$0.name.isEmpty } ?? []
        return rotors.isEmpty ? nil : rotors
    }

    public static func expectedChange(from change: AnyPropertyChange) -> ElementPropertyChange<Self>? {
        guard case .rotors(let expected) = change else { return nil }
        return expected
    }

    public static func displayText(for value: [HeistRotor]) -> String {
        value.map(\.name).joined(separator: ", ")
    }

    public static func matches(_ checker: RotorSetMatch<String>, value: [HeistRotor]?) -> Bool {
        guard let value else { return false }
        let rotorNames = value.map(\.name)
        return checker.include.allSatisfy { rotorNames.contains(matching: $0) }
            && checker.exclude.allSatisfy { !rotorNames.contains(matching: $0) }
    }

    public static func erasedValue(_ value: [HeistRotor]) -> ElementPropertyValue {
        .rotors(value)
    }

    public static func change(old: [HeistRotor]?, new: [HeistRotor]?) -> PropertyChange {
        .rotors(old: old, new: new)
    }
}

private extension CustomContentMatch where Value == String {
    func matches(_ content: HeistCustomContent) -> Bool {
        label.matches(content.label)
            && value.matches(content.value)
            && (isImportant.map { $0 == content.isImportant } ?? true)
    }
}

private extension Optional where Wrapped == StringMatch<String> {
    func matches(_ text: String) -> Bool {
        map { $0.matches(text) } ?? true
    }
}

private extension Collection where Element == String {
    func contains(matching match: StringMatch<String>) -> Bool {
        contains { match.matches($0) }
    }
}

private extension Sequence where Element == HeistTrait {
    var orderedByRawValue: [HeistTrait] {
        sorted { $0.rawValue < $1.rawValue }
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
