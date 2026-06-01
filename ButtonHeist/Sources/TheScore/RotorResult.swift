import Foundation

/// Result from a live rotor step operation.
public struct RotorResult: Codable, Sendable {
    public let rotor: String
    public let direction: RotorDirection
    /// The selected element id, if the rotor resolved to an element. The action trace owns the element snapshot.
    public let foundHeistId: HeistId?
    public let textRange: RotorTextRange?

    public init(
        rotor: String,
        direction: RotorDirection,
        foundHeistId: HeistId? = nil,
        textRange: RotorTextRange? = nil
    ) {
        self.rotor = rotor
        self.direction = direction
        self.foundHeistId = foundHeistId
        self.textRange = textRange
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case rotor
        case direction
        case foundHeistId
        case textRange
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "RotorResult")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            rotor: try container.decode(String.self, forKey: .rotor),
            direction: try container.decode(RotorDirection.self, forKey: .direction),
            foundHeistId: try container.decodeIfPresent(HeistId.self, forKey: .foundHeistId),
            textRange: try container.decodeIfPresent(RotorTextRange.self, forKey: .textRange)
        )
    }
}

/// Text range returned by a rotor result.
public struct RotorTextRange: Codable, Equatable, Sendable {
    public let text: String?
    public let startOffset: Int?
    public let endOffset: Int?
    public let rangeDescription: String

    public init(
        text: String? = nil,
        startOffset: Int? = nil,
        endOffset: Int? = nil,
        rangeDescription: String
    ) {
        self.text = text
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.rangeDescription = rangeDescription
    }
}
