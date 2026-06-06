import ThePlans
import Foundation

/// Result from a live rotor step operation.
public struct RotorResult: Codable, Sendable, Equatable {
    public let rotor: String
    public let direction: RotorDirection
    /// Description of the element the rotor cursor currently holds, if it
    /// resolved to one. This is a read-only snapshot (no id, not a durable
    /// target): the rotor cursor is an ephemeral in-memory pointer, dropped when
    /// rotor mode exits, so the agent reads it rather than re-targeting it.
    public let foundElement: HeistElement?
    public let textRange: RotorTextRange?

    public init(
        rotor: String,
        direction: RotorDirection,
        foundElement: HeistElement? = nil,
        textRange: RotorTextRange? = nil
    ) {
        self.rotor = rotor
        self.direction = direction
        self.foundElement = foundElement
        self.textRange = textRange
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case rotor
        case direction
        case foundElement
        case textRange
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "RotorResult")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            rotor: try container.decode(String.self, forKey: .rotor),
            direction: try container.decode(RotorDirection.self, forKey: .direction),
            foundElement: try container.decodeIfPresent(HeistElement.self, forKey: .foundElement),
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
