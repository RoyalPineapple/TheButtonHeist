import ThePlans
import TheScore

enum HeistRepairSuggestionRenderer {
    static func noSuggestionReason(for request: HeistRepairRequest) -> String {
        if !request.lastSuccess.result.succeeded {
            return "last receipt step did not pass"
        }
        if request.currentFailure.result.succeeded {
            return "current receipt step did not fail"
        }
        if request.lastSuccess.stepPath != request.currentFailure.stepPath {
            return "receipts refer to different step paths"
        }
        if !repairFingerprintsAreCompatible(request.lastSuccess.heistFingerprint, request.currentFailure.heistFingerprint) {
            return "heist fingerprints are incompatible"
        }

        let lastScreen = RepairScreen(interface: request.lastSuccess.beforeSnapshot)
        let currentScreen = RepairScreen(interface: request.currentFailure.beforeSnapshot)
        guard case .resolved = lastScreen.resolve(request.lastSuccess.target) else {
            return "old target did not resolve exactly once in the last successful before snapshot"
        }

        let actionFamily = RepairActionFamily(
            actionIdentity: request.currentFailure.actionIdentity
        )
        switch currentScreen.resolve(request.lastSuccess.target) {
        case .resolved(let element, _):
            if !actionFamily.isKnown || actionFamily.isSupported(by: element.element) {
                return "old target still resolves and supports the requested action; no target repair needed"
            }
            return """
                old target still resolves but does not support the requested action; \
                no safe compatible successor satisfied semantic continuity and unique-matcher requirements
                """

        case .notFound:
            return """
                old target is missing in the current before snapshot; \
                no safe successor satisfied semantic continuity and unique-matcher requirements
                """

        case .ambiguous:
            return """
                old target is ambiguous in the current before snapshot; \
                no candidate could be safely disambiguated
                """
        }
    }

    static func suggestion(
        for candidate: ScoredCandidate,
        oldResolved: RepairScreen.Element,
        currentScreen: RepairScreen,
        request: HeistRepairRequest,
        failureKind: HeistRepairFailureKind,
        currentResolution: RepairTargetResolution,
        actionFamily: RepairActionFamily,
        tiedBestCount: Int
    ) -> HeistRepairSuggestion? {
        let selectionContext = currentScreen.selectionContext()
        guard let selection = minimumUniquePredicate(for: candidate.element.id, in: selectionContext),
              case .resolved(let validation, _) = currentScreen.resolve(selection.target),
              validation.id == candidate.element.id
        else {
            return nil
        }

        if actionFamily.isKnown, !actionFamily.isSupported(by: candidate.element.element) {
            return nil
        }

        var reasons = baseReasons(
            failureKind: failureKind,
            currentResolution: currentResolution,
            selection: selection,
            lastSuccess: request.lastSuccess,
            currentFailure: request.currentFailure
        )
        reasons.append(contentsOf: candidate.reasons)
        reasons.append(contentsOf: afterEvidenceReasons(
            lastSuccess: request.lastSuccess,
            currentFailure: request.currentFailure
        ))

        var caveats = candidate.caveats
        if selection.candidate.tier == .ordinalDisambiguation,
           !request.lastSuccess.target.hasOrdinal {
            caveats.append("Suggested matcher uses ordinal as last-resort disambiguation.")
        }
        if tiedBestCount > 1 {
            caveats.append("Multiple candidates have the same semantic score.")
        }
        if request.lastSuccess.afterDelta == nil, request.lastSuccess.afterSnapshot != nil {
            caveats.append("Last successful evidence used a full after snapshot because compact diff was unavailable.")
        }
        if request.currentFailure.afterDelta == nil, request.currentFailure.afterSnapshot != nil {
            caveats.append("Current failure evidence used a full after snapshot because compact diff was unavailable.")
        }

        return HeistRepairSuggestion(
            stepPath: request.currentFailure.stepPath,
            failureKind: failureKind,
            oldTarget: request.lastSuccess.target,
            oldResolvedElement: oldResolved.summary,
            newTarget: selection.target,
            newResolvedElement: candidate.element.summary,
            confidence: confidence(
                score: candidate.score,
                selection: selection,
                oldTargetHadOrdinal: request.lastSuccess.target.hasOrdinal,
                tiedBestCount: tiedBestCount,
                failureKind: failureKind
            ),
            reasons: unique(reasons),
            caveats: unique(caveats)
        )
    }

