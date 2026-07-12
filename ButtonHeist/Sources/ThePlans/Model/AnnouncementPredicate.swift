import Foundation

public struct AnnouncementPredicate: Codable, Sendable, Equatable, Hashable {
    public let match: StringMatch<String>?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case match
    }

    public init(match: StringMatch<String>? = nil) {
        self.match = match
    }

    public init(_ text: String) {
        self.init(match: .exact(text))
    }

    public func matches(_ text: String) -> Bool {
        match?.matches(text) ?? true
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "announcement predicate")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(match: try container.decodeIfPresent(StringMatch<String>.self, forKey: .match))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(match, forKey: .match)
    }
}

extension AnnouncementPredicate: CustomStringConvertible {
    public var description: String {
        guard let match else { return "announcement" }
        return ScoreDescription.call("announcement", [match.description])
    }
}
