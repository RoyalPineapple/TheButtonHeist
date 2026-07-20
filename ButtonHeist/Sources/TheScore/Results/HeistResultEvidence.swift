import Foundation
import ThePlans

package struct HeistPassingChildren: Codable, Sendable, Equatable {
    package static let empty = Self(admitted: [])
    package let values: [HeistExecutionStepResult]

    package init?(_ values: [HeistExecutionStepResult]) {
        guard values.firstFailedStepInResultOrder == nil else { return nil }
        self.init(admitted: values)
    }

    fileprivate init(admitted values: [HeistExecutionStepResult]) { self.values = values }

    package func appending(_ result: HeistExecutionStepResult) -> HeistExecutedChildren {
        let values = values + [result]
        guard let failed = result.firstFailedStepInResultOrder else {
            return .passed(.init(admitted: values))
        }
        return .aborted(.init(admitted: values, abortedAtPath: failed.path))
    }

    package func appending(_ children: HeistPassingChildren) -> HeistPassingChildren {
        .init(admitted: values + children.values)
    }

    package func appending(_ children: HeistAbortedChildren) -> HeistAbortedChildren {
        .init(
            admitted: values + children.values,
            abortedAtPath: children.abortedAtPath
        )
    }

    package func wrappedInRepeatUntilIteration(
        path: HeistExecutionPath,
        durationMs: ElapsedMilliseconds,
        declaration: HeistRepeatUntilDeclaration,
        evidence: HeistPassedRepeatUntilIterationEvidence
    ) -> HeistPassingChildren {
        let result = HeistExecutionStepResult.repeatUntilIteration(
            path: path,
            durationMs: durationMs,
            declaration: declaration,
            completion: .passed(evidence: evidence, children: self)
        )
        return .init(admitted: [result])
    }

    package init(from decoder: Decoder) throws {
        let values = try [HeistExecutionStepResult](from: decoder)
        guard let admitted = Self(values) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "passing result children cannot contain a failed node"
            ))
        }
        self = admitted
    }

    package func encode(to encoder: Encoder) throws { try values.encode(to: encoder) }
}

package struct HeistSkippedChildren: Codable, Sendable, Equatable {
    package static let empty = Self(admitted: [])
    package private(set) var values: [HeistExecutionStepResult]

    package init?(_ values: [HeistExecutionStepResult]) {
        guard values.allSatisfy({ $0.status == .skipped }) else { return nil }
        self.init(admitted: values)
    }

    fileprivate init(admitted values: [HeistExecutionStepResult]) { self.values = values }

    package mutating func append(
        path: HeistExecutionPath,
        durationMs: ElapsedMilliseconds,
        step: HeistStep
    ) {
        values.append(.skipped(path: path, durationMs: durationMs, step: step))
    }

    package init(from decoder: Decoder) throws {
        let values = try [HeistExecutionStepResult](from: decoder)
        guard let admitted = Self(values) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "skipped result children must all be skipped"
            ))
        }
        self = admitted
    }

    package func encode(to encoder: Encoder) throws { try values.encode(to: encoder) }
}

package struct HeistAbortedChildren: Codable, Sendable, Equatable {
    package let values: [HeistExecutionStepResult]
    package let abortedAtPath: HeistExecutionPath

    package init?(_ values: [HeistExecutionStepResult]) {
        guard let failed = values.firstFailedStepInResultOrder else { return nil }
        self.init(admitted: values, abortedAtPath: failed.path)
    }

    fileprivate init(admitted values: [HeistExecutionStepResult], abortedAtPath: HeistExecutionPath) {
        self.values = values
        self.abortedAtPath = abortedAtPath
    }

    package func appending(_ result: HeistExecutionStepResult) -> HeistAbortedChildren {
        .init(admitted: values + [result], abortedAtPath: abortedAtPath)
    }

    package func wrappedInRepeatUntilIteration(
        path: HeistExecutionPath,
        durationMs: ElapsedMilliseconds,
        declaration: HeistRepeatUntilDeclaration,
        evidence: HeistFailedRepeatUntilEvidence,
        failure: HeistFailureDetail
    ) -> HeistAbortedChildren {
        let result = HeistExecutionStepResult.repeatUntilIteration(
            path: path,
            durationMs: durationMs,
            declaration: declaration,
            completion: .childAborted(
                evidence: evidence,
                failure: failure,
                children: self
            )
        )
        return .init(admitted: [result], abortedAtPath: abortedAtPath)
    }

    package init(from decoder: Decoder) throws {
        let values = try [HeistExecutionStepResult](from: decoder)
        guard let admitted = Self(values) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "aborted result children require a failed node"
            ))
        }
        self = admitted
    }

    package func encode(to encoder: Encoder) throws { try values.encode(to: encoder) }
}

