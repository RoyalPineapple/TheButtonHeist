import Foundation
import ThePlans

public enum HeistExecutionStepKind: String, Codable, Sendable, Equatable {
    case action
    case wait
    case conditional
    case forEachElement = "for_each_element"
    case forEachString = "for_each_string"
    case forEachIteration = "for_each_iteration"
    case repeatUntil = "repeat_until"
    case repeatUntilIteration = "repeat_until_iteration"
    case warn
    case fail
    case heist
    case invoke
}

public enum HeistExecutionStepStatus: String, Codable, Sendable, Equatable {
    case passed
    case failed
    case skipped
}

package enum HeistExecutionCompletion<PassedEvidence, FailedEvidence, AbortedEvidence>: Sendable, Equatable
where PassedEvidence: Sendable & Equatable,
      FailedEvidence: Sendable & Equatable,
      AbortedEvidence: Sendable & Equatable {
    case passed(evidence: PassedEvidence, children: HeistPassingChildren = .empty)
    case failed(evidence: FailedEvidence, failure: HeistFailureDetail, children: HeistPassingChildren = .empty)
    case childAborted(evidence: AbortedEvidence, failure: HeistFailureDetail, children: HeistAbortedChildren)
    case skipped(children: HeistSkippedChildren = .empty)

    var facts: HeistStepFacts {
        switch self {
        case .passed(_, let children):
            .init(status: .passed, failure: nil, children: children.values, abortedAtChildPath: nil)
        case .failed(_, let failure, let children):
            .init(status: .failed, failure: failure, children: children.values, abortedAtChildPath: nil)
        case .childAborted(_, let failure, let children):
            .init(
                status: .failed,
                failure: failure,
                children: children.values,
                abortedAtChildPath: children.abortedAtPath
            )
        case .skipped(let children):
            .init(status: .skipped, failure: nil, children: children.values, abortedAtChildPath: nil)
        }
    }
}

package enum HeistWarningCompletion: Sendable, Equatable {
    case passed(children: HeistPassingChildren = .empty)
    case skipped(children: HeistSkippedChildren = .empty)
}

package enum HeistFailureCompletion: Sendable, Equatable {
    case failed(failure: HeistFailureDetail, children: HeistPassingChildren = .empty)
    case childAborted(failure: HeistFailureDetail, children: HeistAbortedChildren)
    case skipped(children: HeistSkippedChildren = .empty)
}

package enum HeistGroupCompletion: Sendable, Equatable {
    case passed(children: HeistPassingChildren = .empty)
    case childAborted(failure: HeistFailureDetail, children: HeistAbortedChildren)
    case skipped(children: HeistSkippedChildren = .empty)
}

package typealias HeistActionCompletion = HeistExecutionCompletion<
    HeistPassedActionEvidence, HeistFailedActionEvidence, HeistPassedActionEvidence
>
package typealias HeistWaitCompletion = HeistExecutionCompletion<
    HeistPassedWaitEvidence, HeistEvidenceAvailability<HeistFailedWaitEvidence>, HeistPassedWaitEvidence
>
package typealias HeistCaseSelectionCompletion = HeistExecutionCompletion<
    HeistCaseSelectionEvidence, HeistEvidenceAvailability<HeistCaseSelectionEvidence>, HeistCaseSelectionEvidence
>
package typealias HeistForEachElementCompletion = HeistExecutionCompletion<
    HeistPassedForEachElementEvidence,
    HeistEvidenceAvailability<HeistFailedForEachElementEvidence>,
    HeistFailedForEachElementEvidence
>
package typealias HeistForEachStringCompletion = HeistExecutionCompletion<
    HeistPassedForEachStringEvidence,
    HeistEvidenceAvailability<HeistFailedForEachStringEvidence>,
    HeistFailedForEachStringEvidence
