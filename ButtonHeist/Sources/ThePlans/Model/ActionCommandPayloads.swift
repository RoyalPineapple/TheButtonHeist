import Foundation

/// Target for custom actions.
///
/// Custom actions are element actions. Containers remain addressable by the
/// commands whose product subject is a container, such as scroll commands.
public struct CustomActionTarget: Codable, Sendable, Equatable, CustomStringConvertible {
    public let target: AccessibilityTarget
    public let actionName: String

    public init(target: AccessibilityTarget, actionName: String) {
        self.target = target
        self.actionName = actionName
    }

    public var description: String {
        ScoreDescription.call("customAction", [
            target.description,
            ScoreDescription.stringField("action", actionName),
        ].compactMap { $0 })
    }
}

enum CustomActionTargetValidationError: Error, Sendable, Equatable, CustomStringConvertible {
    case emptyActionName

    var description: String {
        switch self {
        case .emptyActionName:
            return "custom action name must not be empty"
        }
    }
}

extension CustomActionTarget {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case target
        case actionName
    }

    static func validate(actionName: String) throws {
        guard !actionName.isEmpty else {
            throw CustomActionTargetValidationError.emptyActionName
        }
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "custom action target")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let actionName = try container.decode(String.self, forKey: .actionName)
        do {
            try Self.validate(actionName: actionName)
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .actionName,
                in: container,
                debugDescription: String(describing: error)
            )
        }
        self.init(
            target: try container.decode(AccessibilityTarget.self, forKey: .target),
            actionName: actionName
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

public enum RotorSelection: Equatable, Hashable, Sendable {
    case automatic
    case named(String)
    case index(Int)

    public var rotorName: String? {
        guard case .named(let name) = self else { return nil }
        return name
    }

    public var rotorIndex: Int? {
        guard case .index(let index) = self else { return nil }
        return index
    }
}

extension RotorSelection {
    static func decode(
        name: String?,
        index: Int?,
        codingPath: [any CodingKey]
    ) throws -> Self {
        if name != nil, index != nil {
            throw DecodingError.dataCorrupted(.init(
                codingPath: codingPath,
                debugDescription: "rotor accepts either rotor or rotorIndex, not both"
            ))
        }
        if let index, index < 0 {
            throw DecodingError.dataCorrupted(.init(
                codingPath: codingPath,
                debugDescription: "rotorIndex must be non-negative, got \(index)"
            ))
        }
        if let name { return .named(name) }
        if let index { return .index(index) }
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
        case .index(let index): try container.encode(index, forKey: indexKey)
        }
    }
}

extension RotorSelection: CustomStringConvertible {
    public var description: String {
        switch self {
        case .automatic:
            return "automatic"
        case .named(let name):
            return ScoreDescription.stringField("name", name) ?? "name=\"\""
        case .index(let index):
            return ScoreDescription.valueField("index", index) ?? "index=\(index)"
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
        ScoreDescription.call("rotor", [
            target.description,
            selection == .automatic ? nil : selection.description,
            ScoreDescription.valueField("direction", direction),
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
        let rotor = try container.decodeIfPresent(String.self, forKey: .rotor)
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