package enum HeistExecutedChildren: Sendable, Equatable {
    case passed(HeistPassingChildren)
    case aborted(HeistAbortedChildren)

    package static let empty = Self.passed(.empty)

    package var values: [HeistExecutionStepResult] {
        switch self {
        case .passed(let children): children.values
        case .aborted(let children): children.values
        }
    }

    package var abortedAtPath: HeistExecutionPath? {
        guard case .aborted(let children) = self else { return nil }
        return children.abortedAtPath
    }

    package mutating func append(_ result: HeistExecutionStepResult) {
        switch self {
        case .passed(let children):
            self = children.appending(result)
        case .aborted(let children):
            self = .aborted(children.appending(result))
        }
    }
}

package enum HeistEvidenceAvailability<Evidence>: Codable, Sendable, Equatable
where Evidence: Codable & Sendable & Equatable {
    case unavailable
    case observed(Evidence)

    package init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = container.decodeNil() ? .unavailable : .observed(try container.decode(Evidence.self))
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .unavailable: try container.encodeNil()
        case .observed(let evidence): try container.encode(evidence)
        }
    }

    package var value: Evidence? {
        guard case .observed(let evidence) = self else { return nil }
        return evidence
    }
}

package protocol HeistResultEvidenceRule: Sendable {
    associatedtype Evidence: Codable & Sendable & Equatable
    static var rejection: String { get }
    static func admits(_ evidence: Evidence) -> Bool
}

package struct HeistResultEvidence<Rule>: Codable, Sendable, Equatable
where Rule: HeistResultEvidenceRule {
    package let value: Rule.Evidence

    package init?(_ value: Rule.Evidence) {
        guard Rule.admits(value) else { return nil }
        self.value = value
    }

    package init(admitted value: Rule.Evidence) {
        self.value = value
    }

    package init(from decoder: Decoder) throws {
        let value = try Rule.Evidence(from: decoder)
        guard let admitted = Self(value) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: Rule.rejection
            ))
        }
        self = admitted
    }

    package func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}

package enum HeistPassedActionRule: HeistResultEvidenceRule {
    package static let rejection = "passed action evidence must prove success"
    package static func admits(_ evidence: HeistActionEvidence) -> Bool { evidence.resultSucceeded == true }
}

package enum HeistFailedActionRule: HeistResultEvidenceRule {
    package static let rejection = "failed action evidence must prove failure"
    package static func admits(_ evidence: HeistActionEvidence) -> Bool { evidence.resultSucceeded == false }
}

package enum HeistPassedWaitRule: HeistResultEvidenceRule {
    package static let rejection = "passed wait evidence must be matched or handled_else"
    package static func admits(_ evidence: HeistWaitEvidence) -> Bool {
        evidence.outcome == .matched || evidence.outcome == .handledElse
    }
}

package enum HeistFailedWaitRule: HeistResultEvidenceRule {
    package static let rejection = "failed wait evidence must prove failure"
    package static func admits(_ evidence: HeistWaitEvidence) -> Bool { evidence.outcome == .failed }
}

package enum HeistPassedForEachElementRule: HeistResultEvidenceRule {
    package static let rejection = "passed for_each_element evidence cannot include a failure reason"
    package static func admits(_ evidence: HeistForEachElementEvidence) -> Bool { evidence.failureReason == nil }
}

