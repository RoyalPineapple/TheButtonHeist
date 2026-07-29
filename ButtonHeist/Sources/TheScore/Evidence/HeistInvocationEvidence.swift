import Foundation
import ThePlans

private enum InvocationExpectationEvidenceKind: String, Codable {
    case result
    case waitPassed = "wait_passed"
    case waitUnmatched = "wait_unmatched"
}

private enum InvocationExpectationEvidenceCodingKey: String, CodingKey, CaseIterable {
    case type
    case actionResult
    case expectation
    case passedWaitEvidence
    case unmatchedWaitEvidence
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
        case waitPassed(HeistPassedWaitEvidence)
        case waitUnmatched(HeistWaitUnmatchedEvidence)

        public var actionResult: ActionResult? {
            guard case .result(let actionResult, _) = self else { return nil }
            return actionResult
        }

        public var expectation: ExpectationResult {
            switch self {
            case .result(_, let expectation): expectation
            case .waitPassed(let evidence): evidence.expectation
            case .waitUnmatched(let evidence): evidence.expectation.result
            }
        }

        public var waitObservation: Observation.Evidence? {
            switch self {
            case .result:
                nil
            case .waitPassed(let evidence):
                evidence.observation
            case .waitUnmatched(let evidence):
                evidence.observation
            }
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
            case .waitPassed:
                self = .waitPassed(
                    try container.decode(
                        HeistPassedWaitEvidence.self,
                        forKey: .passedWaitEvidence
                    )
                )
                try container.rejectIncompatibleFields(
                    allowing: [.type, .passedWaitEvidence],
                    typeName: "passed wait invocation expectation evidence"
                )
            case .waitUnmatched:
                self = .waitUnmatched(
                    try container.decode(
                        HeistWaitUnmatchedEvidence.self,
                        forKey: .unmatchedWaitEvidence
                    )
                )
                try container.rejectIncompatibleFields(
                    allowing: [.type, .unmatchedWaitEvidence],
                    typeName: "unmatched wait invocation expectation evidence"
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
            case .waitPassed(let evidence):
                try container.encode(InvocationExpectationEvidenceKind.waitPassed, forKey: .type)
                try container.encode(evidence, forKey: .passedWaitEvidence)
            case .waitUnmatched(let evidence):
                try container.encode(InvocationExpectationEvidenceKind.waitUnmatched, forKey: .type)
                try container.encode(evidence, forKey: .unmatchedWaitEvidence)
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
    public var waitObservation: Observation.Evidence? { expectationEvidence?.waitObservation }
    public var passedWaitEvidence: HeistPassedWaitEvidence? {
        guard let expectationEvidence,
              case .waitPassed(let evidence) = expectationEvidence else {
            return nil
        }
        return evidence
    }
    public var unmatchedWaitEvidence: HeistWaitUnmatchedEvidence? {
        guard let expectationEvidence,
              case .waitUnmatched(let evidence) = expectationEvidence else {
            return nil
        }
        return evidence
    }

    var provesInvocationFailure: Bool {
        switch self {
        case .childFailed:
            return true
        case .completed(let expectation):
            guard let expectation else { return false }
            return expectation.actionResult?.outcome.isSuccess == false
                || !expectation.expectation.met
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
