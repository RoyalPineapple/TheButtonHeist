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
    private let shape: Shape

    public var text: String? {
        guard case .indexed(let text, _, _, _) = shape else {
            return nil
        }
        return text
    }

    public var startOffset: Int? {
        guard case .indexed(_, let startOffset, _, _) = shape else {
            return nil
        }
        return startOffset
    }

    public var endOffset: Int? {
        guard case .indexed(_, _, let endOffset, _) = shape else {
            return nil
        }
        return endOffset
    }

    public var rangeDescription: String {
        switch shape {
        case .described(let rangeDescription), .indexed(_, _, _, let rangeDescription):
            return rangeDescription
        }
    }

    public init(rangeDescription: String) {
        self.shape = .described(rangeDescription: rangeDescription)
    }

    public init(text: String?, startOffset: Int, endOffset: Int, rangeDescription: String) {
        self.shape = .indexed(
            text: text,
            startOffset: startOffset,
            endOffset: endOffset,
            rangeDescription: rangeDescription
        )
    }

    private enum Shape: Equatable, Sendable {
        case described(rangeDescription: String)
        case indexed(text: String?, startOffset: Int, endOffset: Int, rangeDescription: String)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case text
        case startOffset
        case endOffset
        case rangeDescription
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "RotorTextRange")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let text = try container.decodeIfPresent(String.self, forKey: .text)
        let startOffset = try container.decodeIfPresent(Int.self, forKey: .startOffset)
        let endOffset = try container.decodeIfPresent(Int.self, forKey: .endOffset)
        let rangeDescription = try container.decode(String.self, forKey: .rangeDescription)

        switch (text, startOffset, endOffset) {
        case (nil, nil, nil):
            self.init(rangeDescription: rangeDescription)
        case (let text, .some(let startOffset), .some(let endOffset)):
            self.init(
                text: text,
                startOffset: startOffset,
                endOffset: endOffset,
                rangeDescription: rangeDescription
            )
        default:
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "RotorTextRange requires startOffset and endOffset together; description-only ranges cannot include text"
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(startOffset, forKey: .startOffset)
        try container.encodeIfPresent(endOffset, forKey: .endOffset)
        try container.encode(rangeDescription, forKey: .rangeDescription)
    }
}