package enum HeistFailedForEachElementRule: HeistResultEvidenceRule {
    package static let rejection = "failed for_each_element evidence requires a failure reason"
    package static func admits(_ evidence: HeistForEachElementEvidence) -> Bool { evidence.failureReason != nil }
}

package enum HeistPassedForEachStringRule: HeistResultEvidenceRule {
    package static let rejection = "passed for_each_string evidence cannot include a failure reason"
    package static func admits(_ evidence: HeistForEachStringEvidence) -> Bool { evidence.failureReason == nil }
}

package enum HeistFailedForEachStringRule: HeistResultEvidenceRule {
    package static let rejection = "failed for_each_string evidence requires a failure reason"
    package static func admits(_ evidence: HeistForEachStringEvidence) -> Bool { evidence.failureReason != nil }
}

package enum HeistPassedRepeatUntilRule: HeistResultEvidenceRule {
    package static let rejection = "passed repeat_until evidence must be matched"
    package static func admits(_ evidence: HeistRepeatUntilEvidence) -> Bool {
        evidence.outcome == .matched
    }
}

package enum HeistPassedRepeatUntilIterationRule: HeistResultEvidenceRule {
    package static let rejection = "passed repeat_until iteration evidence has an incompatible outcome"
    package static func admits(_ evidence: HeistRepeatUntilEvidence) -> Bool {
        evidence.outcome == .matched || evidence.outcome == .continued
    }
}

package enum HeistFailedRepeatUntilRule: HeistResultEvidenceRule {
    package static let rejection = "failed repeat_until evidence must prove failure"
    package static func admits(_ evidence: HeistRepeatUntilEvidence) -> Bool { evidence.outcome == .failed }
}

package enum HeistPassedInvocationRule: HeistResultEvidenceRule {
    package static let rejection = "passed invocation evidence cannot prove failure"
    package static func admits(_ evidence: HeistInvocationEvidence) -> Bool { !evidence.provesInvocationFailure }
}

package enum HeistFailedInvocationRule: HeistResultEvidenceRule {
    package static let rejection = "failed invocation evidence must prove failure"
    package static func admits(_ evidence: HeistInvocationEvidence) -> Bool { evidence.provesInvocationFailure }
}

package typealias HeistPassedActionEvidence = HeistResultEvidence<HeistPassedActionRule>
package typealias HeistFailedActionEvidence = HeistResultEvidence<HeistFailedActionRule>
package typealias HeistPassedWaitEvidence = HeistResultEvidence<HeistPassedWaitRule>
package typealias HeistFailedWaitEvidence = HeistResultEvidence<HeistFailedWaitRule>
package typealias HeistPassedForEachElementEvidence = HeistResultEvidence<HeistPassedForEachElementRule>
package typealias HeistFailedForEachElementEvidence = HeistResultEvidence<HeistFailedForEachElementRule>
package typealias HeistPassedForEachStringEvidence = HeistResultEvidence<HeistPassedForEachStringRule>
package typealias HeistFailedForEachStringEvidence = HeistResultEvidence<HeistFailedForEachStringRule>
package typealias HeistPassedRepeatUntilEvidence = HeistResultEvidence<HeistPassedRepeatUntilRule>
package typealias HeistPassedRepeatUntilIterationEvidence = HeistResultEvidence<HeistPassedRepeatUntilIterationRule>
package typealias HeistFailedRepeatUntilEvidence = HeistResultEvidence<HeistFailedRepeatUntilRule>
package typealias HeistPassedInvocationEvidence = HeistResultEvidence<HeistPassedInvocationRule>
package typealias HeistFailedInvocationEvidence = HeistResultEvidence<HeistFailedInvocationRule>

private extension HeistActionEvidence {
    var resultSucceeded: Bool? {
        switch self {
        case .commandResolutionFailure:
            return false
        case .dispatch(let result):
            return result.outcome.isSuccess
        case .expectation(let result, let expectationResult, let expectation):
            guard result.outcome.isSuccess,
                  expectationResult.method == .wait,
                  expectationResult.outcome.isSuccess == expectation.met
            else { return nil }
            return expectation.met
        }
    }
}