    private static func baseReasons(
        failureKind: HeistRepairFailureKind,
        currentResolution: RepairTargetResolution,
        selection: MinimumPredicateSelection,
        lastSuccess: HeistStepRepairEvidence,
        currentFailure: HeistStepRepairEvidence
    ) -> [String] {
        var reasons = [
            "Old target resolved to one element in the last successful before snapshot.",
        ]
        switch currentResolution {
        case .resolved:
            reasons.append("Old target still resolves, but the resolved element does not support the requested action.")
        case .notFound(let matchCount):
            reasons.append("Old target resolves to \(matchCount) elements in the new before snapshot.")
        case .ambiguous(_, let matchCount):
            reasons.append("Old target resolves to \(matchCount) elements in the new before snapshot.")
        }
        reasons.append("Suggested matcher resolves exactly one element in the new before snapshot.")
        if selection.candidate.tier == .ordinalDisambiguation {
            reasons.append("No semantic-only matcher was unique for the successor element.")
        }
        if lastSuccess.target != currentFailure.target {
            reasons.append("Current failure evidence supplied a different target; repair compared against the last successful target.")
        }
        if failureKind == .missingTarget {
            reasons.append("Best successor was selected from semantic continuity after the old target went missing.")
        }
        if failureKind == .ambiguousTarget {
            reasons.append("Best successor was selected from the ambiguous current matches.")
        }
        return reasons
    }

    private static func afterEvidenceReasons(
        lastSuccess: HeistStepRepairEvidence,
        currentFailure: HeistStepRepairEvidence
    ) -> [String] {
        var reasons: [String] = []
        if let reason = deltaReason(prefix: "Last successful after diff", delta: lastSuccess.afterDelta) {
            reasons.append(reason)
        }
        if let reason = deltaReason(prefix: "Current failure after diff", delta: currentFailure.afterDelta) {
            reasons.append(reason)
        }
        if let expectation = lastSuccess.result.expectation, expectation.met {
            reasons.append("Last successful result met its expectation.")
        }
        if let expectation = currentFailure.result.expectation, !expectation.met {
            reasons.append("Current failure result did not meet its expectation.")
        }
        return reasons
    }

    private static func deltaReason(prefix: String, delta: AccessibilityTrace.Delta?) -> String? {
        guard let delta else { return nil }
        switch delta {
        case .noChange:
            return "\(prefix) observed no semantic change."
        case .screenChanged:
            return "\(prefix) observed a screen change."
        case .elementsChanged(let payload):
            if let valueChange = payload.edits.updated
                .flatMap(\.changes)
                .first(where: { $0.property == .value }) {
                let old = valueChange.oldValue?.displayText ?? "nil"
                let new = valueChange.newValue?.displayText ?? "nil"
                return "\(prefix) observed value change from \(old) to \(new)."
            }
            if !payload.edits.added.isEmpty {
                return "\(prefix) observed semantic elements added."
            }
            if !payload.edits.removed.isEmpty {
                return "\(prefix) observed semantic elements removed."
            }
            return "\(prefix) observed element changes."
        }
    }

    private static func confidence(
        score: Int,
        selection: MinimumPredicateSelection,
        oldTargetHadOrdinal: Bool,
        tiedBestCount: Int,
        failureKind: HeistRepairFailureKind
    ) -> RepairConfidence {
        if selection.candidate.tier == .ordinalDisambiguation, !oldTargetHadOrdinal {
            return .low
        }
        if tiedBestCount > 1 {
            return .low
        }
        if failureKind == .wrongCapability {
            return .low
        }
        if score >= 120 {
            return .high
        }
        if score >= 75 {
            return .medium
        }
        return .low
    }
}
