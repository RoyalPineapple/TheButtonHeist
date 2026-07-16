import Foundation
import ThePlans

package struct HeistPassingChildren: Codable, Sendable, Equatable {
    package static let empty = Self(admitted: [])
    package let values: [HeistExecutionStepResult]

    package init?(_ values: [HeistExecutionStepResult]) {
        guard values.firstFailedStepInReceiptOrder == nil else { return nil }
        self.init(admitted: values)
    }

    fileprivate init(admitted values: [HeistExecutionStepResult]) { self.values = values }

    package init(from decoder: Decoder) throws {
        let values = try [HeistExecutionStepResult](from: decoder)
        guard let admitted = Self(values) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "passing receipt children cannot contain a failed node"
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
        durationMs: Int,
        step: HeistStep
    ) {
        values.append(.skipped(path: path, durationMs: durationMs, step: step))
    }

    package init(from decoder: Decoder) throws {
        let values = try [HeistExecutionStepResult](from: decoder)
        guard let admitted = Self(values) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "skipped receipt children must all be skipped"
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
        guard let failed = values.firstFailedStepInReceiptOrder else { return nil }
        self.init(admitted: values, abortedAtPath: failed.path)
    }

    fileprivate init(admitted values: [HeistExecutionStepResult], abortedAtPath: HeistExecutionPath) {
        self.values = values
        self.abortedAtPath = abortedAtPath
    }

    package init(from decoder: Decoder) throws {
        let values = try [HeistExecutionStepResult](from: decoder)
        guard let admitted = Self(values) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "aborted receipt children require a failed node"
            ))
        }
        self = admitted
    }

    package func encode(to encoder: Encoder) throws { try values.encode(to: encoder) }
}

