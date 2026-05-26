import Foundation

/// Target for custom actions.
///
/// Element targeting keeps the historical `elementTarget` wire field.
/// Container targeting uses the same `container` selector shape as
/// `get_interface.subtree`, with `ordinal` as the disambiguator.
public struct CustomActionTarget: Codable, Sendable {
    public let elementTarget: ElementTarget?
    public let containerTarget: ContainerMatcher?
    public let containerOrdinal: Int?
    public let actionName: String

    public init(elementTarget: ElementTarget, actionName: String) {
        self.elementTarget = elementTarget
        self.containerTarget = nil
        self.containerOrdinal = nil
        self.actionName = actionName
    }

    public init(containerTarget: ContainerMatcher, ordinal: Int? = nil, actionName: String) {
        self.elementTarget = nil
        self.containerTarget = containerTarget
        self.containerOrdinal = ordinal
        self.actionName = actionName
    }
}

extension CustomActionTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("customAction", [
            elementTarget?.description,
            containerTarget.map {
                ScoreDescription.call("container", [
                    $0.description,
                    ScoreDescription.valueField("ordinal", containerOrdinal),
                ].compactMap { $0 })
            },
            ScoreDescription.stringField("action", actionName),
        ].compactMap { $0 })
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
        actionName = try container.decode(String.self, forKey: .actionName)
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
            elementTarget = try container.decode(ElementTarget.self, forKey: .elementTarget)
            containerTarget = nil
            containerOrdinal = nil
        } else {
            elementTarget = nil
            let matcher = try container.decode(ContainerMatcher.self, forKey: .container)
            let ordinal = try container.decodeIfPresent(Int.self, forKey: .ordinal)
            guard matcher.hasPredicates || ordinal != nil else {
                throw DecodingError.dataCorruptedError(
                    forKey: .container,
                    in: container,
                    debugDescription: "CustomActionTarget container requires stableId, type, label, value, identifier, isModalBoundary, or ordinal"
                )
            }
            containerTarget = matcher
            if let ordinal, ordinal < 0 {
                throw DecodingError.dataCorruptedError(
                    forKey: .ordinal,
                    in: container,
                    debugDescription: "ordinal must be non-negative, got \(ordinal)"
                )
            }
            containerOrdinal = ordinal
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(actionName, forKey: .actionName)
        switch (elementTarget, containerTarget) {
        case (let elementTarget?, nil):
            try container.encode(elementTarget, forKey: .elementTarget)
        case (nil, let containerTarget?):
            try container.encode(containerTarget, forKey: .container)
            try container.encodeIfPresent(containerOrdinal, forKey: .ordinal)
        default:
            throw EncodingError.invalidValue(self, .init(
                codingPath: encoder.codingPath,
                debugDescription: "CustomActionTarget requires exactly one of elementTarget or container"
            ))
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

/// Target for moving through a rotor.
public struct RotorTarget: Sendable {
    /// Element whose `accessibilityCustomRotors` should be used.
    public let elementTarget: ElementTarget
    /// Select a rotor by display/name. When omitted, `rotorIndex` is used.
    public let rotor: String?
    /// Select a rotor by zero-based index when the name is omitted or ambiguous.
    public let rotorIndex: Int?
    /// Direction to move. Defaults to `.next`.
    public let direction: RotorDirection?
    /// Optional heistId for the current rotor item. Use the previous result's
    /// heistId to continue moving through a rotor like a VoiceOver user.
    public let currentHeistId: HeistId?
    /// Optional text-range cursor for continuing through text-range rotor
    /// results inside the element identified by `currentHeistId`.
    public let currentTextRange: TextRangeReference?

    public init(
        elementTarget: ElementTarget,
        rotor: String? = nil,
        rotorIndex: Int? = nil,
        direction: RotorDirection? = nil,
        currentHeistId: HeistId? = nil,
        currentTextRange: TextRangeReference? = nil
    ) {
        self.elementTarget = elementTarget
        self.rotor = rotor
        self.rotorIndex = rotorIndex
        self.direction = direction
        self.currentHeistId = currentHeistId
        self.currentTextRange = currentTextRange
    }

    public var resolvedDirection: RotorDirection { direction ?? .next }
}

extension RotorTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("rotor", [
            elementTarget.description,
            ScoreDescription.stringField("name", rotor),
            ScoreDescription.valueField("index", rotorIndex),
            ScoreDescription.valueField("direction", direction),
            ScoreDescription.stringField("currentHeistId", currentHeistId),
            currentTextRange?.description,
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
        elementTarget = try ElementTarget(from: decoder)
        rotor = try container.decodeIfPresent(String.self, forKey: .rotor)
        rotorIndex = try container.decodeIfPresent(Int.self, forKey: .rotorIndex)
        direction = try container.decodeIfPresent(RotorDirection.self, forKey: .direction)
        currentHeistId = try container.decodeIfPresent(HeistId.self, forKey: .currentHeistId)
        currentTextRange = try container.decodeIfPresent(TextRangeReference.self, forKey: .currentTextRange)
        if let rotorIndex, rotorIndex < 0 {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "rotorIndex must be non-negative, got \(rotorIndex)"
            ))
        }
        if let currentTextRange {
            guard currentTextRange.startOffset >= 0,
                  currentTextRange.endOffset >= currentTextRange.startOffset else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: container.codingPath + [CodingKeys.currentTextRange],
                    debugDescription: "currentTextRange must use non-negative offsets with endOffset >= startOffset"
                ))
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        try elementTarget.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(rotor, forKey: .rotor)
        try container.encodeIfPresent(rotorIndex, forKey: .rotorIndex)
        try container.encodeIfPresent(direction, forKey: .direction)
        try container.encodeIfPresent(currentHeistId, forKey: .currentHeistId)
        try container.encodeIfPresent(currentTextRange, forKey: .currentTextRange)
    }
}
