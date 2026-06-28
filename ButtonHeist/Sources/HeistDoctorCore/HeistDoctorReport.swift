import ThePlans

public enum HeistDoctorFeatureStatus: String, Codable, Sendable, Equatable {
    case alpha
}

public struct HeistDoctorReport: Codable, Sendable, Equatable {
    public let status: HeistDoctorFeatureStatus
    public let suggestions: [HeistRepairSuggestion]

    public init(
        suggestions: [HeistRepairSuggestion],
        status: HeistDoctorFeatureStatus = .alpha
    ) {
        self.status = status
        self.suggestions = suggestions
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case status
        case suggestions
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist-doctor report")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(HeistDoctorFeatureStatus.self, forKey: .status)
        suggestions = try container.decode([HeistRepairSuggestion].self, forKey: .suggestions)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encode(suggestions, forKey: .suggestions)
    }
}
