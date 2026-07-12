public enum RepairScoringReason: String, Codable, Sendable, Hashable {
    case oldTargetIsCurrentMatch
    case identifierUnchanged
    case labelUnchanged
    case labelSemanticRename
    case valueUnchanged
    case valueSemanticRename
    case controlRoleTraitsCompatible
    case elementActionsCompatible
    case rotorCapabilityCompatible
    case siblingRowContextPreserved
    case headerContextPreserved
    case changeFactEvidenceMatchesElement
    case expectationEvidenceMatchesElement
    case onlyCurrentSemanticCandidate
    case elementSupportsSameActionFamily
    case onlyCurrentElementWithCompatibleActionFamily
}

public enum RepairSuggestionReason: Codable, Sendable, Hashable {
    case oldTargetResolvedInLastSuccessfulSnapshot
    case oldTargetResolvesWithoutRequestedAction
    case oldTargetCurrentMatchCount(Int)
    case suggestedMatcherResolvesExactlyOneElement
    case noSemanticOnlyMatcherUnique
    case currentFailureSuppliedDifferentTarget
    case missingTargetSuccessorSelected
    case ambiguousTargetSuccessorSelected
    case scoring(RepairScoringReason)
    case changeFact(RepairEvidenceSource, RepairChangeFactObservation)
    case lastSuccessfulExpectationMet
    case currentFailureExpectationUnmet
}

public enum RepairCaveat: String, Codable, Sendable, Hashable {
    case candidateDoesNotExposeSameActionFamily
    case ordinalDisambiguation
    case tiedBestCandidates
}

public enum RepairEvidenceSource: String, Codable, Sendable, Hashable {
    case lastSuccess
    case currentFailure
}

public enum RepairChangeFactObservation: Codable, Sendable, Hashable {
    case noSemanticChange
    case screenChange
    case valueChange(old: String?, new: String?)
    case semanticElementsAdded
    case semanticElementsRemoved
    case elementChanges
}

extension RepairSuggestionReason {
    package var reportText: String {
        switch self {
        case .oldTargetResolvedInLastSuccessfulSnapshot:
            return "Old target resolved to one element in the last successful before snapshot."
        case .oldTargetResolvesWithoutRequestedAction:
            return "Old target still resolves, but the resolved element does not support the requested action."
        case .oldTargetCurrentMatchCount(let matchCount):
            return "Old target resolves to \(matchCount) elements in the new before snapshot."
        case .suggestedMatcherResolvesExactlyOneElement:
            return "Suggested matcher resolves exactly one element in the new before snapshot."
        case .noSemanticOnlyMatcherUnique:
            return "No semantic-only matcher was unique for the successor element."
        case .currentFailureSuppliedDifferentTarget:
            return "Current failure evidence supplied a different target; repair compared against the last successful target."
        case .missingTargetSuccessorSelected:
            return "Best successor was selected from semantic continuity after the old target went missing."
        case .ambiguousTargetSuccessorSelected:
            return "Best successor was selected from the ambiguous current matches."
        case .scoring(let reason):
            return reason.reportText
        case .changeFact(let source, let observation):
            return "\(source.changeFactPrefix) \(observation.reportText)."
        case .lastSuccessfulExpectationMet:
            return "Last successful result met its expectation."
        case .currentFailureExpectationUnmet:
            return "Current failure result did not meet its expectation."
        }
    }
}

extension RepairScoringReason {
    var reportText: String {
        switch self {
        case .oldTargetIsCurrentMatch:
            return "Old target is one of the current matches."
        case .identifierUnchanged:
            return "Accessibility identifier is unchanged."
        case .labelUnchanged:
            return "Label is unchanged."
        case .labelSemanticRename:
            return "Label is a close semantic rename."
        case .valueUnchanged:
            return "Value is unchanged."
        case .valueSemanticRename:
            return "Value is a close semantic rename."
        case .controlRoleTraitsCompatible:
            return "Control role traits are compatible."
        case .elementActionsCompatible:
            return "Element actions are compatible."
        case .rotorCapabilityCompatible:
            return "Rotor capability is compatible."
        case .siblingRowContextPreserved:
            return "Sibling row context is preserved."
        case .headerContextPreserved:
            return "Header context is preserved."
        case .changeFactEvidenceMatchesElement:
            return "Change-fact evidence mentions the same semantic element."
        case .expectationEvidenceMatchesElement:
            return "Expectation evidence mentions the same semantic element."
        case .onlyCurrentSemanticCandidate:
            return "It is the only current semantic candidate."
        case .elementSupportsSameActionFamily:
            return "Element supports the same action family."
        case .onlyCurrentElementWithCompatibleActionFamily:
            return "It is the only current element with a compatible action family."
        }
    }
}

extension RepairCaveat {
    package var reportText: String {
        switch self {
        case .candidateDoesNotExposeSameActionFamily:
            return "Candidate does not expose the same action family."
        case .ordinalDisambiguation:
            return "Suggested matcher uses ordinal as last-resort disambiguation."
        case .tiedBestCandidates:
            return "Multiple candidates have the same semantic score."
        }
    }
}

extension RepairEvidenceSource {
    var changeFactPrefix: String {
        switch self {
        case .lastSuccess:
            return "Last successful change facts"
        case .currentFailure:
            return "Current failure change facts"
        }
    }
}

extension RepairChangeFactObservation {
    var reportText: String {
        switch self {
        case .noSemanticChange:
            return "observed no semantic change"
        case .screenChange:
            return "observed a screen change"
        case .valueChange(let old, let new):
            return "observed value change from \(old ?? "nil") to \(new ?? "nil")"
        case .semanticElementsAdded:
            return "observed semantic elements added"
        case .semanticElementsRemoved:
            return "observed semantic elements removed"
        case .elementChanges:
            return "observed element changes"
        }
    }
}
