import Foundation
import ThePlans

private enum InvocationExpectationEvidenceKind: String, Codable {
    case result
    case wait
}

private enum InvocationExpectationEvidenceCodingKey: String, CodingKey, CaseIterable {
    case type
    case actionResult
    case expectation
    case waitEvidence
}

private enum InvocationOutcomeKind: String, Codable {
    case completed
    case childFailed = "child_failed"
}

private enum InvocationOutcomeCodingKey: String, CodingKey, CaseIterable {
    case type
    case expectation
    case path
}

public enum HeistInvocationEvidence: Codable, Sendable, Equatable {
    public enum InvocationExpectationEvidence: Codable, Sendable, Equatable {
        case result(actionResult: ActionResult, expectation: ExpectationResult)
        case wait(HeistWaitEvidence)

        public var actionResult: ActionResult {
            switch self {
            case .result(let actionResult, _): actionResult
            case .wait(let evidence): evidence.actionResult
            }
        }

        public var expectation: ExpectationResult {
            switch self {
            case .result(_, let expectation): expectation
            case .wait(let evidence): evidence.expectation
            }
        }

        public var waitEvidence: HeistWaitEvidence? {
            guard case .wait(let evidence) = self else { return nil }
            return evidence
        }

        public init(from decoder: Decoder) throws {
            try decoder.rejectUnknownKeys(
                allowed: InvocationExpectationEvidenceCodingKey.self,
                typeName: "invocation expectation evidence"
            )
            let container = try decoder.container(keyedBy: InvocationExpectationEvidenceCodingKey.self)
            switch try container.decode(InvocationExpectationEvidenceKind.self, forKey: .type) {
            case .result:
                self = .result(
                    actionResult: try container.decode(ActionResult.self, forKey: .actionResult),
                    expectation: try container.decode(ExpectationResult.self, forKey: .expectation)
                )
                try container.rejectIncompatibleFields(
                    allowing: [.type, .actionResult, .expectation],
                    typeName: "result invocation expectation evidence"
                )
            case .wait:
                self = .wait(try container.decode(HeistWaitEvidence.self, forKey: .waitEvidence))
                try container.rejectIncompatibleFields(
                    allowing: [.type, .waitEvidence],
                    typeName: "wait invocation expectation evidence"
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: InvocationExpectationEvidenceCodingKey.self)
            switch self {
            case .result(let actionResult, let expectation):
                try container.encode(InvocationExpectationEvidenceKind.result, forKey: .type)
                try container.encode(actionResult, forKey: .actionResult)
                try container.encode(expectation, forKey: .expectation)
            case .wait(let evidence):
                try container.encode(InvocationExpectationEvidenceKind.wait, forKey: .type)
                try container.encode(evidence, forKey: .waitEvidence)
            }
        }

    }

    public enum InvocationOutcome: Codable, Sendable, Equatable {
        case completed(expectation: InvocationExpectationEvidence?)
        case childFailed(path: String)

        public init(from decoder: Decoder) throws {
            try decoder.rejectUnknownKeys(allowed: InvocationOutcomeCodingKey.self, typeName: "invocation outcome")
            let container = try decoder.container(keyedBy: InvocationOutcomeCodingKey.self)
            switch try container.decode(InvocationOutcomeKind.self, forKey: .type) {
            case .completed:
                self = .completed(
                    expectation: try container.decodeIfPresent(InvocationExpectationEvidence.self, forKey: .expectation)
                )
                try container.rejectIncompatibleFields(
                    allowing: [.type, .expectation],
                    typeName: "completed invocation outcome"
                )
            case .childFailed:
                self = .childFailed(path: try container.decode(String.self, forKey: .path))
                try container.rejectIncompatibleFields(
                    allowing: [.type, .path],
                    typeName: "child_failed invocation outcome"
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: InvocationOutcomeCodingKey.self)
            switch self {
            case .completed(let expectation):
                try container.encode(InvocationOutcomeKind.completed, forKey: .type)
                try container.encodeIfPresent(expectation, forKey: .expectation)
            case .childFailed(let path):
                try container.encode(InvocationOutcomeKind.childFailed, forKey: .type)
                try container.encode(path, forKey: .path)
            }
        }

    }

    case heist(name: String?, childFailedPath: String?)
    case invocation(
        invocation: HeistInvocationStep,
        name: String?,
        argument: String?,
        outcome: InvocationOutcome
    )

    private enum Kind: String, Codable {
        case heist
        case invocation
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type
        case invocation
        case name
        case argument
        case childFailedPath
        case outcome
    }

    public var invocation: HeistInvocationStep? {
        guard case .invocation(let invocation, _, _, _) = self else { return nil }
        return invocation
    }

    public var name: String? {
        switch self {
        case .heist(let name, _), .invocation(_, let name, _, _): name
        }
    }

    public var argument: String? {
        guard case .invocation(_, _, let argument, _) = self else { return nil }
        return argument
    }

    public var childFailedPath: String? {
        switch self {
        case .heist(_, let path):
            return path
        case .invocation(_, _, _, .childFailed(let path)):
            return path
        case .invocation:
            return nil
        }
    }

    private var expectationEvidence: InvocationExpectationEvidence? {
        guard case .invocation(_, _, _, .completed(let expectation)) = self else { return nil }
        return expectation
    }

    public var expectationActionResult: ActionResult? { expectationEvidence?.actionResult }
    public var expectation: ExpectationResult? { expectationEvidence?.expectation }
    public var waitEvidence: HeistWaitEvidence? { expectationEvidence?.waitEvidence }

    var provesInvocationFailure: Bool {
        switch self {
        case .heist(_, let childFailedPath):
            return childFailedPath != nil
        case .invocation(_, _, _, .childFailed):
            return true
        case .invocation(_, _, _, .completed(let expectation)):
            guard let expectation else { return false }
            return !expectation.actionResult.outcome.isSuccess || !expectation.expectation.met
        }
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist invocation evidence")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .heist:
            self = .heist(
                name: try container.decodeIfPresent(String.self, forKey: .name),
                childFailedPath: try container.decodeIfPresent(String.self, forKey: .childFailedPath)
            )
            try container.rejectIncompatibleFields(
                allowing: [.type, .name, .childFailedPath],
                typeName: "heist invocation evidence"
            )
        case .invocation:
            self = .invocation(
                invocation: try container.decode(HeistInvocationStep.self, forKey: .invocation),
                name: try container.decodeIfPresent(String.self, forKey: .name),
                argument: try container.decodeIfPresent(String.self, forKey: .argument),
                outcome: try container.decode(InvocationOutcome.self, forKey: .outcome)
            )
            try container.rejectIncompatibleFields(
                allowing: [.type, .invocation, .name, .argument, .outcome],
                typeName: "invocation evidence"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .heist(let name, let childFailedPath):
            try container.encode(Kind.heist, forKey: .type)
            try container.encodeIfPresent(name, forKey: .name)
            try container.encodeIfPresent(childFailedPath, forKey: .childFailedPath)
        case .invocation(let invocation, let name, let argument, let outcome):
            try container.encode(Kind.invocation, forKey: .type)
            try container.encode(invocation, forKey: .invocation)
            try container.encodeIfPresent(name, forKey: .name)
            try container.encodeIfPresent(argument, forKey: .argument)
            try container.encode(outcome, forKey: .outcome)
        }
    }

}
