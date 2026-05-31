import Foundation

/// Target for custom actions.
///
/// Element targeting uses the public `elementTarget` wire field.
/// Container targeting uses the same `container` target object shape as
/// `get_interface.subtree`, with `ordinal` as the disambiguator.
public enum CustomActionTarget: Codable, Sendable, Equatable, CustomStringConvertible {
    case element(ElementTarget, actionName: String)
    case container(ContainerMatcher, ordinal: Int?, actionName: String)

    public init(elementTarget: ElementTarget, actionName: String) {
        self = .element(elementTarget, actionName: actionName)
    }

    public init(containerTarget: ContainerMatcher, ordinal: Int? = nil, actionName: String) {
        self = .container(containerTarget, ordinal: ordinal, actionName: actionName)
    }

    public var actionName: String {
        switch self {
        case .element(_, let actionName), .container(_, _, let actionName):
            return actionName
        }
    }

    public var description: String {
        switch self {
        case .element(let target, let actionName):
            return ScoreDescription.call("customAction", [
                target.description,
                ScoreDescription.stringField("action", actionName),
            ].compactMap { $0 })
        case .container(let target, let ordinal, let actionName):
            return ScoreDescription.call("customAction", [
                ScoreDescription.call("container", [
                    target.description,
                    ScoreDescription.valueField("ordinal", ordinal),
                ].compactMap { $0 }),
                ScoreDescription.stringField("action", actionName),
            ].compactMap { $0 })
        }
    }
}

extension CustomActionTarget {
    private enum CodingKeys: String, CodingKey {
        case elementTarget
        case container
        case ordinal
        case actionName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let actionName = try container.decode(String.self, forKey: .actionName)
        let hasElementTarget = container.contains(.elementTarget)
        let hasContainerTarget = container.contains(.container)
        guard hasElementTarget != hasContainerTarget else {
            throw DecodingError.dataCorruptedError(
                forKey: .elementTarget,
                in: container,
                debugDescription: "CustomActionTarget requires exactly one of elementTarget or container"
            )
        }
        if hasElementTarget {
            self = .element(
                try container.decode(ElementTarget.self, forKey: .elementTarget),
                actionName: actionName
            )
        } else {
            let matcher = try container.decode(ContainerMatcher.self, forKey: .container)
            let ordinal = try container.decodeIfPresent(Int.self, forKey: .ordinal)
            guard matcher.hasPredicates else {
                throw DecodingError.dataCorruptedError(
                    forKey: .container,
                    in: container,
                    debugDescription: """
                    CustomActionTarget container requires stableId, type, label, value, identifier, \
                    or isModalBoundary; ordinal only disambiguates a container matcher
                    """
                )
            }
            if let ordinal, ordinal < 0 {
                throw DecodingError.dataCorruptedError(
                    forKey: .ordinal,
                    in: container,
                    debugDescription: "ordinal must be non-negative, got \(ordinal)"
                )
            }
            self = .container(matcher, ordinal: ordinal, actionName: actionName)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(actionName, forKey: .actionName)
        switch self {
        case .element(let elementTarget, _):
            try container.encode(elementTarget, forKey: .elementTarget)
        case .container(let containerTarget, let containerOrdinal, _):
            guard containerTarget.hasPredicates else {
                throw EncodingError.invalidValue(containerTarget, .init(
                    codingPath: encoder.codingPath + [CodingKeys.container],
                    debugDescription: """
                    CustomActionTarget container requires stableId, type, label, value, identifier, \
                    or isModalBoundary; ordinal only disambiguates a container matcher
                    """
                ))
            }
            try container.encode(containerTarget, forKey: .container)
            try container.encodeIfPresent(containerOrdinal, forKey: .ordinal)
        }
    }
}

/// Direction for a rotor step.
public enum RotorDirection: String, Codable, Sendable, CaseIterable {
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

public enum RotorContinuation: Equatable, Hashable, Sendable {
    case none
    case item(HeistId)
    case textRange(HeistId, TextRangeReference)

    public var heistId: HeistId? {
        switch self {
        case .none:
            return nil
        case .item(let heistId), .textRange(let heistId, _):
            return heistId
        }
    }

