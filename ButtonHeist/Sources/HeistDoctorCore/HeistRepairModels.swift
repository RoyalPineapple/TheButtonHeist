import Foundation
import ThePlans
import TheScore

// MARK: - Heist Repair Evidence

public enum HeistRepairEvidenceOutcome: Codable, Sendable, Equatable {
    case passed
    case failed(errorKind: ErrorKind?, message: String?)
}

public struct HeistRepairEvidence: Codable, Sendable, Equatable {
    public let heistFingerprint: String?
    public let stepPath: String
    public let command: HeistActionCommand
    public let target: AccessibilityTarget
    public let beforeSnapshot: Interface
    public let changeFacts: [AccessibilityTrace.ChangeFact]
    public let method: ActionMethod?
    public let expectation: ExpectationResult?
    public let outcome: HeistRepairEvidenceOutcome

    public init(
        heistFingerprint: String? = nil,
        stepPath: String,
        command: HeistActionCommand,
        target: AccessibilityTarget,
        beforeSnapshot: Interface,
        changeFacts: [AccessibilityTrace.ChangeFact] = [],
        method: ActionMethod? = nil,
        expectation: ExpectationResult? = nil,
        outcome: HeistRepairEvidenceOutcome
    ) {
        self.heistFingerprint = heistFingerprint
        self.stepPath = stepPath
        self.command = command
        self.target = target
        self.beforeSnapshot = beforeSnapshot
        self.changeFacts = changeFacts
        self.method = method
        self.expectation = expectation
        self.outcome = outcome
    }
}

public struct HeistRepairRequest: Codable, Sendable, Equatable {
    public let lastSuccess: HeistRepairEvidence
    public let currentFailure: HeistRepairEvidence

    public init(
        lastSuccess: HeistRepairEvidence,
        currentFailure: HeistRepairEvidence
    ) throws {
        guard case .passed = lastSuccess.outcome else {
            throw ValidationError.lastSuccessDidNotPass
        }
        guard case .failed = currentFailure.outcome else {
            throw ValidationError.currentFailureDidNotFail
        }
        self.lastSuccess = lastSuccess
        self.currentFailure = currentFailure
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case lastSuccess
        case currentFailure
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist repair request")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let lastSuccess = try container.decode(HeistRepairEvidence.self, forKey: .lastSuccess)
        let currentFailure = try container.decode(HeistRepairEvidence.self, forKey: .currentFailure)
        do {
            try self.init(lastSuccess: lastSuccess, currentFailure: currentFailure)
        } catch {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: String(describing: error)
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lastSuccess, forKey: .lastSuccess)
        try container.encode(currentFailure, forKey: .currentFailure)
    }

    private enum ValidationError: Error, CustomStringConvertible {
        case lastSuccessDidNotPass
        case currentFailureDidNotFail

        var description: String {
            switch self {
            case .lastSuccessDidNotPass:
                return "lastSuccess repair evidence must have a passed outcome"
            case .currentFailureDidNotFail:
                return "currentFailure repair evidence must have a failed outcome"
            }
        }
    }
}

// MARK: - Heist Repair Suggestion

public enum HeistRepairFailureKind: String, Codable, Sendable, Equatable {
    case missingTarget
    case ambiguousTarget
    case wrongCapability
}

public enum RepairConfidence: String, Codable, Sendable, Equatable {
    case high
    case medium
    case low
}

public enum HeistRepairPipelineStage: String, Codable, Sendable, Equatable {
    case evidenceEligibility
    case candidateRanking
    case candidateValidation
}

public enum HeistRepairRefusalReason: String, Codable, Sendable, Equatable {
    case differentStepPaths
    case incompatibleHeistFingerprints
    case oldTargetDidNotResolveExactlyOnce
    case containerTargetUnsupported
    case targetReferenceUnsupported
    case scopedTargetUnsupported
    case unresolvedTargetExpression
    case oldTargetStillResolvesAndSupportsRequestedAction
    case noCandidateMetScoreThreshold
    case noCandidateValidated
}

public struct HeistRepairRefusal: Codable, Sendable, Equatable {
    public let stage: HeistRepairPipelineStage
    public let reason: HeistRepairRefusalReason
    public let message: String

    public init(
        stage: HeistRepairPipelineStage,
        reason: HeistRepairRefusalReason,
        message: String
    ) {
        self.stage = stage
        self.reason = reason
        self.message = message
    }
}

public enum RepairCandidateSource: String, Codable, Sendable, Hashable {
    case semanticContinuityScan
    case currentAmbiguousMatch
}

public enum RepairCandidateRejectionReason: String, Codable, Sendable, Equatable {
    case noUniqueDurableMatcher
    case unsupportedActionFamily
}

public struct HeistRepairElementContext: Codable, Sendable, Equatable {
    public let element: HeistElement
    public let siblingText: [String]
    public let headerText: [String]

    public init(
        element: HeistElement,
        siblingText: [String] = [],
        headerText: [String] = []
    ) {
        self.element = element
        self.siblingText = siblingText
        self.headerText = headerText
    }
}

