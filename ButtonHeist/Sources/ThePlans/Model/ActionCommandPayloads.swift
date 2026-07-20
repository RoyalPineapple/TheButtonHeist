import Foundation

/// Target for custom actions.
///
/// Custom actions are element actions. Containers remain addressable by the
/// commands whose product subject is a container, such as scroll commands.
public struct CustomActionTarget: Codable, Sendable, Equatable, CustomStringConvertible {
    public let target: AccessibilityTarget
    public let actionName: CustomActionName

    public init(target: AccessibilityTarget, actionName: CustomActionName) {
        self.target = target
        self.actionName = actionName
    }

    public var description: String {
        CanonicalValueDescription.call("customAction", [
            target.description,
            CanonicalValueDescription.stringField("action", actionName.rawValue),
        ].compactMap { $0 })
    }
}

extension CustomActionTarget {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case target
        case actionName
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "custom action target")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            target: try container.decode(AccessibilityTarget.self, forKey: .target),
            actionName: try container.decode(CustomActionName.self, forKey: .actionName)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(actionName, forKey: .actionName)
        try container.encode(target, forKey: .target)
    }
}

/// Direction for a rotor step.
public enum RotorDirection: String, Codable, Sendable, CaseIterable, Equatable {
    case next
    case previous
}

/// Text-range cursor for continuing through rotor results inside one text input.
public struct TextRangeReference: Codable, Equatable, Hashable, Sendable {
    public let startOffset: Int
    public let endOffset: Int

    public init(startOffset: Int, endOffset: Int) {
        self.startOffset = startOffset
        self.endOffset = endOffset
    }
}

extension TextRangeReference: CustomStringConvertible {
    public var description: String {
        "textRange(\(startOffset)..<\(endOffset))"
    }
}

public struct RotorIndex: Equatable, Hashable, Sendable, ExpressibleByIntegerLiteral {
    public enum ValidationError: Error, Equatable, Sendable, CustomStringConvertible {
        case negative(Int)

        public var description: String {
            switch self {
            case .negative(let value): "rotorIndex must be non-negative, got \(value)"
            }
        }
    }

    public let value: Int

    public init(validating value: Int) throws(ValidationError) {
        guard value >= 0 else { throw .negative(value) }
        self.value = value
    }

    public init(integerLiteral value: Int) {
        self = requireValidLiteralPayload { try Self(validating: value) }
    }
}

public enum RotorSelection: Equatable, Hashable, Sendable {
    case automatic
    case named(RotorName)
    case index(RotorIndex)

    public var rotorName: RotorName? {
        guard case .named(let name) = self else { return nil }
        return name
    }

    public var rotorIndex: Int? {
        guard case .index(let index) = self else { return nil }
        return index.value
    }
}

extension RotorSelection {
    static func decode(
        name: RotorName?,
        index: Int?,
        codingPath: [any CodingKey]
    ) throws -> Self {
        if name != nil, index != nil {
            throw DecodingError.dataCorrupted(.init(
                codingPath: codingPath,
                debugDescription: "rotor accepts either rotor or rotorIndex, not both"
            ))
        }
        if let name { return .named(name) }
        if let index {
            do {
                return .index(try RotorIndex(validating: index))
            } catch {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: codingPath,
                    debugDescription: error.description
                ))
            }
        }
        return .automatic
    }

    func encode<Key: CodingKey>(
        to container: inout KeyedEncodingContainer<Key>,
        nameKey: Key,
        indexKey: Key
    ) throws {
        switch self {
        case .automatic: break
        case .named(let name): try container.encode(name, forKey: nameKey)
        case .index(let index): try container.encode(index.value, forKey: indexKey)
        }
    }
}

extension RotorSelection: CustomStringConvertible {
    public var description: String {
        switch self {
        case .automatic:
            return "automatic"
        case .named(let name):
            return CanonicalValueDescription.stringField("name", name.rawValue) ?? "name=\"\""
        case .index(let index):
            return CanonicalValueDescription.valueField("index", index.value) ?? "index=\(index.value)"
        }
    }
}

/// Target for moving through a rotor.
public struct RotorTarget: Sendable, Equatable {
    /// Element whose `accessibilityCustomRotors` should be used.
    public let target: AccessibilityTarget
    public let selection: RotorSelection
    /// Direction to move the held rotor cursor (forward/back).
    public let direction: RotorDirection

    public init(
        target: AccessibilityTarget,
        selection: RotorSelection = .automatic,
        direction: RotorDirection = .next
    ) {
        self.target = target
        self.selection = selection
        self.direction = direction
    }
}

extension RotorTarget: CustomStringConvertible {
    public var description: String {
        CanonicalValueDescription.call("rotor", [
            target.description,
            selection == .automatic ? nil : selection.description,
            CanonicalValueDescription.valueField("direction", direction),
        ].compactMap { $0 })
    }
}

extension RotorTarget: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case target
        case rotor
        case rotorIndex
        case direction
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "rotor target")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        target = try container.decode(AccessibilityTarget.self, forKey: .target)
        let rotor = try container.decodeIfPresent(RotorName.self, forKey: .rotor)
        let rotorIndex = try container.decodeIfPresent(Int.self, forKey: .rotorIndex)
        selection = try RotorSelection.decode(name: rotor, index: rotorIndex, codingPath: container.codingPath)
        direction = try container.decodeIfPresent(RotorDirection.self, forKey: .direction) ?? .next
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try selection.encode(to: &container, nameKey: .rotor, indexKey: .rotorIndex)
        try container.encode(direction, forKey: .direction)
    }
}
