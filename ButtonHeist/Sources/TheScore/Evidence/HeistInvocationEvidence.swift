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
        case wait(HeistSettlementEvidence)

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

        public var waitEvidence: HeistSettlementEvidence? {
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
                self = .wait(try container.decode(HeistSettlementEvidence.self, forKey: .waitEvidence))
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

    case completed(expectation: InvocationExpectationEvidence?)
    case childFailed(path: HeistExecutionPath)

    public var childFailedPath: HeistExecutionPath? {
        guard case .childFailed(let path) = self else { return nil }
        return path
    }

    private var expectationEvidence: InvocationExpectationEvidence? {
        guard case .completed(let expectation) = self else { return nil }
        return expectation
    }

    public var expectationActionResult: ActionResult? { expectationEvidence?.actionResult }
    public var expectation: ExpectationResult? { expectationEvidence?.expectation }
    public var waitEvidence: HeistSettlementEvidence? { expectationEvidence?.waitEvidence }

    var provesInvocationFailure: Bool {
        switch self {
        case .childFailed:
            return true
        case .completed(let expectation):
            guard let expectation else { return false }
            return !expectation.actionResult.outcome.isSuccess || !expectation.expectation.met
        }
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(
            allowed: InvocationOutcomeCodingKey.self,
            typeName: "heist invocation evidence"
        )
        let container = try decoder.container(keyedBy: InvocationOutcomeCodingKey.self)
        switch try container.decode(InvocationOutcomeKind.self, forKey: .type) {
        case .completed:
            self = .completed(
                expectation: try container.decodeIfPresent(InvocationExpectationEvidence.self, forKey: .expectation)
            )
            try container.rejectIncompatibleFields(
                allowing: [.type, .expectation],
                typeName: "completed invocation evidence"
            )
        case .childFailed:
            self = .childFailed(path: try container.decode(HeistExecutionPath.self, forKey: .path))
            try container.rejectIncompatibleFields(
                allowing: [.type, .path],
                typeName: "child_failed invocation evidence"
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
