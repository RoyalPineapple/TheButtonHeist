import Foundation
import ThePlans
import TheScore

// MARK: - Heist Repair Evidence

public struct HeistRepairCustomActionIdentity: RawRepresentable, Codable, Sendable, Equatable, Hashable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct HeistRepairRotorIdentity: RawRepresentable, Codable, Sendable, Equatable, Hashable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct HeistRepairActionIdentity: Codable, Sendable, Equatable {
    public let commandType: HeistActionCommandType
    public let customAction: HeistRepairCustomActionIdentity?

    public init(
        commandType: HeistActionCommandType,
        customAction: HeistRepairCustomActionIdentity? = nil
    ) {
        self.commandType = commandType
        self.customAction = customAction
    }

    public init(command: HeistActionCommand) {
        let customAction: HeistRepairCustomActionIdentity?
        if case .customAction(let name, _) = command {
            customAction = HeistRepairCustomActionIdentity(rawValue: name)
        } else {
            customAction = nil
        }
        self.init(commandType: command.wireType, customAction: customAction)
    }
}

public struct RepairPassEvidence: Codable, Sendable, Equatable {
    public let method: ActionMethod?
    public let expectation: ExpectationResult?

    public init(
        method: ActionMethod? = nil,
        expectation: ExpectationResult? = nil
    ) {
        self.method = method
        self.expectation = expectation
    }
}

public struct RepairFailureEvidence: Codable, Sendable, Equatable {
    public let method: ActionMethod?
    public let errorKind: ErrorKind?
    public let message: String?
    public let expectation: ExpectationResult?

    public init(
        method: ActionMethod? = nil,
        errorKind: ErrorKind? = nil,
        message: String? = nil,
        expectation: ExpectationResult? = nil
    ) {
        self.method = method
        self.errorKind = errorKind
        self.message = message
        self.expectation = expectation
    }
}

public struct HeistPassedStepRepairEvidence: Codable, Sendable, Equatable {
    public let heistFingerprint: String?
    public let stepPath: String
    public let actionIdentity: HeistRepairActionIdentity
    public let target: ElementTarget
    public let beforeSnapshot: Interface
    public let afterDelta: AccessibilityTrace.Delta?
    public let afterSnapshot: Interface?
    public let result: RepairPassEvidence

    public init(
        heistFingerprint: String? = nil,
        stepPath: String,
        actionIdentity: HeistRepairActionIdentity,
        target: ElementTarget,
        beforeSnapshot: Interface,
        afterDelta: AccessibilityTrace.Delta? = nil,
        afterSnapshot: Interface? = nil,
        result: RepairPassEvidence
    ) {
        self.heistFingerprint = heistFingerprint
        self.stepPath = stepPath
        self.actionIdentity = actionIdentity
        self.target = target
        self.beforeSnapshot = beforeSnapshot
        self.afterDelta = afterDelta
        self.afterSnapshot = afterSnapshot
        self.result = result
    }
}

public struct HeistFailedStepRepairEvidence: Codable, Sendable, Equatable {
    public let heistFingerprint: String?
    public let stepPath: String
    public let actionIdentity: HeistRepairActionIdentity
    public let target: ElementTarget
    public let beforeSnapshot: Interface
    public let afterDelta: AccessibilityTrace.Delta?
    public let afterSnapshot: Interface?
    public let result: RepairFailureEvidence

    public init(
        heistFingerprint: String? = nil,
        stepPath: String,
        actionIdentity: HeistRepairActionIdentity,
        target: ElementTarget,
        beforeSnapshot: Interface,
        afterDelta: AccessibilityTrace.Delta? = nil,
        afterSnapshot: Interface? = nil,
        result: RepairFailureEvidence
    ) {
        self.heistFingerprint = heistFingerprint
        self.stepPath = stepPath
        self.actionIdentity = actionIdentity
        self.target = target
        self.beforeSnapshot = beforeSnapshot
        self.afterDelta = afterDelta
        self.afterSnapshot = afterSnapshot
        self.result = result
    }
}

