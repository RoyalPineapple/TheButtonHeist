public struct HeistDoctorReport: Codable, Sendable, Equatable {
    public let featureStatus: String
    public let suggestions: [HeistRepairSuggestion]

    public init(
        suggestions: [HeistRepairSuggestion],
        featureStatus: String = "alpha"
    ) {
        self.featureStatus = featureStatus
        self.suggestions = suggestions
    }
}
