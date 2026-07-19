import Foundation

public struct AnnouncementPredicate: Codable, Sendable, Equatable, Hashable {
    public let match: StringMatch?

    private enum CodingKeys: String, CodingKey, CaseIterable { case match }

    public init(match: StringMatch? = nil) {
        self.match = match
    }

    public init(_ text: String) {
        self.init(match: .exact(text))
    }

    package func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedAnnouncementPredicate {
        ResolvedAnnouncementPredicate(match: try match?.resolve(in: environment))
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "announcement predicate")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        match = try container.decodeIfPresent(StringMatch.self, forKey: .match)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(match, forKey: .match)
    }
}

extension AnnouncementPredicate: CustomStringConvertible {
    public var description: String {
        guard let match else { return "announcement" }
        return CanonicalValueDescription.call("announcement", [match.description])
    }
}

public struct ResolvedAnnouncementPredicate: Sendable, Equatable, Hashable {
    package let match: ResolvedStringMatch?

    package init(match: ResolvedStringMatch?) {
        self.match = match
    }

    public func matches(_ text: String) -> Bool {
        match?.matches(text) ?? true
    }
}

extension ResolvedAnnouncementPredicate: CustomStringConvertible {
    public var description: String {
        guard let match else { return "announcement" }
        return CanonicalValueDescription.call("announcement", [match.core.description])
    }
}
