import TheScore

// MARK: - Heist Repair Suggester

public enum HeistRepairSuggester {
    public static func diagnosis(for request: HeistRepairRequest) -> HeistRepairDiagnosis {
        RepairDiagnosisPipeline.run(request)
    }

    public static func suggestions(for request: HeistRepairRequest) -> [HeistRepairSuggestion] {
        switch diagnosis(for: request) {
        case .suggested(let diagnosis):
            return diagnosis.suggestions
        case .refused:
            return []
        }
    }

    public static func noSuggestionReason(for request: HeistRepairRequest) -> String? {
        switch diagnosis(for: request) {
        case .suggested:
            return nil
        case .refused(let diagnosis):
            return diagnosis.refusal.message
        }
    }
}
