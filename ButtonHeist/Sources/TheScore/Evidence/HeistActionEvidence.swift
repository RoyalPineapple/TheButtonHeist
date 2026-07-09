import Foundation
import ThePlans

public struct HeistActionEvidence: Codable, Sendable, Equatable {
    private let storage: Storage

    public struct DispatchResultEvidence: Sendable, Equatable {
        public let dispatchResult: ActionResult
    }

    public struct ExpectationResultEvidence: Sendable, Equatable {
        public let dispatchResult: ActionResult
        public let expectationResult: ActionResult
        public let expectation: ExpectationResult
    }

    public enum ResultEvidence: Sendable, Equatable {
        case commandResolutionFailure
        case dispatch(DispatchResultEvidence)
        case expectation(ExpectationResultEvidence)
    }

    public var resultEvidence: ResultEvidence {
        switch storage {
        case .commandResolutionFailure:
            return .commandResolutionFailure
        case .dispatch(let dispatch):
            return .dispatch(DispatchResultEvidence(dispatchResult: dispatch.dispatchResult))
        case .expectation(_, let dispatchResult, let expectationResult, let expectation, _):
            return .expectation(ExpectationResultEvidence(
                dispatchResult: dispatchResult,
                expectationResult: expectationResult,
                expectation: expectation
            ))
        }
    }

    public var dispatchResult: ActionResult? {
        switch resultEvidence {
        case .commandResolutionFailure:
            return nil
        case .dispatch(let evidence):
            return evidence.dispatchResult
        case .expectation(let evidence):
            return evidence.dispatchResult
        }
    }

    public var reportedResult: ActionResult? {
        switch resultEvidence {
        case .commandResolutionFailure:
            return nil
        case .dispatch(let evidence):
            return evidence.dispatchResult
        case .expectation(let evidence):
            return evidence.expectationResult
        }
    }

    public var traceResult: ActionResult? {
        reportedResult
    }

    public var expectationResult: ActionResult? {
        guard case .expectation(let evidence) = resultEvidence else { return nil }
        return evidence.expectationResult
    }

    public var command: HeistActionCommand? {
        switch storage {
        case .commandResolutionFailure(let command):
            return command
        case .dispatch(let dispatch):
            return dispatch.command
        case .expectation(let command, _, _, _, _):
            return command
        }
    }

    public var expectation: ExpectationResult? {
        guard case .expectation(let evidence) = resultEvidence else { return nil }
        return evidence.expectation
    }

    public var warning: HeistActionWarning? {
        switch storage {
        case .commandResolutionFailure:
            return nil
        case .dispatch(let dispatch):
            return dispatch.warning
        case .expectation(_, _, _, _, let warning):
            return warning
        }
    }

    public static func commandResolutionFailure(
        command: HeistActionCommand
    ) -> HeistActionEvidence {
        HeistActionEvidence(storage: .commandResolutionFailure(command: command))
    }

    public static func dispatch(
        command: HeistActionCommand,
        dispatchResult: ActionResult,
        warning: HeistActionWarning? = nil
    ) -> HeistActionEvidence {
        return HeistActionEvidence(storage: .dispatch(.command(
            command: command,
            dispatchResult: dispatchResult,
            warning: warning
        )))
    }

    public static func dispatch(
        dispatchResult: ActionResult
    ) -> HeistActionEvidence {
        HeistActionEvidence(storage: .dispatch(.commandless(dispatchResult: dispatchResult)))
    }

    public static func expectation(
        command: HeistActionCommand,
        dispatchResult: ActionResult,
        expectationResult: ActionResult,
        expectation: ExpectationResult,
        warning: HeistActionWarning? = nil
    ) -> HeistActionEvidence {
        HeistActionEvidence(storage: .expectation(
            command: command,
            dispatchResult: dispatchResult,
            expectationResult: expectationResult,
            expectation: expectation,
            warning: warning
        ))
    }

    private init(storage: Storage) {
        self.storage = storage
    }

    private enum Storage: Sendable, Equatable {
        case commandResolutionFailure(command: HeistActionCommand)
        case dispatch(Dispatch)
        case expectation(
            command: HeistActionCommand,
            dispatchResult: ActionResult,
            expectationResult: ActionResult,
            expectation: ExpectationResult,
            warning: HeistActionWarning?
        )
    }

    private enum Dispatch: Sendable, Equatable {
        case command(command: HeistActionCommand, dispatchResult: ActionResult, warning: HeistActionWarning?)
        case commandless(dispatchResult: ActionResult)

        var command: HeistActionCommand? {
            switch self {
            case .command(let command, _, _):
                return command
            case .commandless:
                return nil
            }
        }

        var dispatchResult: ActionResult {
            switch self {
            case .command(_, let dispatchResult, _),
                 .commandless(let dispatchResult):
                return dispatchResult
            }
        }

        var warning: HeistActionWarning? {
            switch self {
            case .command(_, _, let warning):
                return warning
            case .commandless:
                return nil
            }
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type
        case command
        case dispatchResult
        case expectationResult
        case expectation
        case warning
    }

