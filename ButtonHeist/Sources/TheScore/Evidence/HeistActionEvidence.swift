import Foundation
import ThePlans

public enum HeistActionEvidence: Codable, Sendable, Equatable {
    case commandResolutionFailure
    case dispatch(dispatchResult: ActionResult)
    case expectation(
        dispatchResult: ActionResult,
        expectationResult: ActionResult,
        expectation: ExpectationResult
    )

    public var dispatchResult: ActionResult? {
        switch self {
        case .commandResolutionFailure:
            return nil
        case .dispatch(let result),
             .expectation(let result, _, _):
            return result
        }
    }

    public var reportedResult: ActionResult? {
        switch self {
        case .commandResolutionFailure:
            return nil
        case .dispatch(let result):
            return result
        case .expectation(_, let result, _):
            return result
        }
    }

    public var expectationResult: ActionResult? {
        guard case .expectation(_, let result, _) = self else { return nil }
        return result
    }

    public var checkedExpectation: ExpectationResult? {
        guard case .expectation(_, _, let expectation) = self else { return nil }
        return expectation
    }

    public var warning: HeistActionWarning? {
        dispatchResult?.warning
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type
        case dispatchResult
        case expectationResult
        case expectation
    }

    private enum EvidenceType: String, Codable {
        case commandResolutionFailure = "command_resolution_failure"
        case dispatch
        case expectation
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
        case .dispatch:
            self = .dispatch(
                dispatchResult: try container.decode(ActionResult.self, forKey: .dispatchResult)
            )
            try container.rejectIncompatibleFields(
                allowing: [.type, .dispatchResult],
                typeName: typeName
            )
        case .expectation:
            self = .expectation(
                dispatchResult: try container.decode(ActionResult.self, forKey: .dispatchResult),
                expectationResult: try container.decode(ActionResult.self, forKey: .expectationResult),
                expectation: try container.decode(ExpectationResult.self, forKey: .expectation)
            )
            try container.rejectIncompatibleFields(
                allowing: [.type, .dispatchResult, .expectationResult, .expectation],
                typeName: typeName
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .commandResolutionFailure:
            try container.encode(EvidenceType.commandResolutionFailure, forKey: .type)
        case .dispatch(let dispatchResult):
            try container.encode(EvidenceType.dispatch, forKey: .type)
            try container.encode(dispatchResult, forKey: .dispatchResult)
        case .expectation(let dispatchResult, let expectationResult, let expectation):
            try container.encode(EvidenceType.expectation, forKey: .type)
            try container.encode(dispatchResult, forKey: .dispatchResult)
            try container.encode(expectationResult, forKey: .expectationResult)
            try container.encode(expectation, forKey: .expectation)
        }
    }

}

extension HeistActionEvidence {
    func matches(command: HeistActionCommand) -> Bool {
        switch self {
        case .commandResolutionFailure:
            return true
        case .dispatch(let result), .expectation(let result, _, _):
            return command.actionResultMethod == result.method
        }
    }
}

extension HeistActionCommand {
    var actionResultMethod: ActionMethod {
        switch self {
        case .activate: .activate
        case .increment: .increment
        case .decrement: .decrement
        case .customAction: .customAction
        case .rotor: .rotor
        case .dismiss: .dismiss
        case .magicTap: .magicTap
        case .typeText: .typeText
        case .oneFingerTap: .oneFingerTap
        case .longPress: .longPress
        case .swipe: .swipe
        case .drag: .drag
        case .scroll: .scroll
        case .scrollToVisible: .scrollToVisible
        case .scrollToEdge: .scrollToEdge
        case .editAction: .editAction
        case .setPasteboard: .setPasteboard
        case .takeScreenshot: .takeScreenshot
        case .dismissKeyboard: .dismissKeyboard
        }
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
