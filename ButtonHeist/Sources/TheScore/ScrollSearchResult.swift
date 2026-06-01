import Foundation

/// Diagnostics from a scroll_to_visible search operation.
public struct ScrollSearchResult: Codable, Sendable {
    /// Number of scroll operations performed
    public let scrollCount: Int
    /// Number of unique elements seen across all scroll positions
    public let uniqueElementsSeen: Int
    /// Whether every item in the data source was checked
    public let exhaustive: Bool
    /// The matched element id, if found. The action trace owns the element snapshot.
    public let foundHeistId: HeistId?

    public init(
        scrollCount: Int,
        uniqueElementsSeen: Int,
        exhaustive: Bool,
        foundHeistId: HeistId? = nil
    ) {
        self.scrollCount = scrollCount
        self.uniqueElementsSeen = uniqueElementsSeen
        self.exhaustive = exhaustive
        self.foundHeistId = foundHeistId
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case scrollCount
        case uniqueElementsSeen
        case exhaustive
        case foundHeistId
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "ScrollSearchResult")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            scrollCount: try container.decode(Int.self, forKey: .scrollCount),
            uniqueElementsSeen: try container.decode(Int.self, forKey: .uniqueElementsSeen),
            exhaustive: try container.decode(Bool.self, forKey: .exhaustive),
            foundHeistId: try container.decodeIfPresent(HeistId.self, forKey: .foundHeistId)
        )
    }
}