>
package typealias HeistRepeatUntilCompletion = HeistExecutionCompletion<
    HeistPassedRepeatUntilEvidence,
    HeistEvidenceAvailability<HeistFailedRepeatUntilEvidence>,
    HeistFailedRepeatUntilEvidence
>
package typealias HeistRepeatUntilIterationCompletion = HeistExecutionCompletion<
    HeistPassedRepeatUntilIterationEvidence,
    HeistEvidenceAvailability<HeistFailedRepeatUntilEvidence>,
    HeistFailedRepeatUntilEvidence
>
package typealias HeistInvocationFailureEvidence = HeistEvidenceAvailability<HeistFailedInvocationEvidence>
package typealias HeistInvocationCompletion = HeistExecutionCompletion<
    HeistPassedInvocationEvidence, HeistInvocationFailureEvidence, HeistInvocationFailureEvidence
>

package struct HeistForEachStringDeclaration: Sendable, Equatable {
    package let parameter: HeistReferenceName
    package let count: Int

    package init?(parameter: HeistReferenceName, count: Int) {
        guard count >= 0 else { return nil }
        self.parameter = parameter
        self.count = count
    }

    package init(_ step: ForEachStringStep) {
        parameter = step.parameter
        count = step.values.count
    }
}

package struct HeistForEachElementDeclaration: Sendable, Equatable {
    package let parameter: HeistReferenceName
    package let matching: ElementPredicateTemplate
    package let limit: Int

    package init?(
        parameter: HeistReferenceName,
        matching: ElementPredicateTemplate,
        limit: Int
    ) {
        guard limit > 0 else { return nil }
        self.parameter = parameter
        self.matching = matching
        self.limit = limit
    }

    package init(_ step: ForEachElementStep) {
        parameter = step.parameter
        matching = step.matching
        limit = step.limit
    }
}

package struct HeistRepeatUntilDeclaration: Sendable, Equatable {
    package let predicate: AccessibilityPredicate
    package let timeout: WaitTimeout

    package init(predicate: AccessibilityPredicate, timeout: WaitTimeout) {
        self.predicate = predicate
        self.timeout = timeout
    }

    package init(_ step: RepeatUntilStep) {
        predicate = step.predicate
        timeout = step.timeout
    }
}

/// One semantic node in a heist execution receipt tree.
public struct HeistExecutionStepResult: Codable, Sendable, Equatable {
    public let path: HeistExecutionPath
    public let durationMs: Int
    let node: HeistExecutionStepNode

    public var kind: HeistExecutionStepKind {
        switch node {
        case .action: .action
        case .wait: .wait
        case .conditional: .conditional
        case .forEachElement: .forEachElement
        case .forEachString: .forEachString
        case .forEachElementIteration, .forEachStringIteration: .forEachIteration
        case .repeatUntil: .repeatUntil
        case .repeatUntilIteration: .repeatUntilIteration
        case .warning: .warn
        case .failure: .fail
        case .heist: .heist
        case .invocation: .invoke
        }
    }

    public var status: HeistExecutionStepStatus { node.facts.status }
    public var failure: HeistFailureDetail? { node.facts.failure }
    public var children: [HeistExecutionStepResult] { node.facts.children }
    public var abortedAtChildPath: HeistExecutionPath? { node.facts.abortedAtChildPath }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case path
        case durationMs
        case node
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist execution step result")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let path = try container.decode(HeistExecutionPath.self, forKey: .path)
        let durationMs = try container.decode(Int.self, forKey: .durationMs)
        let node = try container.decode(HeistExecutionStepNode.self, forKey: .node)
        self = try Self.admitDecodedNode(path: path, durationMs: durationMs, node: node, from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(durationMs, forKey: .durationMs)
        try container.encode(node, forKey: .node)
    }

    package func walk(
        enter: (HeistExecutionStepResult) throws -> Void,
        leave: (HeistExecutionStepResult) throws -> Void
    ) rethrows {
        try enter(self)
        for child in children { try child.walk(enter: enter, leave: leave) }
        try leave(self)
    }

