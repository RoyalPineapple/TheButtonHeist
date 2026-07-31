import Foundation
import ThePlans

public enum HeistActionEvidence: Codable, Sendable, Equatable {
    case commandResolutionFailure
    case completed(result: ActionResult, expectation: HeistExpectationEvidence?)

    public var result: ActionResult? {
        guard case .completed(let result, _) = self else { return nil }
        return result
    }

    package func replayExpectation() throws(Observation.Gap) -> ExpectationResult? {
        guard let expectationEvidence else { return nil }
        return try expectationEvidence.replay()
    }

    package var expectationEvidence: HeistExpectationEvidence? {
        guard case .completed(_, let expectation) = self else { return nil }
        return expectation
    }

    public var warning: HeistActionWarning? {
        result?.warning
    }

    public var announcement: String? {
        get throws(Observation.Gap) {
            try replayExpectation()?.matchedAnnouncement ?? result?.announcement
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type
        case result
        case expectationEvidence
    }

    private enum EvidenceType: String, Codable {
        case commandResolutionFailure = "command_resolution_failure"
        case completed
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist action evidence")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(EvidenceType.self, forKey: .type)
        let typeName = "\(type.rawValue) heist action evidence"
        switch type {
        case .commandResolutionFailure:
            self = .commandResolutionFailure
            try container.rejectIncompatibleFields(allowing: [.type], typeName: typeName)
        case .completed:
            self = .completed(
                result: try container.decode(ActionResult.self, forKey: .result),
                expectation: try container.decodeIfPresent(
                    HeistExpectationEvidence.self,
                    forKey: .expectationEvidence
                )
            )
            try container.rejectIncompatibleFields(
                allowing: [.type, .result, .expectationEvidence],
                typeName: typeName
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .commandResolutionFailure:
            try container.encode(EvidenceType.commandResolutionFailure, forKey: .type)
        case .completed(let result, let expectation):
            try container.encode(EvidenceType.completed, forKey: .type)
            try container.encode(result, forKey: .result)
            try container.encodeIfPresent(expectation, forKey: .expectationEvidence)
        }
    }
}

extension HeistActionEvidence {
    func matches(command: HeistActionCommand) -> Bool {
        switch self {
        case .commandResolutionFailure:
            return true
        case .completed(let result, _):
            return command.wireType.actionResultMethod == result.method
        }
    }
}

package extension HeistActionCommandType {
    /// Projects the canonical action identity onto the public result method.
    var actionResultMethod: ActionMethod {
        if self == .performCustomAction { return .customAction }
        guard let method = ActionMethod(rawValue: rawValue) else {
            preconditionFailure("Every heist action command type projects to an ActionResult method")
        }
        return method
    }
}

package extension ActionResult.Payload {
    /// Empty returned-data payload for an action command before dispatch returns data.
    static func empty(for type: HeistActionCommandType) -> Self {
        switch type {
        case .activate: .activate
        case .increment: .increment
        case .decrement: .decrement
        case .performCustomAction: .customAction
        case .rotor: .rotor(nil)
        case .dismiss: .dismiss
        case .magicTap: .magicTap
        case .oneFingerTap: .oneFingerTap
        case .longPress: .longPress
        case .swipe: .swipe
        case .drag: .drag
        case .typeText: .typeText(nil)
        case .editAction: .editAction
        case .setPasteboard: .setPasteboard(nil)
        case .takeScreenshot: .screenshot(nil)
        case .scroll: .scroll
        case .scrollToVisible: .scrollToVisible
        case .scrollToEdge: .scrollToEdge
        case .dismissKeyboard: .dismissKeyboard
        }
    }
}

package extension HeistActionCommand {
    var actionResultPayload: ActionResult.Payload {
        .empty(for: wireType)
    }
}

public enum HeistActionWarning: Codable, Sendable, Equatable {
    case activationWeakAffordance(evidence: String?)
    case textEntryWeakAffordance(evidence: String?)

    private enum Code: String, Codable {
        case activationWeakAffordance = "activation_weak_affordance_evidence"
        case textEntryWeakAffordance = "text_entry_weak_affordance_evidence"
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case code
        case evidence
    }

    public var code: String {
        switch self {
        case .activationWeakAffordance:
            return Code.activationWeakAffordance.rawValue
        case .textEntryWeakAffordance:
            return Code.textEntryWeakAffordance.rawValue
        }
    }

    public var message: String {
        switch self {
        case .activationWeakAffordance:
            return "target advertised no interactivity and implements no activation; "
                + "activate proceeded as VoiceOver would"
        case .textEntryWeakAffordance:
            return "typeText succeeded, but the target does not advertise a text-input trait"
        }
    }

    public var evidence: String? {
        switch self {
        case .activationWeakAffordance(let evidence), .textEntryWeakAffordance(let evidence):
            return evidence
        }
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist action warning")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let evidence = try container.decodeIfPresent(String.self, forKey: .evidence)
        switch try container.decode(Code.self, forKey: .code) {
        case .activationWeakAffordance:
            self = .activationWeakAffordance(evidence: evidence)
        case .textEntryWeakAffordance:
            self = .textEntryWeakAffordance(evidence: evidence)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .activationWeakAffordance:
            try container.encode(Code.activationWeakAffordance, forKey: .code)
        case .textEntryWeakAffordance:
            try container.encode(Code.textEntryWeakAffordance, forKey: .code)
        }
        try container.encodeIfPresent(evidence, forKey: .evidence)
    }
}
