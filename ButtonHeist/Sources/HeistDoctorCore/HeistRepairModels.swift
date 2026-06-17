import Foundation
import ThePlans
import TheScore

// MARK: - Heist Repair Evidence

public struct HeistStepRepairEvidence: Codable, Sendable, Equatable {
    public let heistFingerprint: String?
    public let stepPath: String
    public let actionKind: String
    public let target: ElementTarget
    /// Parsed Interface hierarchy captured before the action. This is the
    /// durable world-model snapshot repair uses to rerun predicates and recover
    /// local semantic context around the original target; it is not raw AX data.
    public let beforeSnapshot: Interface
    /// Compact parsed-world-model transition evidence captured after the action.
    public let afterDelta: AccessibilityTrace.Delta?
    /// Parsed Interface fallback when a compact transition delta is unavailable.
    public let afterSnapshot: Interface?
    public let result: HeistStepRepairResult

    public init(
        heistFingerprint: String? = nil,
        stepPath: String,
        actionKind: String,
        target: ElementTarget,
        beforeSnapshot: Interface,
        afterDelta: AccessibilityTrace.Delta? = nil,
        afterSnapshot: Interface? = nil,
        result: HeistStepRepairResult
    ) {
        self.heistFingerprint = heistFingerprint
        self.stepPath = stepPath
        self.actionKind = actionKind
        self.target = target
        self.beforeSnapshot = beforeSnapshot
        self.afterDelta = afterDelta
        self.afterSnapshot = afterSnapshot
        self.result = result
    }
}

public struct HeistStepRepairResult: Codable, Sendable, Equatable {
    public let succeeded: Bool
    public let method: ActionMethod?
    public let errorKind: ErrorKind?
    public let message: String?
    public let expectation: ExpectationResult?

    public init(
        succeeded: Bool,
        method: ActionMethod? = nil,
        errorKind: ErrorKind? = nil,
        message: String? = nil,
        expectation: ExpectationResult? = nil
    ) {
        self.succeeded = succeeded
        self.method = method
        self.errorKind = errorKind
        self.message = message
        self.expectation = expectation
    }

    public init(actionResult: ActionResult, expectation: ExpectationResult? = nil) {
        self.init(
            succeeded: actionResult.success,
            method: actionResult.method,
            errorKind: actionResult.errorKind,
            message: actionResult.message,
            expectation: expectation
        )
    }
}

public struct HeistRepairRequest: Codable, Sendable, Equatable {
    public let lastSuccess: HeistStepRepairEvidence
    public let currentFailure: HeistStepRepairEvidence

    public init(
        lastSuccess: HeistStepRepairEvidence,
        currentFailure: HeistStepRepairEvidence
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

public struct ElementSummary: Codable, Sendable, Equatable {
    public let description: String
    public let label: String?
    public let value: String?
    public let identifier: String?
    public let hint: String?
    public let traits: [HeistTrait]
    public let actions: [ElementAction]
    public let rotors: [String]
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
        rotors: [String],
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

public struct HeistRepairSuggestion: Codable, Sendable, Equatable {
    public let stepPath: String
    public let failureKind: HeistRepairFailureKind
    public let oldTarget: ElementTarget
    public let oldResolvedElement: ElementSummary
    public let newTarget: ElementTarget
    public let newResolvedElement: ElementSummary
    public let confidence: RepairConfidence
    public let reasons: [String]
    public let caveats: [String]

    public init(
        stepPath: String,
        failureKind: HeistRepairFailureKind,
        oldTarget: ElementTarget,
        oldResolvedElement: ElementSummary,
        newTarget: ElementTarget,
        newResolvedElement: ElementSummary,
        confidence: RepairConfidence,
        reasons: [String],
        caveats: [String] = []
    ) {
        self.stepPath = stepPath
        self.failureKind = failureKind
        self.oldTarget = oldTarget
        self.oldResolvedElement = oldResolvedElement
        self.newTarget = newTarget
        self.newResolvedElement = newResolvedElement
        self.confidence = confidence
        self.reasons = reasons
        self.caveats = caveats
    }
}
