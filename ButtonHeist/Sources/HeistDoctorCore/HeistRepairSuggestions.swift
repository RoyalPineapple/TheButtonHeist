import TheScore

// MARK: - Heist Repair Suggester

public enum HeistRepairSuggester {
    public static func suggestions(for request: HeistRepairRequest) -> [HeistRepairSuggestion] {
        let analysis = HeistRepairAnalysis.analyze(request)
        guard case .eligible(let eligibleAnalysis) = analysis else {
            return []
        }

        guard let bestScore = eligibleAnalysis.rankedCandidates.first?.score, bestScore >= 55 else {
            return []
        }

        let tiedBest = eligibleAnalysis.rankedCandidates.prefix { $0.score == bestScore }
        return tiedBest.prefix(3).compactMap { candidate in
            HeistRepairSuggestionRenderer.suggestion(
                for: candidate,
                analysis: eligibleAnalysis,
                request: request,
                tiedBestCount: tiedBest.count
            )
        }
    }

    public static func noSuggestionReason(for request: HeistRepairRequest) -> String {
        HeistRepairSuggestionRenderer.noSuggestionReason(
            for: HeistRepairAnalysis.analyze(request)
        )
    }
}
