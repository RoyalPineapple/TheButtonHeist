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

    fileprivate var facts: HeistStepFacts {
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

private struct HeistStepFacts {
    let status: HeistExecutionStepStatus
    let failure: HeistFailureDetail?
    let children: [HeistExecutionStepResult]
    let abortedAtChildPath: HeistExecutionPath?
}

enum HeistExecutionStepNode: Codable, Sendable, Equatable {
    case action(command: HeistActionCommand, completion: HeistActionCompletion)
    case wait(predicate: AccessibilityPredicate, timeout: WaitTimeout, completion: HeistWaitCompletion)
    case conditional(completion: HeistCaseSelectionCompletion)
    case forEachElement(
        parameter: HeistReferenceName,
        matching: ElementPredicateTemplate,
        limit: Int,
        completion: HeistForEachElementCompletion
    )
    case forEachString(parameter: HeistReferenceName, count: Int, completion: HeistForEachStringCompletion)
    case forEachElementIteration(
        parameter: HeistReferenceName,
        matching: ElementPredicateTemplate,
        limit: Int,
        completion: HeistForEachElementCompletion
    )
    case forEachStringIteration(parameter: HeistReferenceName, count: Int, completion: HeistForEachStringCompletion)
    case repeatUntil(
        predicate: AccessibilityPredicate,
        timeout: WaitTimeout,
        completion: HeistRepeatUntilCompletion
    )
    case repeatUntilIteration(
        predicate: AccessibilityPredicate,
        timeout: WaitTimeout,
        completion: HeistRepeatUntilIterationCompletion
    )
    case warning(message: HeistWarningMessage, completion: HeistWarningCompletion)
    case failure(message: HeistFailureMessage, completion: HeistFailureCompletion)
    case heist(name: HeistPlanName?, completion: HeistGroupCompletion)
    case invocation(path: HeistInvocationPath, argument: HeistArgument, completion: HeistInvocationCompletion)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type
        case outcome
        case command
        case predicate
        case timeout
        case parameter
        case count
        case matching
        case limit
        case path
        case argument
        case name
        case message
        case evidence
        case failure
        case children
    }

    private enum NodeType: String, Codable {
        case action
        case wait
        case conditional
        case forEachElement = "for_each_element"
        case forEachString = "for_each_string"
        case forEachElementIteration = "for_each_element_iteration"
        case forEachStringIteration = "for_each_string_iteration"
        case repeatUntil = "repeat_until"
        case repeatUntilIteration = "repeat_until_iteration"
        case warning
        case failure
        case heist
        case invocation
    }

    private enum Outcome: String, Codable {
        case passed
        case failed
        case childAborted = "child_aborted"
        case skipped
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist execution step node")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(NodeType.self, forKey: .type)
        switch type {
        case .action:
            self = try Self.decodeAction(from: container)
        case .wait:
            self = .wait(
                predicate: try container.decode(AccessibilityPredicate.self, forKey: .predicate),
                timeout: try container.decode(WaitTimeout.self, forKey: .timeout),
                completion: try Self.decodeCompletion(
                    from: container,
                    semanticKeys: [.type, .predicate, .timeout],
                    typeName: type.rawValue
                )
            )
        case .conditional:
            self = .conditional(completion: try Self.decodeCompletion(
                from: container,
                semanticKeys: [.type],
                typeName: type.rawValue
            ))
        case .forEachElement, .forEachElementIteration:
            self = try Self.decodeForEachElement(type, from: container)
        case .forEachString, .forEachStringIteration:
            self = try Self.decodeForEachString(type, from: container)
        case .repeatUntil:
            self = try Self.decodeRepeatUntil(from: container)
        case .repeatUntilIteration:
            self = try Self.decodeRepeatUntilIteration(from: container)
        case .warning:
            self = .warning(
                message: try container.decode(HeistWarningMessage.self, forKey: .message),
                completion: try Self.decodeWarning(from: container)
            )
        case .failure:
            self = .failure(
                message: try container.decode(HeistFailureMessage.self, forKey: .message),
                completion: try Self.decodeFailure(from: container)
            )
        case .heist:
            self = .heist(
                name: try container.decodeIfPresent(HeistPlanName.self, forKey: .name),
                completion: try Self.decodeGroup(from: container)
            )
        case .invocation:
            self = .invocation(
                path: try container.decode(HeistInvocationPath.self, forKey: .path),
                argument: try container.decode(HeistArgument.self, forKey: .argument),
                completion: try Self.decodeCompletion(
                    from: container,
                    semanticKeys: [.type, .path, .argument],
                    typeName: type.rawValue
                )
            )
        }
    }

    private static func decodeAction(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Self {
        let command = try container.decode(HeistActionCommand.self, forKey: .command)
        let completion: HeistActionCompletion = try decodeCompletion(
            from: container,
            semanticKeys: [.type, .command],
            typeName: NodeType.action.rawValue
        )
        guard actionCompletion(completion, matches: command) else {
            throw invalidNode(
                in: container,
                "action evidence result method must match the receipt command"
            )
        }
        return .action(command: command, completion: completion)
    }

    private static func decodeForEachElement(
        _ type: NodeType,
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Self {
        let parameter = try container.decode(HeistReferenceName.self, forKey: .parameter)
        let matching = try container.decode(ElementPredicateTemplate.self, forKey: .matching)
        let limit = try container.decode(Int.self, forKey: .limit)
        let completion: HeistForEachElementCompletion = try decodeCompletion(
            from: container,
            semanticKeys: [.type, .parameter, .matching, .limit],
            typeName: type.rawValue
        )
        let isIteration = type == .forEachElementIteration
        guard forEachElementCompletion(completion, limit: limit, isIteration: isIteration) else {
            throw invalidNode(in: container, "for_each_element evidence must fit its node declaration")
        }
        return isIteration
            ? .forEachElementIteration(
                parameter: parameter,
                matching: matching,
                limit: limit,
                completion: completion
            )
            : .forEachElement(
                parameter: parameter,
                matching: matching,
                limit: limit,
                completion: completion
            )
    }

    private static func decodeForEachString(
        _ type: NodeType,
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Self {
        let parameter = try container.decode(HeistReferenceName.self, forKey: .parameter)
        let count = try container.decode(Int.self, forKey: .count)
        let completion: HeistForEachStringCompletion = try decodeCompletion(
            from: container,
            semanticKeys: [.type, .parameter, .count],
            typeName: type.rawValue
        )
        let isIteration = type == .forEachStringIteration
        guard forEachStringCompletion(completion, count: count, isIteration: isIteration) else {
            throw invalidNode(in: container, "for_each_string evidence must fit its node declaration")
        }
        return isIteration
            ? .forEachStringIteration(parameter: parameter, count: count, completion: completion)
            : .forEachString(parameter: parameter, count: count, completion: completion)
    }

    private static func decodeRepeatUntil(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Self {
        let predicate = try container.decode(AccessibilityPredicate.self, forKey: .predicate)
        let timeout = try container.decode(WaitTimeout.self, forKey: .timeout)
        let completion: HeistRepeatUntilCompletion = try decodeCompletion(
            from: container,
            semanticKeys: [.type, .predicate, .timeout],
            typeName: NodeType.repeatUntil.rawValue
        )
        guard repeatUntilCompletion(completion, matches: predicate) else {
            throw invalidNode(in: container, "repeat_until evidence must fit its node declaration")
        }
        return .repeatUntil(predicate: predicate, timeout: timeout, completion: completion)
    }

    private static func decodeRepeatUntilIteration(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Self {
        let predicate = try container.decode(AccessibilityPredicate.self, forKey: .predicate)
        let timeout = try container.decode(WaitTimeout.self, forKey: .timeout)
        let completion: HeistRepeatUntilIterationCompletion = try decodeCompletion(
            from: container,
            semanticKeys: [.type, .predicate, .timeout],
            typeName: NodeType.repeatUntilIteration.rawValue
        )
        guard repeatUntilIterationCompletion(completion, matches: predicate) else {
            throw invalidNode(in: container, "repeat_until iteration evidence must fit its node declaration")
        }
        return .repeatUntilIteration(predicate: predicate, timeout: timeout, completion: completion)
    }

    private static func invalidNode(
        in container: KeyedDecodingContainer<CodingKeys>,
        _ description: String
    ) -> DecodingError {
        .dataCorrupted(.init(codingPath: container.codingPath, debugDescription: description))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .action(let command, let completion):
            try container.encode(NodeType.action, forKey: .type)
            try container.encode(command, forKey: .command)
            try Self.encode(completion, to: &container)
        case .wait(let predicate, let timeout, let completion):
            try container.encode(NodeType.wait, forKey: .type)
            try container.encode(predicate, forKey: .predicate)
            try container.encode(timeout, forKey: .timeout)
            try Self.encode(completion, to: &container)
        case .conditional(let completion):
            try container.encode(NodeType.conditional, forKey: .type)
            try Self.encode(completion, to: &container)
        case .forEachElement(let parameter, let matching, let limit, let completion):
            try container.encode(NodeType.forEachElement, forKey: .type)
            try Self.encodeLoop(parameter, matching, limit, completion, to: &container)
        case .forEachElementIteration(let parameter, let matching, let limit, let completion):
            try container.encode(NodeType.forEachElementIteration, forKey: .type)
            try Self.encodeLoop(parameter, matching, limit, completion, to: &container)
        case .forEachString(let parameter, let count, let completion):
            try container.encode(NodeType.forEachString, forKey: .type)
            try Self.encodeLoop(parameter, count, completion, to: &container)
        case .forEachStringIteration(let parameter, let count, let completion):
            try container.encode(NodeType.forEachStringIteration, forKey: .type)
            try Self.encodeLoop(parameter, count, completion, to: &container)
        case .repeatUntil(let predicate, let timeout, let completion):
            try container.encode(NodeType.repeatUntil, forKey: .type)
            try container.encode(predicate, forKey: .predicate)
            try container.encode(timeout, forKey: .timeout)
            try Self.encode(completion, to: &container)
        case .repeatUntilIteration(let predicate, let timeout, let completion):
            try container.encode(NodeType.repeatUntilIteration, forKey: .type)
            try container.encode(predicate, forKey: .predicate)
            try container.encode(timeout, forKey: .timeout)
            try Self.encode(completion, to: &container)
        case .warning(let message, let completion):
            try container.encode(NodeType.warning, forKey: .type)
            try container.encode(message, forKey: .message)
            try Self.encode(completion, to: &container)
        case .failure(let message, let completion):
            try container.encode(NodeType.failure, forKey: .type)
            try container.encode(message, forKey: .message)
            try Self.encode(completion, to: &container)
        case .heist(let name, let completion):
            try container.encode(NodeType.heist, forKey: .type)
            try container.encodeIfPresent(name, forKey: .name)
            try Self.encode(completion, to: &container)
        case .invocation(let path, let argument, let completion):
            try container.encode(NodeType.invocation, forKey: .type)
            try container.encode(path, forKey: .path)
            try container.encode(argument, forKey: .argument)
            try Self.encode(completion, to: &container)
        }
    }

    private static func decodeCompletion<Passed, Failed, Aborted>(
        from container: KeyedDecodingContainer<CodingKeys>,
        semanticKeys: Set<CodingKeys>,
        typeName: String
    ) throws -> HeistExecutionCompletion<Passed, Failed, Aborted>
    where Passed: Codable & Sendable & Equatable,
          Failed: Codable & Sendable & Equatable,
          Aborted: Codable & Sendable & Equatable {
        switch try container.decode(Outcome.self, forKey: .outcome) {
        case .passed:
            try container.rejectIncompatibleFields(
                allowing: semanticKeys.union([.outcome, .evidence, .children]),
                typeName: "passed \(typeName) receipt node"
            )
            return .passed(
                evidence: try container.decode(Passed.self, forKey: .evidence),
                children: try container.decode(HeistPassingChildren.self, forKey: .children)
            )
        case .failed:
            try container.rejectIncompatibleFields(
                allowing: semanticKeys.union([.outcome, .evidence, .failure, .children]),
                typeName: "failed \(typeName) receipt node"
            )
            return .failed(
                evidence: try container.decode(Failed.self, forKey: .evidence),
                failure: try container.decode(HeistFailureDetail.self, forKey: .failure),
                children: try container.decode(HeistPassingChildren.self, forKey: .children)
            )
        case .childAborted:
            try container.rejectIncompatibleFields(
                allowing: semanticKeys.union([.outcome, .evidence, .failure, .children]),
                typeName: "child-aborted \(typeName) receipt node"
            )
            return .childAborted(
                evidence: try container.decode(Aborted.self, forKey: .evidence),
                failure: try container.decode(HeistFailureDetail.self, forKey: .failure),
                children: try container.decode(HeistAbortedChildren.self, forKey: .children)
            )
        case .skipped:
            try container.rejectIncompatibleFields(
                allowing: semanticKeys.union([.outcome, .children]),
                typeName: "skipped \(typeName) receipt node"
            )
            return .skipped(children: try container.decode(HeistSkippedChildren.self, forKey: .children))
        }
    }

    private static func encode<Passed, Failed, Aborted>(
        _ completion: HeistExecutionCompletion<Passed, Failed, Aborted>,
        to container: inout KeyedEncodingContainer<CodingKeys>
    ) throws where Passed: Codable, Failed: Codable, Aborted: Codable {
        switch completion {
        case .passed(let evidence, let children):
            try container.encode(Outcome.passed, forKey: .outcome)
            try container.encode(evidence, forKey: .evidence)
            try container.encode(children, forKey: .children)
        case .failed(let evidence, let failure, let children):
            try container.encode(Outcome.failed, forKey: .outcome)
            try container.encode(evidence, forKey: .evidence)
            try container.encode(failure, forKey: .failure)
            try container.encode(children, forKey: .children)
        case .childAborted(let evidence, let failure, let children):
            try container.encode(Outcome.childAborted, forKey: .outcome)
            try container.encode(evidence, forKey: .evidence)
            try container.encode(failure, forKey: .failure)
            try container.encode(children, forKey: .children)
        case .skipped(let children):
            try container.encode(Outcome.skipped, forKey: .outcome)
            try container.encode(children, forKey: .children)
        }
    }

    private static func decodeWarning(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> HeistWarningCompletion {
        switch try container.decode(Outcome.self, forKey: .outcome) {
        case .passed:
            try container.rejectIncompatibleFields(
                allowing: [.type, .message, .outcome, .children],
                typeName: "passed warning receipt node"
            )
            return .passed(children: try container.decode(HeistPassingChildren.self, forKey: .children))
        case .skipped:
            try container.rejectIncompatibleFields(
                allowing: [.type, .message, .outcome, .children],
                typeName: "skipped warning receipt node"
            )
            return .skipped(children: try container.decode(HeistSkippedChildren.self, forKey: .children))
        case .failed, .childAborted:
            throw incompatibleOutcome("warning", in: container)
        }
    }

    private static func decodeFailure(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> HeistFailureCompletion {
        switch try container.decode(Outcome.self, forKey: .outcome) {
        case .failed:
            try container.rejectIncompatibleFields(
                allowing: [.type, .message, .outcome, .failure, .children],
                typeName: "failed explicit-failure receipt node"
            )
            return .failed(
                failure: try container.decode(HeistFailureDetail.self, forKey: .failure),
                children: try container.decode(HeistPassingChildren.self, forKey: .children)
            )
        case .skipped:
            try container.rejectIncompatibleFields(
                allowing: [.type, .message, .outcome, .children],
                typeName: "skipped explicit-failure receipt node"
            )
            return .skipped(children: try container.decode(HeistSkippedChildren.self, forKey: .children))
        case .passed, .childAborted:
            throw incompatibleOutcome("explicit-failure", in: container)
        }
    }

    private static func decodeGroup(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> HeistGroupCompletion {
        let semanticKeys: Set<CodingKeys> = [.type, .name, .outcome, .children]
        switch try container.decode(Outcome.self, forKey: .outcome) {
        case .passed:
            try container.rejectIncompatibleFields(allowing: semanticKeys, typeName: "passed heist receipt node")
            return .passed(children: try container.decode(HeistPassingChildren.self, forKey: .children))
        case .childAborted:
            try container.rejectIncompatibleFields(
                allowing: semanticKeys.union([.failure]),
                typeName: "child-aborted heist receipt node"
            )
            return .childAborted(
                failure: try container.decode(HeistFailureDetail.self, forKey: .failure),
                children: try container.decode(HeistAbortedChildren.self, forKey: .children)
            )
        case .skipped:
            try container.rejectIncompatibleFields(allowing: semanticKeys, typeName: "skipped heist receipt node")
            return .skipped(children: try container.decode(HeistSkippedChildren.self, forKey: .children))
        case .failed:
            throw incompatibleOutcome("heist", in: container)
        }
    }

    private static func incompatibleOutcome(
        _ type: String,
        in container: KeyedDecodingContainer<CodingKeys>
    ) -> DecodingError {
        .dataCorruptedError(
            forKey: .outcome,
            in: container,
            debugDescription: "outcome is not legal for a \(type) receipt node"
        )
    }

    private static func encode(
        _ completion: HeistWarningCompletion,
        to container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        switch completion {
        case .passed(let children):
            try container.encode(Outcome.passed, forKey: .outcome)
            try container.encode(children, forKey: .children)
        case .skipped(let children):
            try container.encode(Outcome.skipped, forKey: .outcome)
            try container.encode(children, forKey: .children)
        }
    }

    private static func encode(
        _ completion: HeistFailureCompletion,
        to container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        switch completion {
        case .failed(let failure, let children):
            try container.encode(Outcome.failed, forKey: .outcome)
            try container.encode(failure, forKey: .failure)
            try container.encode(children, forKey: .children)
        case .skipped(let children):
            try container.encode(Outcome.skipped, forKey: .outcome)
            try container.encode(children, forKey: .children)
        }
    }

    private static func encode(
        _ completion: HeistGroupCompletion,
        to container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        switch completion {
        case .passed(let children):
            try container.encode(Outcome.passed, forKey: .outcome)
            try container.encode(children, forKey: .children)
        case .childAborted(let failure, let children):
            try container.encode(Outcome.childAborted, forKey: .outcome)
            try container.encode(failure, forKey: .failure)
            try container.encode(children, forKey: .children)
        case .skipped(let children):
            try container.encode(Outcome.skipped, forKey: .outcome)
            try container.encode(children, forKey: .children)
        }
    }

    private static func encodeLoop(
        _ parameter: HeistReferenceName,
        _ matching: ElementPredicateTemplate,
        _ limit: Int,
        _ completion: HeistForEachElementCompletion,
        to container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        try container.encode(parameter, forKey: .parameter)
        try container.encode(matching, forKey: .matching)
        try container.encode(limit, forKey: .limit)
        try encode(completion, to: &container)
    }

    private static func encodeLoop(
        _ parameter: HeistReferenceName,
        _ count: Int,
        _ completion: HeistForEachStringCompletion,
        to container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        try container.encode(parameter, forKey: .parameter)
        try container.encode(count, forKey: .count)
        try encode(completion, to: &container)
    }

    fileprivate var facts: HeistStepFacts {
        switch self {
        case .action(_, let completion): completion.facts
        case .wait(_, _, let completion): completion.facts
        case .conditional(let completion): completion.facts
        case .forEachElement(_, _, _, let completion),
             .forEachElementIteration(_, _, _, let completion): completion.facts
        case .forEachString(_, _, let completion),
             .forEachStringIteration(_, _, let completion): completion.facts
        case .repeatUntil(_, _, let completion): completion.facts
        case .repeatUntilIteration(_, _, let completion): completion.facts
        case .invocation(_, _, let completion): completion.facts
        case .warning(_, .passed(let children)):
            .init(status: .passed, failure: nil, children: children.values, abortedAtChildPath: nil)
        case .warning(_, .skipped(let children)), .failure(_, .skipped(let children)):
            .init(status: .skipped, failure: nil, children: children.values, abortedAtChildPath: nil)
        case .failure(_, .failed(let failure, let children)):
            .init(status: .failed, failure: failure, children: children.values, abortedAtChildPath: nil)
        case .heist(_, .passed(let children)):
            .init(status: .passed, failure: nil, children: children.values, abortedAtChildPath: nil)
        case .heist(_, .childAborted(let failure, let children)):
            .init(
                status: .failed,
                failure: failure,
                children: children.values,
                abortedAtChildPath: children.abortedAtPath
            )
        case .heist(_, .skipped(let children)):
            .init(status: .skipped, failure: nil, children: children.values, abortedAtChildPath: nil)
        }
    }

    fileprivate static func actionCompletion(
        _ completion: HeistActionCompletion,
        matches command: HeistActionCommand
    ) -> Bool {
        let evidence: HeistActionEvidence?
        switch completion {
        case .passed(let admitted, _), .childAborted(let admitted, _, _):
            evidence = admitted.value
        case .failed(let admitted, _, _):
            evidence = admitted.value
        case .skipped:
            evidence = nil
        }
        return evidence?.matches(command: command) ?? true
    }

    fileprivate static func forEachStringCompletion(
        _ completion: HeistForEachStringCompletion,
        count: Int,
        isIteration: Bool
    ) -> Bool {
        guard count >= 0 else { return false }
        let evidence: HeistForEachStringEvidence?
        switch completion {
        case .passed(let admitted, _): evidence = admitted.value
        case .failed(let admitted, _, _): evidence = admitted.value?.value
        case .childAborted(let admitted, _, _): evidence = admitted.value
        case .skipped: evidence = nil
        }
        guard let evidence else { return true }
        guard evidence.iterationCount <= count else { return false }
        if isIteration {
            guard let ordinal = evidence.iterationOrdinal else { return false }
            return ordinal < count && ordinal < evidence.iterationCount
        }
        return evidence.iterationOrdinal == nil
    }

    fileprivate static func forEachElementCompletion(
        _ completion: HeistForEachElementCompletion,
        limit: Int,
        isIteration: Bool
    ) -> Bool {
        guard limit > 0 else { return false }
        let evidence: HeistForEachElementEvidence?
        switch completion {
        case .passed(let admitted, _): evidence = admitted.value
        case .failed(let admitted, _, _): evidence = admitted.value?.value
        case .childAborted(let admitted, _, _): evidence = admitted.value
        case .skipped: evidence = nil
        }
        guard let evidence else { return true }
        guard evidence.iterationCount <= evidence.matchedCount else { return false }
        if isIteration {
            guard let iterationOrdinal = evidence.iterationOrdinal,
                  let targetOrdinal = evidence.targetOrdinal else { return false }
            return iterationOrdinal < evidence.iterationCount && targetOrdinal < evidence.matchedCount
        }
        return evidence.iterationOrdinal == nil && evidence.targetOrdinal == nil
    }

    fileprivate static func repeatUntilCompletion(
        _ completion: HeistRepeatUntilCompletion,
        matches predicate: AccessibilityPredicate
    ) -> Bool {
        let evidence: HeistRepeatUntilEvidence?
        switch completion {
        case .passed(let admitted, _): evidence = admitted.value
        case .failed(let admitted, _, _): evidence = admitted.value?.value
        case .childAborted(let admitted, _, _): evidence = admitted.value
        case .skipped: evidence = nil
        }
        return repeatUntilEvidence(evidence, matches: predicate, isIteration: false)
    }

    fileprivate static func repeatUntilIterationCompletion(
        _ completion: HeistRepeatUntilIterationCompletion,
        matches predicate: AccessibilityPredicate
    ) -> Bool {
        let evidence: HeistRepeatUntilEvidence?
        switch completion {
        case .passed(let admitted, _): evidence = admitted.value
        case .failed(let admitted, _, _): evidence = admitted.value?.value
        case .childAborted(let admitted, _, _): evidence = admitted.value
        case .skipped: evidence = nil
        }
        return repeatUntilEvidence(evidence, matches: predicate, isIteration: true)
    }

    private static func repeatUntilEvidence(
        _ evidence: HeistRepeatUntilEvidence?,
        matches predicate: AccessibilityPredicate,
        isIteration: Bool
    ) -> Bool {
        guard let evidence else { return true }
        if let evidencePredicate = evidence.expectation.predicate,
           evidencePredicate != predicate { return false }
        if isIteration {
            guard let ordinal = evidence.iterationOrdinal else { return false }
            return ordinal < evidence.iterationCount
        }
        return evidence.iterationOrdinal == nil
    }
}

/// One semantic node in a heist execution receipt tree.
public struct HeistExecutionStepResult: Codable, Sendable, Equatable {
    public let path: HeistExecutionPath
    public let durationMs: Int
    let node: HeistExecutionStepNode

    private init(path: HeistExecutionPath, durationMs: Int, node: HeistExecutionStepNode) {
        self.path = path
        self.durationMs = durationMs
        self.node = node
    }

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

    package static func action(
        path: HeistExecutionPath, durationMs: Int, command: HeistActionCommand, completion: HeistActionCompletion
    ) -> Self {
        precondition(HeistExecutionStepNode.actionCompletion(completion, matches: command))
        return .init(path: path, durationMs: durationMs, node: .action(command: command, completion: completion))
    }

    package static func wait(
        path: HeistExecutionPath,
        durationMs: Int,
        predicate: AccessibilityPredicate,
        timeout: WaitTimeout,
        completion: HeistWaitCompletion
    ) -> Self {
        .init(path: path, durationMs: durationMs, node: .wait(predicate: predicate, timeout: timeout, completion: completion))
    }

    package static func conditional(
        path: HeistExecutionPath, durationMs: Int, completion: HeistCaseSelectionCompletion
    ) -> Self { .init(path: path, durationMs: durationMs, node: .conditional(completion: completion)) }

    package static func forEachElement(
        path: HeistExecutionPath,
        durationMs: Int,
        parameter: HeistReferenceName,
        matching: ElementPredicateTemplate,
        limit: Int,
        completion: HeistForEachElementCompletion
    ) -> Self {
        precondition(HeistExecutionStepNode.forEachElementCompletion(
            completion,
            limit: limit,
            isIteration: false
        ))
        return .init(
            path: path,
            durationMs: durationMs,
            node: .forEachElement(parameter: parameter, matching: matching, limit: limit, completion: completion)
        )
    }

    package static func forEachString(
        path: HeistExecutionPath,
        durationMs: Int,
        parameter: HeistReferenceName,
        count: Int,
        completion: HeistForEachStringCompletion
    ) -> Self {
        precondition(HeistExecutionStepNode.forEachStringCompletion(
            completion,
            count: count,
            isIteration: false
        ))
        return .init(path: path, durationMs: durationMs, node: .forEachString(parameter: parameter, count: count, completion: completion))
    }

    package static func forEachElementIteration(
        path: HeistExecutionPath,
        durationMs: Int,
        parameter: HeistReferenceName,
        matching: ElementPredicateTemplate,
        limit: Int,
        completion: HeistForEachElementCompletion
    ) -> Self {
        precondition(HeistExecutionStepNode.forEachElementCompletion(
            completion,
            limit: limit,
            isIteration: true
        ))
        return .init(
            path: path,
            durationMs: durationMs,
            node: .forEachElementIteration(parameter: parameter, matching: matching, limit: limit, completion: completion)
        )
    }

    package static func forEachStringIteration(
        path: HeistExecutionPath,
        durationMs: Int,
        parameter: HeistReferenceName,
        count: Int,
        completion: HeistForEachStringCompletion
    ) -> Self {
        precondition(HeistExecutionStepNode.forEachStringCompletion(
            completion,
            count: count,
            isIteration: true
        ))
        return .init(
            path: path,
            durationMs: durationMs,
            node: .forEachStringIteration(parameter: parameter, count: count, completion: completion)
        )
    }

    package static func repeatUntil(
        path: HeistExecutionPath,
        durationMs: Int,
        predicate: AccessibilityPredicate,
        timeout: WaitTimeout,
        completion: HeistRepeatUntilCompletion
    ) -> Self {
        precondition(HeistExecutionStepNode.repeatUntilCompletion(
            completion,
            matches: predicate
        ))
        return .init(
            path: path,
            durationMs: durationMs,
            node: .repeatUntil(predicate: predicate, timeout: timeout, completion: completion)
        )
    }

    package static func repeatUntilIteration(
        path: HeistExecutionPath,
        durationMs: Int,
        predicate: AccessibilityPredicate,
        timeout: WaitTimeout,
        completion: HeistRepeatUntilIterationCompletion
    ) -> Self {
        precondition(HeistExecutionStepNode.repeatUntilIterationCompletion(
            completion,
            matches: predicate
        ))
        return .init(
            path: path,
            durationMs: durationMs,
            node: .repeatUntilIteration(predicate: predicate, timeout: timeout, completion: completion)
        )
    }

    package static func warning(
        path: HeistExecutionPath, durationMs: Int, message: HeistWarningMessage, completion: HeistWarningCompletion
    ) -> Self { .init(path: path, durationMs: durationMs, node: .warning(message: message, completion: completion)) }

    package static func failure(
        path: HeistExecutionPath, durationMs: Int, message: HeistFailureMessage, completion: HeistFailureCompletion
    ) -> Self { .init(path: path, durationMs: durationMs, node: .failure(message: message, completion: completion)) }

    package static func heist(
        path: HeistExecutionPath, durationMs: Int, name: HeistPlanName?, completion: HeistGroupCompletion
    ) -> Self { .init(path: path, durationMs: durationMs, node: .heist(name: name, completion: completion)) }

    package static func invocation(
        path: HeistExecutionPath,
        durationMs: Int,
        invocationPath: HeistInvocationPath,
        argument: HeistArgument,
        completion: HeistInvocationCompletion
    ) -> Self {
        .init(
            path: path,
            durationMs: durationMs,
            node: .invocation(path: invocationPath, argument: argument, completion: completion)
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case path
        case durationMs
        case node
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist execution step result")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(HeistExecutionPath.self, forKey: .path)
        durationMs = try container.decode(Int.self, forKey: .durationMs)
        node = try container.decode(HeistExecutionStepNode.self, forKey: .node)
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
        case .forEachString(_, _, let value), .forEachStringIteration(_, _, let value): completion = value
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
        case .forEachElement(_, _, _, let value), .forEachElementIteration(_, _, _, let value): completion = value
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
        case .repeatUntil(_, _, let completion):
            switch completion {
            case .passed(let evidence, _): return evidence.value
            case .failed(let evidence, _, _): return evidence.value?.value
            case .childAborted(let evidence, _, _): return evidence.value
            case .skipped: return nil
            }
        case .repeatUntilIteration(_, _, let completion):
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