package enum HeistExecutedChildren: Sendable, Equatable {
    case passed(HeistPassingChildren)
    case aborted(HeistAbortedChildren)

    package init(_ values: [HeistExecutionStepResult]) {
        if let failed = values.firstFailedStepInReceiptOrder {
            self = .aborted(.init(admitted: values, abortedAtPath: failed.path))
        } else {
            self = .passed(.init(admitted: values))
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

package protocol HeistReceiptEvidenceRule: Sendable {
    associatedtype Evidence: Codable & Sendable & Equatable
    static var rejection: String { get }
    static func admits(_ evidence: Evidence) -> Bool
}

package struct HeistReceiptEvidence<Rule>: Codable, Sendable, Equatable
where Rule: HeistReceiptEvidenceRule {
    package let value: Rule.Evidence

    package init?(_ value: Rule.Evidence) {
        guard Rule.admits(value) else { return nil }
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

package enum HeistPassedActionRule: HeistReceiptEvidenceRule {
    package static let rejection = "passed action evidence must prove success"
    package static func admits(_ evidence: HeistActionEvidence) -> Bool { evidence.receiptSuccess == true }
}

package enum HeistFailedActionRule: HeistReceiptEvidenceRule {
    package static let rejection = "failed action evidence must prove failure"
    package static func admits(_ evidence: HeistActionEvidence) -> Bool { evidence.receiptSuccess == false }
}

package enum HeistPassedWaitRule: HeistReceiptEvidenceRule {
    package static let rejection = "passed wait evidence must be matched or handled_else"
    package static func admits(_ evidence: HeistWaitEvidence) -> Bool {
        evidence.outcome == .matched || evidence.outcome == .handledElse
    }
}

package enum HeistFailedWaitRule: HeistReceiptEvidenceRule {
    package static let rejection = "failed wait evidence must prove failure"
    package static func admits(_ evidence: HeistWaitEvidence) -> Bool { evidence.outcome == .failed }
}

package enum HeistPassedForEachElementRule: HeistReceiptEvidenceRule {
    package static let rejection = "passed for_each_element evidence cannot include a failure reason"
    package static func admits(_ evidence: HeistForEachElementEvidence) -> Bool { evidence.failureReason == nil }
}

package enum HeistFailedForEachElementRule: HeistReceiptEvidenceRule {
    package static let rejection = "failed for_each_element evidence requires a failure reason"
    package static func admits(_ evidence: HeistForEachElementEvidence) -> Bool { evidence.failureReason != nil }
}

package enum HeistPassedForEachStringRule: HeistReceiptEvidenceRule {
    package static let rejection = "passed for_each_string evidence cannot include a failure reason"
    package static func admits(_ evidence: HeistForEachStringEvidence) -> Bool { evidence.failureReason == nil }
}

package enum HeistFailedForEachStringRule: HeistReceiptEvidenceRule {
    package static let rejection = "failed for_each_string evidence requires a failure reason"
    package static func admits(_ evidence: HeistForEachStringEvidence) -> Bool { evidence.failureReason != nil }
}

package enum HeistPassedRepeatUntilRule: HeistReceiptEvidenceRule {
    package static let rejection = "passed repeat_until evidence must be matched or handled_else"
    package static func admits(_ evidence: HeistRepeatUntilEvidence) -> Bool {
        evidence.outcome == .matched || evidence.outcome == .handledElse
    }
}

package enum HeistPassedRepeatUntilIterationRule: HeistReceiptEvidenceRule {
    package static let rejection = "passed repeat_until iteration evidence has an incompatible outcome"
    package static func admits(_ evidence: HeistRepeatUntilEvidence) -> Bool {
        evidence.outcome == .matched || evidence.outcome == .continued
    }
}

package enum HeistFailedRepeatUntilRule: HeistReceiptEvidenceRule {
    package static let rejection = "failed repeat_until evidence must prove failure"
    package static func admits(_ evidence: HeistRepeatUntilEvidence) -> Bool { evidence.outcome == .failed }
}

package enum HeistPassedInvocationRule: HeistReceiptEvidenceRule {
    package static let rejection = "passed invocation evidence cannot prove failure"
    package static func admits(_ evidence: HeistInvocationEvidence) -> Bool { !evidence.provesInvocationFailure }
}

package enum HeistFailedInvocationRule: HeistReceiptEvidenceRule {
    package static let rejection = "failed invocation evidence must prove failure"
    package static func admits(_ evidence: HeistInvocationEvidence) -> Bool { evidence.provesInvocationFailure }
}

package typealias HeistPassedActionEvidence = HeistReceiptEvidence<HeistPassedActionRule>
package typealias HeistFailedActionEvidence = HeistReceiptEvidence<HeistFailedActionRule>
package typealias HeistPassedWaitEvidence = HeistReceiptEvidence<HeistPassedWaitRule>
package typealias HeistFailedWaitEvidence = HeistReceiptEvidence<HeistFailedWaitRule>
package typealias HeistPassedForEachElementEvidence = HeistReceiptEvidence<HeistPassedForEachElementRule>
package typealias HeistFailedForEachElementEvidence = HeistReceiptEvidence<HeistFailedForEachElementRule>
package typealias HeistPassedForEachStringEvidence = HeistReceiptEvidence<HeistPassedForEachStringRule>
package typealias HeistFailedForEachStringEvidence = HeistReceiptEvidence<HeistFailedForEachStringRule>
package typealias HeistPassedRepeatUntilEvidence = HeistReceiptEvidence<HeistPassedRepeatUntilRule>
package typealias HeistPassedRepeatUntilIterationEvidence = HeistReceiptEvidence<HeistPassedRepeatUntilIterationRule>
package typealias HeistFailedRepeatUntilEvidence = HeistReceiptEvidence<HeistFailedRepeatUntilRule>
package typealias HeistPassedInvocationEvidence = HeistReceiptEvidence<HeistPassedInvocationRule>
package typealias HeistFailedInvocationEvidence = HeistReceiptEvidence<HeistFailedInvocationRule>

private extension HeistActionEvidence {
    var receiptSuccess: Bool? {
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
