import Foundation

/// Target for custom actions.
///
/// Element targeting uses the public `elementTarget` wire field.
/// Container targeting uses the same `container` target object shape as
/// `get_interface.subtree`, with `ordinal` as the disambiguator.
public struct CustomActionTarget: Codable, Sendable {
    public let selection: CustomActionSelection

    public init(elementTarget: ElementTarget, actionName: String) {
        self.selection = .element(elementTarget, actionName: actionName)
    }

    public init(containerTarget: ContainerMatcher, ordinal: Int? = nil, actionName: String) {
        self.selection = .container(containerTarget, ordinal: ordinal, actionName: actionName)
    }

    public var elementTarget: ElementTarget? {
        guard case .element(let target, _) = selection else { return nil }
        return target
    }

    public var containerTarget: ContainerMatcher? {
        guard case .container(let target, _, _) = selection else { return nil }
        return target
    }

    public var containerOrdinal: Int? {
        guard case .container(_, let ordinal, _) = selection else { return nil }
        return ordinal
    }

    public var actionName: String {
        selection.actionName
    }
}

public enum CustomActionSelection: Sendable, Equatable, CustomStringConvertible {
    case element(ElementTarget, actionName: String)
    case container(ContainerMatcher, ordinal: Int?, actionName: String)

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

extension CustomActionTarget: CustomStringConvertible {
    public var description: String {
        selection.description
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
            selection = .element(
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
            selection = .container(matcher, ordinal: ordinal, actionName: actionName)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(actionName, forKey: .actionName)
        switch selection {
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

    public var currentHeistId: HeistId? {
        switch self {
        case .none:
            return nil
        case .item(let heistId), .textRange(let heistId, _):
            return heistId
        }
    }

    public var currentTextRange: TextRangeReference? {
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
            return ScoreDescription.stringField("currentHeistId", heistId) ?? "currentHeistId=\"\""
        case .textRange(let heistId, let range):
            return [
                ScoreDescription.stringField("currentHeistId", heistId) ?? "currentHeistId=\"\"",
                range.description,
            ].joined(separator: ", ")
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

    public var resolvedDirection: RotorDirection { direction }
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
        case currentHeistId
        case currentTextRange
    }

    public init(from decoder: Decoder) throws {
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
        let currentHeistId = try container.decodeIfPresent(HeistId.self, forKey: .currentHeistId)
        let currentTextRange = try container.decodeIfPresent(TextRangeReference.self, forKey: .currentTextRange)
        if let currentTextRange {
            guard currentTextRange.startOffset >= 0,
                  currentTextRange.endOffset >= currentTextRange.startOffset else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: container.codingPath + [CodingKeys.currentTextRange],
                    debugDescription: "currentTextRange must use non-negative offsets with endOffset >= startOffset"
                ))
            }
            guard let currentHeistId else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: container.codingPath + [CodingKeys.currentHeistId],
                    debugDescription: "currentTextRange requires currentHeistId"
                ))
            }
            continuation = .textRange(currentHeistId, currentTextRange)
        } else if let currentHeistId {
            continuation = .item(currentHeistId)
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
        case .item(let heistId):
            try container.encode(heistId, forKey: .currentHeistId)
        case .textRange(let heistId, let range):
            try container.encode(heistId, forKey: .currentHeistId)
            try container.encode(range, forKey: .currentTextRange)
        }
    }
}