public enum RepairCandidateValidation: Codable, Sendable, Equatable {
    case notEvaluated
    case suggested(target: AccessibilityTarget, confidence: RepairConfidence)
    case rejected(reason: RepairCandidateRejectionReason)
}

public struct HeistRepairCandidateDiagnosis: Codable, Sendable, Equatable {
    public let source: RepairCandidateSource
    public let resolvedElement: HeistRepairElementContext
    public let score: Int
    public let reasons: [RepairScoringReason]
    public let caveats: [RepairCaveat]
    public let validation: RepairCandidateValidation

    public init(
        source: RepairCandidateSource,
        resolvedElement: HeistRepairElementContext,
        score: Int,
        reasons: [RepairScoringReason],
        caveats: [RepairCaveat] = [],
        validation: RepairCandidateValidation
    ) {
        self.source = source
        self.resolvedElement = resolvedElement
        self.score = score
        self.reasons = reasons.uniqued(on: \.self)
        self.caveats = caveats.uniqued(on: \.self)
        self.validation = validation
    }
}

public enum HeistRepairDiagnosis: Codable, Sendable, Equatable {
    case suggested(HeistRepairSuggestedDiagnosis)
    case refused(HeistRepairRefusedDiagnosis)
}

public struct HeistRepairSuggestedDiagnosis: Codable, Sendable, Equatable {
    public let stepPath: String
    public let failureKind: HeistRepairFailureKind
    public let oldTarget: AccessibilityTarget
    public let oldResolvedElement: HeistRepairElementContext
    public let currentMatchCount: Int
    public let candidates: [HeistRepairCandidateDiagnosis]
    public let suggestions: [HeistRepairSuggestion]

    public init(
        stepPath: String,
        failureKind: HeistRepairFailureKind,
        oldTarget: AccessibilityTarget,
        oldResolvedElement: HeistRepairElementContext,
        currentMatchCount: Int,
        candidates: [HeistRepairCandidateDiagnosis],
        suggestions: [HeistRepairSuggestion]
    ) {
        self.stepPath = stepPath
        self.failureKind = failureKind
        self.oldTarget = oldTarget
        self.oldResolvedElement = oldResolvedElement
        self.currentMatchCount = currentMatchCount
        self.candidates = candidates
        self.suggestions = suggestions
    }
}

public enum HeistRepairRefusalContext: Codable, Sendable, Equatable {
    case evidenceEligibility
    case eligible(HeistRepairEligibleRefusalContext)
}

public struct HeistRepairEligibleRefusalContext: Codable, Sendable, Equatable {
    public let failureKind: HeistRepairFailureKind
    public let oldResolvedElement: HeistRepairElementContext
    public let currentMatchCount: Int
    public let candidates: [HeistRepairCandidateDiagnosis]

    public init(
        failureKind: HeistRepairFailureKind,
        oldResolvedElement: HeistRepairElementContext,
        currentMatchCount: Int,
        candidates: [HeistRepairCandidateDiagnosis]
    ) {
        self.failureKind = failureKind
        self.oldResolvedElement = oldResolvedElement
        self.currentMatchCount = currentMatchCount
        self.candidates = candidates
    }
}

public struct HeistRepairRefusedDiagnosis: Codable, Sendable, Equatable {
    public let stepPath: String
    public let oldTarget: AccessibilityTarget
    public let context: HeistRepairRefusalContext
    public let refusal: HeistRepairRefusal

    public init(
        stepPath: String,
        oldTarget: AccessibilityTarget,
        context: HeistRepairRefusalContext,
        refusal: HeistRepairRefusal
    ) {
        self.stepPath = stepPath
        self.oldTarget = oldTarget
        self.context = context
        self.refusal = refusal
    }
}

public struct HeistRepairSuggestion: Codable, Sendable, Equatable {
    public let stepPath: String
    public let failureKind: HeistRepairFailureKind
    public let oldTarget: AccessibilityTarget
    public let oldResolvedElement: HeistRepairElementContext
    public let newTarget: AccessibilityTarget
    public let newResolvedElement: HeistRepairElementContext
    public let confidence: RepairConfidence
    public let reasons: [RepairSuggestionReason]
    public let caveats: [RepairCaveat]

    public init(
        stepPath: String,
        failureKind: HeistRepairFailureKind,
        oldTarget: AccessibilityTarget,
        oldResolvedElement: HeistRepairElementContext,
        newTarget: AccessibilityTarget,
        newResolvedElement: HeistRepairElementContext,
        confidence: RepairConfidence,
        reasons: [RepairSuggestionReason],
        caveats: [RepairCaveat] = []
    ) {
        self.stepPath = stepPath
        self.failureKind = failureKind
        self.oldTarget = oldTarget
        self.oldResolvedElement = oldResolvedElement
        self.newTarget = newTarget
        self.newResolvedElement = newResolvedElement
        self.confidence = confidence
        self.reasons = reasons.uniqued(on: \.self)
        self.caveats = caveats.uniqued(on: \.self)
    }

}
