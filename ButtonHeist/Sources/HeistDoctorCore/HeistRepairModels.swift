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

public struct HeistStepRepairEvidence: Codable, Sendable, Equatable {
    public let heistFingerprint: String?
    public let stepPath: String
    public let actionIdentity: HeistRepairActionIdentity
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
        actionIdentity: HeistRepairActionIdentity,
        target: ElementTarget,
        beforeSnapshot: Interface,
        afterDelta: AccessibilityTrace.Delta? = nil,
        afterSnapshot: Interface? = nil,
        result: HeistStepRepairResult
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

public enum HeistStepRepairResult: Codable, Sendable, Equatable {
    case passed(RepairPassEvidence)
    case failed(RepairFailureEvidence)

    public init(actionResult: ActionResult, expectation: ExpectationResult? = nil) {
        if actionResult.success {
            self = .passed(RepairPassEvidence(
                method: actionResult.method,
                expectation: expectation
            ))
        } else {
            self = .failed(RepairFailureEvidence(
                method: actionResult.method,
                errorKind: actionResult.errorKind,
                message: actionResult.message,
                expectation: expectation
            ))
        }
    }

    public var expectation: ExpectationResult? {
        switch self {
        case .passed(let evidence):
            return evidence.expectation
        case .failed(let evidence):
            return evidence.expectation
        }
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

    private enum CodingKeys: String, CodingKey {
        case stepPath
        case failureKind
        case oldTarget
        case oldResolvedElement
        case newTarget
        case newResolvedElement
        case confidence
        case reasons
        case caveats
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stepPath = try container.decode(String.self, forKey: .stepPath)
        failureKind = try container.decode(HeistRepairFailureKind.self, forKey: .failureKind)
        oldTarget = try container.decode(ElementTarget.self, forKey: .oldTarget)
        oldResolvedElement = try container.decode(ElementSummary.self, forKey: .oldResolvedElement)
        newTarget = try container.decode(ElementTarget.self, forKey: .newTarget)
        newResolvedElement = try container.decode(ElementSummary.self, forKey: .newResolvedElement)
        confidence = try container.decode(RepairConfidence.self, forKey: .confidence)
        reasons = try container.decodeRenderedReasons(forKey: .reasons)
        caveats = try container.decodeRenderedCaveats(forKey: .caveats)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(stepPath, forKey: .stepPath)
        try container.encode(failureKind, forKey: .failureKind)
        try container.encode(oldTarget, forKey: .oldTarget)
        try container.encode(oldResolvedElement, forKey: .oldResolvedElement)
        try container.encode(newTarget, forKey: .newTarget)
        try container.encode(newResolvedElement, forKey: .newResolvedElement)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(reasons.map(\.prose), forKey: .reasons)
        try container.encode(caveats.map(\.prose), forKey: .caveats)
    }
}

private extension KeyedDecodingContainer {
    func decodeRenderedReasons(forKey key: Key) throws -> [RepairSuggestionReason] {
        try decode([String].self, forKey: key).map { prose in
            guard let reason = RepairSuggestionReason(prose: prose) else {
                throw DecodingError.dataCorruptedError(
                    forKey: key,
                    in: self,
                    debugDescription: "Unknown heist repair reason: \(prose)"
                )
            }
            return reason
        }
    }

    func decodeRenderedCaveats(forKey key: Key) throws -> [RepairCaveat] {
        try decode([String].self, forKey: key).map { prose in
            guard let caveat = RepairCaveat(prose: prose) else {
                throw DecodingError.dataCorruptedError(
                    forKey: key,
                    in: self,
                    debugDescription: "Unknown heist repair caveat: \(prose)"
                )
            }
            return caveat
        }
    }
}