    package var firstFailedStepInReceiptOrder: HeistExecutionStepResult? {
        var firstFailure: HeistExecutionStepResult?
        walk(enter: { _ in }, leave: { if firstFailure == nil, $0.status == .failed { firstFailure = $0 } })
        return firstFailure
    }
}

package extension Sequence where Element == HeistExecutionStepResult {
    func walk(
        enter: (HeistExecutionStepResult) throws -> Void,
        leave: (HeistExecutionStepResult) throws -> Void
    ) rethrows {
        for step in self { try step.walk(enter: enter, leave: leave) }
    }

    var firstFailedStepInReceiptOrder: HeistExecutionStepResult? {
        lazy.compactMap(\.firstFailedStepInReceiptOrder).first
    }
}

public extension HeistExecutionStepResult {
    var actionEvidence: HeistActionEvidence? {
        guard case .action(_, let completion) = node else { return nil }
        switch completion {
        case .passed(let evidence, _), .childAborted(let evidence, _, _): return evidence.value
        case .failed(let evidence, _, _): return evidence.value
        case .skipped: return nil
        }
    }

    var waitEvidence: HeistWaitEvidence? {
        guard case .wait(_, _, let completion) = node else { return nil }
        switch completion {
        case .passed(let evidence, _), .childAborted(let evidence, _, _): return evidence.value
        case .failed(let evidence, _, _): return evidence.value?.value
        case .skipped: return nil
        }
    }

    var caseSelectionEvidence: HeistCaseSelectionEvidence? {
        guard case .conditional(let completion) = node else { return nil }
        switch completion {
        case .passed(let evidence, _), .childAborted(let evidence, _, _): return evidence
        case .failed(let evidence, _, _): return evidence.value
        case .skipped: return nil
        }
    }

    var forEachStringEvidence: HeistForEachStringEvidence? {
        let completion: HeistForEachStringCompletion
        switch node {
        case .forEachString(_, let value), .forEachStringIteration(_, let value): completion = value
        default: return nil
        }
        switch completion {
        case .passed(let evidence, _): return evidence.value
        case .failed(let evidence, _, _): return evidence.value?.value
        case .childAborted(let evidence, _, _): return evidence.value
        case .skipped: return nil
        }
    }

    var forEachElementEvidence: HeistForEachElementEvidence? {
        let completion: HeistForEachElementCompletion
        switch node {
        case .forEachElement(_, let value), .forEachElementIteration(_, let value): completion = value
        default: return nil
        }
        switch completion {
        case .passed(let evidence, _): return evidence.value
        case .failed(let evidence, _, _): return evidence.value?.value
        case .childAborted(let evidence, _, _): return evidence.value
        case .skipped: return nil
        }
    }

    var repeatUntilEvidence: HeistRepeatUntilEvidence? {
        switch node {
        case .repeatUntil(_, let completion):
            switch completion {
            case .passed(let evidence, _): return evidence.value
            case .failed(let evidence, _, _): return evidence.value?.value
            case .childAborted(let evidence, _, _): return evidence.value
            case .skipped: return nil
            }
        case .repeatUntilIteration(_, let completion):
            switch completion {
            case .passed(let evidence, _): return evidence.value
            case .failed(let evidence, _, _): return evidence.value?.value
            case .childAborted(let evidence, _, _): return evidence.value
            case .skipped: return nil
            }
        default:
            return nil
        }
    }

    var invocationEvidence: HeistInvocationEvidence? {
        guard case .invocation(_, _, let completion) = node else { return nil }
        switch completion {
        case .passed(let evidence, _): return evidence.value
        case .failed(let evidence, _, _), .childAborted(let evidence, _, _): return evidence.value?.value
        case .skipped: return nil
        }
    }

    var warningEvidence: HeistExecutionWarning? {
        guard case .warning(let message, .passed) = node else { return nil }
        return HeistExecutionWarning(path: path, message: message)
    }
}