public struct HeistRepairRequest: Codable, Sendable, Equatable {
    public let lastSuccess: HeistPassedStepRepairEvidence
    public let currentFailure: HeistFailedStepRepairEvidence

    public init(
        lastSuccess: HeistPassedStepRepairEvidence,
        currentFailure: HeistFailedStepRepairEvidence
    ) {
        self.lastSuccess = lastSuccess
        self.currentFailure = currentFailure
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

public struct ElementSummary: Codable, Sendable, Equatable {
    public let description: String
    public let label: String?
    public let value: String?
    public let identifier: String?
    public let hint: String?
    public let traits: [HeistTrait]
    public let actions: [ElementAction]
    public let rotors: [HeistRepairRotorIdentity]
    public let siblingText: [String]
    public let headerText: [String]

    public init(
        description: String,
        label: String?,
        value: String?,
        identifier: String?,
        hint: String?,
        traits: [HeistTrait],
        actions: [ElementAction],
        rotors: [HeistRepairRotorIdentity],
        siblingText: [String] = [],
        headerText: [String] = []
    ) {
        self.description = description
        self.label = label
        self.value = value
        self.identifier = identifier
        self.hint = hint
        self.traits = traits
        self.actions = actions
        self.rotors = rotors
        self.siblingText = siblingText
        self.headerText = headerText
    }
}

public enum RepairCandidateValidation: Codable, Sendable, Equatable {
    case notEvaluated
    case suggested(target: ElementTarget, confidence: RepairConfidence)
    case rejected(reason: RepairCandidateRejectionReason)
}

public struct HeistRepairCandidateDiagnosis: Codable, Sendable, Equatable {
    public let source: RepairCandidateSource
    public let resolvedElement: ElementSummary
    public let score: Int
    public let reasons: [RepairScoringReason]
    public let caveats: [RepairCaveat]
    public let validation: RepairCandidateValidation

    public init(
        source: RepairCandidateSource,
        resolvedElement: ElementSummary,
        score: Int,
        reasons: [RepairScoringReason],
        caveats: [RepairCaveat] = [],
        validation: RepairCandidateValidation
    ) {
        self.source = source
        self.resolvedElement = resolvedElement
        self.score = score
        self.reasons = unique(reasons)
        self.caveats = unique(caveats)
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
    public let oldTarget: ElementTarget
    public let oldResolvedElement: ElementSummary
    public let currentMatchCount: Int
    public let candidates: [HeistRepairCandidateDiagnosis]
    public let suggestions: [HeistRepairSuggestion]

    public init(
        stepPath: String,
        failureKind: HeistRepairFailureKind,
        oldTarget: ElementTarget,
        oldResolvedElement: ElementSummary,
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
    public let oldResolvedElement: ElementSummary
    public let currentMatchCount: Int
    public let candidates: [HeistRepairCandidateDiagnosis]

    public init(
        failureKind: HeistRepairFailureKind,
        oldResolvedElement: ElementSummary,
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
    public let oldTarget: ElementTarget
    public let context: HeistRepairRefusalContext
    public let refusal: HeistRepairRefusal

    public init(
        stepPath: String,
        oldTarget: ElementTarget,
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
    public let oldTarget: ElementTarget
    public let oldResolvedElement: ElementSummary
    public let newTarget: ElementTarget
    public let newResolvedElement: ElementSummary
    public let confidence: RepairConfidence
    public let reasons: [RepairSuggestionReason]
    public let caveats: [RepairCaveat]

    public init(
        stepPath: String,
        failureKind: HeistRepairFailureKind,
        oldTarget: ElementTarget,
        oldResolvedElement: ElementSummary,
        newTarget: ElementTarget,
        newResolvedElement: ElementSummary,
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
        self.reasons = unique(reasons)
        self.caveats = unique(caveats)
    }

}
