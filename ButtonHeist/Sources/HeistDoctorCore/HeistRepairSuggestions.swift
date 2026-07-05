import TheScore

// MARK: - Heist Repair Suggester

public enum HeistRepairSuggester {
    public static func diagnosis(for request: HeistRepairRequest) -> HeistRepairDiagnosis {
        RepairDiagnosisPipeline.run(request)
    }

    public static func suggestions(for request: HeistRepairRequest) -> [HeistRepairSuggestion] {
        diagnosis(for: request).suggestions
    }

    public static func noSuggestionReason(for request: HeistRepairRequest) -> String? {
        diagnosis(for: request).refusal?.message
    }
}
