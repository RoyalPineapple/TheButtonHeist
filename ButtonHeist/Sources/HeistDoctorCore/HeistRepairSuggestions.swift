// MARK: - Heist Repair Suggester

public enum HeistRepairSuggester {
    public static func suggestions(for request: HeistRepairRequest) -> [HeistRepairSuggestion] {
        guard request.lastSuccess.result.succeeded,
              !request.currentFailure.result.succeeded,
              request.lastSuccess.stepPath == request.currentFailure.stepPath,
              repairFingerprintsAreCompatible(request.lastSuccess.heistFingerprint, request.currentFailure.heistFingerprint)
        else {
            return []
        }

        let lastScreen = RepairScreen(interface: request.lastSuccess.beforeSnapshot)
        let currentScreen = RepairScreen(interface: request.currentFailure.beforeSnapshot)
        guard case .resolved(let oldResolved, _) = lastScreen.resolve(request.lastSuccess.target) else {
            return []
        }

        let actionFamily = RepairActionFamily(
            actionKind: request.currentFailure.actionKind,
            method: request.currentFailure.result.method ?? request.lastSuccess.result.method
        )
        let currentResolution = currentScreen.resolve(request.lastSuccess.target)
        let failureKind: HeistRepairFailureKind
        let preferredCandidates: Set<String>

        switch currentResolution {
        case .resolved(let element, _):
            guard !actionFamily.isKnown || actionFamily.isSupported(by: element.element) == false else {
                return []
            }
            failureKind = .wrongCapability
            preferredCandidates = []

        case .notFound:
            failureKind = .missingTarget
            preferredCandidates = []

        case .ambiguous(let matches, _):
            failureKind = .ambiguousTarget
            preferredCandidates = Set(matches.map(\.id))
        }

        let ranked = RepairCandidateGenerator.rankedSuccessorCandidates(
            oldResolved: oldResolved,
            currentScreen: currentScreen,
            preferredCandidates: preferredCandidates,
            failureKind: failureKind,
            actionFamily: actionFamily,
            lastSuccess: request.lastSuccess,
            currentFailure: request.currentFailure
        )
        guard let bestScore = ranked.first?.score, bestScore >= 55 else {
            return []
        }

        let tiedBest = ranked.prefix { $0.score == bestScore }
        return tiedBest.prefix(3).compactMap { candidate in
            HeistRepairSuggestionRenderer.suggestion(
                for: candidate,
                oldResolved: oldResolved,
                currentScreen: currentScreen,
                request: request,
                failureKind: failureKind,
                currentResolution: currentResolution,
                actionFamily: actionFamily,
                tiedBestCount: tiedBest.count
            )
        }
    }

    public static func noSuggestionReason(for request: HeistRepairRequest) -> String {
        HeistRepairSuggestionRenderer.noSuggestionReason(for: request)
    }
}