    private enum EvidenceType: String, Codable {
        case commandResolutionFailure = "command_resolution_failure"
        case dispatch
        case commandlessDispatch = "commandless_dispatch"
        case expectation
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist action evidence")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(EvidenceType.self, forKey: .type) {
        case .commandResolutionFailure:
            self = .commandResolutionFailure(
                command: try container.decode(HeistActionCommand.self, forKey: .command)
            )
            try Self.rejectFields(
                except: [.type, .command],
                in: container,
                typeName: EvidenceType.commandResolutionFailure.rawValue
            )
        case .dispatch:
            self = .dispatch(
                command: try container.decode(HeistActionCommand.self, forKey: .command),
                dispatchResult: try container.decode(ActionResult.self, forKey: .dispatchResult),
                warning: try container.decodeIfPresent(HeistActionWarning.self, forKey: .warning)
            )
            try Self.rejectFields(
                except: [.type, .command, .dispatchResult, .warning],
                in: container,
                typeName: EvidenceType.dispatch.rawValue
            )
        case .commandlessDispatch:
            self = .dispatch(
                dispatchResult: try container.decode(ActionResult.self, forKey: .dispatchResult)
            )
            try Self.rejectFields(
                except: [.type, .dispatchResult],
                in: container,
                typeName: EvidenceType.commandlessDispatch.rawValue
            )
        case .expectation:
            self = .expectation(
                command: try container.decode(HeistActionCommand.self, forKey: .command),
                dispatchResult: try container.decode(ActionResult.self, forKey: .dispatchResult),
                expectationResult: try container.decode(ActionResult.self, forKey: .expectationResult),
                expectation: try container.decode(ExpectationResult.self, forKey: .expectation),
                warning: try container.decodeIfPresent(HeistActionWarning.self, forKey: .warning)
            )
            try Self.rejectFields(
                except: [.type, .command, .dispatchResult, .expectationResult, .expectation, .warning],
                in: container,
                typeName: EvidenceType.expectation.rawValue
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch storage {
        case .commandResolutionFailure(let command):
            try container.encode(EvidenceType.commandResolutionFailure, forKey: .type)
            try container.encode(command, forKey: .command)
        case .dispatch(.command(let command, let dispatchResult, let warning)):
            try container.encode(EvidenceType.dispatch, forKey: .type)
            try container.encode(command, forKey: .command)
            try container.encode(dispatchResult, forKey: .dispatchResult)
            try container.encodeIfPresent(warning, forKey: .warning)
        case .dispatch(.commandless(let dispatchResult)):
            try container.encode(EvidenceType.commandlessDispatch, forKey: .type)
            try container.encode(dispatchResult, forKey: .dispatchResult)
        case .expectation(let command, let dispatchResult, let expectationResult, let expectation, let warning):
            try container.encode(EvidenceType.expectation, forKey: .type)
            try container.encode(command, forKey: .command)
            try container.encode(dispatchResult, forKey: .dispatchResult)
            try container.encode(expectationResult, forKey: .expectationResult)
            try container.encode(expectation, forKey: .expectation)
            try container.encodeIfPresent(warning, forKey: .warning)
        }
    }

    private static func rejectFields(
        except allowed: Set<CodingKeys>,
        in container: KeyedDecodingContainer<CodingKeys>,
        typeName: String
    ) throws {
        for key in CodingKeys.allCases where !allowed.contains(key) && container.contains(key) {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "\(typeName) heist action evidence cannot include \(key.stringValue)"
            )
        }
    }
}

public struct HeistActionWarning: Codable, Sendable, Equatable {
    public static let activationWeakAffordanceEvidenceCode = "activation_weak_affordance_evidence"

    public let code: String
    public let message: String
    public let evidence: String?

    public init(
        code: String,
        message: String,
        evidence: String? = nil
    ) {
        precondition(!code.isEmpty, "HeistActionWarning code must not be empty")
        precondition(!message.isEmpty, "HeistActionWarning message must not be empty")
        self.code = code
        self.message = message
        self.evidence = evidence
    }

    public static func activationWeakAffordanceEvidence(evidence: String?) -> HeistActionWarning {
        HeistActionWarning(
            code: activationWeakAffordanceEvidenceCode,
            message: "activate succeeded, but the target does not advertise a primary activation affordance",
            evidence: evidence
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case code
        case message
        case evidence
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist action warning")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let code = try container.decode(String.self, forKey: .code)
        let message = try container.decode(String.self, forKey: .message)
        guard !code.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .code,
                in: container,
                debugDescription: "heist action warning code must not be empty"
            )
        }
        guard !message.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .message,
                in: container,
                debugDescription: "heist action warning message must not be empty"
            )
        }
        self.init(
            code: code,
            message: message,
            evidence: try container.decodeIfPresent(String.self, forKey: .evidence)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try container.encode(message, forKey: .message)
        try container.encodeIfPresent(evidence, forKey: .evidence)
    }
}