    public var textRange: TextRangeReference? {
        guard case .textRange(_, let range) = self else { return nil }
        return range
    }
}

extension RotorContinuation: CustomStringConvertible {
    public var description: String {
        switch self {
        case .none:
            return "noContinuation"
        case .item(let heistId):
            return ScoreDescription.stringField("continuation.heistId", heistId) ?? "continuation.heistId=\"\""
        case .textRange(let heistId, let range):
            return [
                ScoreDescription.stringField("continuation.heistId", heistId) ?? "continuation.heistId=\"\"",
                range.description,
            ].joined(separator: ", ")
        }
    }
}

extension RotorContinuation: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case heistId
        case textRange
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(
            allowed: CodingKeys.self,
            typeName: "rotor continuation"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let heistId = try container.decode(HeistId.self, forKey: .heistId)
        if let textRange = try container.decodeIfPresent(TextRangeReference.self, forKey: .textRange) {
            try Self.validate(textRange, codingPath: container.codingPath + [CodingKeys.textRange])
            self = .textRange(heistId, textRange)
        } else {
            self = .item(heistId)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            break
        case .item(let heistId):
            try container.encode(heistId, forKey: .heistId)
        case .textRange(let heistId, let textRange):
            try container.encode(heistId, forKey: .heistId)
            try container.encode(textRange, forKey: .textRange)
        }
    }

    static func validate(_ textRange: TextRangeReference, codingPath: [CodingKey]) throws {
        guard textRange.startOffset >= 0,
              textRange.endOffset >= textRange.startOffset else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: codingPath,
                debugDescription: "textRange must use non-negative offsets with endOffset >= startOffset"
            ))
        }
    }

}

/// Target for moving through a rotor.
public struct RotorTarget: Sendable {
    /// Element whose `accessibilityCustomRotors` should be used.
    public let elementTarget: ElementTarget
    public let selection: RotorSelection
    /// Direction to move.
    public let direction: RotorDirection
    public let continuation: RotorContinuation

    public init(
        elementTarget: ElementTarget,
        selection: RotorSelection = .automatic,
        direction: RotorDirection = .next,
        continuation: RotorContinuation = .none
    ) {
        self.elementTarget = elementTarget
        self.selection = selection
        self.direction = direction
        self.continuation = continuation
    }
}

extension RotorTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("rotor", [
            elementTarget.description,
            selection == .automatic ? nil : selection.description,
            ScoreDescription.valueField("direction", direction),
            continuation == .none ? nil : continuation.description,
        ].compactMap { $0 })
    }
}

extension RotorTarget: Codable {
    private enum CodingKeys: String, CodingKey {
        case rotor
        case rotorIndex
        case direction
        case continuation
    }

    public init(from decoder: Decoder) throws {
        try Self.rejectUnknownKeys(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        elementTarget = try ElementTarget.decodeInline(from: decoder)
        let rotor = try container.decodeIfPresent(String.self, forKey: .rotor)
        let rotorIndex = try container.decodeIfPresent(Int.self, forKey: .rotorIndex)
        if rotor != nil, rotorIndex != nil {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "rotor accepts either rotor or rotorIndex, not both"
            ))
        }
        if let rotorIndex, rotorIndex < 0 {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "rotorIndex must be non-negative, got \(rotorIndex)"
            ))
        }
        selection = if let rotor {
            .named(rotor)
        } else if let rotorIndex {
            .index(rotorIndex)
        } else {
            .automatic
        }
        direction = try container.decodeIfPresent(RotorDirection.self, forKey: .direction) ?? .next
        if container.contains(.continuation) {
            continuation = try container.decode(RotorContinuation.self, forKey: .continuation)
        } else {
            continuation = .none
        }
    }

    public func encode(to encoder: Encoder) throws {
        try elementTarget.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch selection {
        case .automatic:
            break
        case .named(let rotor):
            try container.encode(rotor, forKey: .rotor)
        case .index(let rotorIndex):
            try container.encode(rotorIndex, forKey: .rotorIndex)
        }
        try container.encode(direction, forKey: .direction)
        switch continuation {
        case .none:
            break
        case .item, .textRange:
            try container.encode(continuation, forKey: .continuation)
        }
    }

    private static func rejectUnknownKeys(from decoder: Decoder) throws {
        let allowedKeys = Set(
            ElementTarget.inlineFieldNames + [
                CodingKeys.rotor.stringValue,
                CodingKeys.rotorIndex.stringValue,
                CodingKeys.direction.stringValue,
                CodingKeys.continuation.stringValue,
            ]
        )
        try decoder.rejectUnknownKeys(allowed: allowedKeys, typeName: "rotor target")
    }
}
