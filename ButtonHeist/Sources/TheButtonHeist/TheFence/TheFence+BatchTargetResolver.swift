import Foundation

import TheScore

extension TheFence {

    @ButtonHeistActor
    struct BatchTargetResolver {
        private let fence: TheFence

        init(fence: TheFence) {
            self.fence = fence
        }

        func executionTarget(
            from operation: NormalizedOperation,
            fallback target: ElementTarget?
        ) -> BatchExecutionTarget? {
            let argumentTarget = targetFromArguments(operation.arguments)
            if argumentTarget != nil { return argumentTarget }
            return targetFromElementTarget(target)
        }

        func optionalTarget(
            from operation: NormalizedOperation,
            fallback target: ElementTarget?
        ) throws -> BatchExecutionTarget? {
            try optionalExecutionTarget(executionTarget(from: operation, fallback: target))
        }

        func requiredTarget(
            from operation: NormalizedOperation,
            fallback target: ElementTarget?
        ) throws -> BatchExecutionTarget {
            try requiredExecutionTarget(executionTarget(from: operation, fallback: target))
        }

        func optionalExecutionTarget(_ target: BatchExecutionTarget?) throws -> BatchExecutionTarget? {
            guard let target else { return nil }
            return try executionTarget(target)
        }

        func requiredExecutionTarget(_ target: BatchExecutionTarget?) throws -> BatchExecutionTarget {
            guard let target else {
                throw BatchStepPlanBuildError(message: "typed batch target requires matcher predicates or ordinal fallback")
            }
            return try executionTarget(target)
        }

        func waitExpectation(
            target: BatchExecutionTarget?,
            absent: Bool?
        ) throws -> ActionExpectation {
            let matcher = try expectationMatcher(target)
            if absent == true {
                return .elementDisappeared(matcher)
            }
            return .elementAppeared(matcher)
        }

        private func expectationMatcher(_ target: BatchExecutionTarget?) throws -> ElementMatcher {
            guard let target else {
                throw BatchStepPlanBuildError(message: "typed batch expectation requires matcher predicates")
            }
            guard target.matcher.hasPredicates else {
                if let sourceHeistId = target.sourceHeistId {
                    throw BatchStepPlanBuildError(
                        message: "run_batch target \"\(sourceHeistId)\" needs matcher predicates for typed batch expectation; heistId is source metadata only"
                    )
                }
                throw BatchStepPlanBuildError(
                    message: "typed batch expectation requires matcher predicates"
                )
            }
            return target.matcher
        }

        private func executionTarget(_ target: BatchExecutionTarget) throws -> BatchExecutionTarget {
            guard target.matcher.hasPredicates || target.ordinal != nil else {
                if let sourceHeistId = target.sourceHeistId {
                    throw BatchStepPlanBuildError(
                        message: "run_batch target \"\(sourceHeistId)\" needs matcher predicates or ordinal fallback; heistId is source metadata only"
                    )
                }
                throw BatchStepPlanBuildError(
                    message: "typed batch target requires matcher predicates or ordinal fallback; heistId is source metadata only"
                )
            }
            return target
        }

        private func targetFromArguments(_ arguments: [String: Any]) -> BatchExecutionTarget? {
            let sourceHeistId = try? arguments.schemaString("heistId")
            let ordinal = try? arguments.schemaInteger("ordinal")
            let parsedMatcher = (try? fence.elementMatcher(arguments)) ?? ElementMatcher()
            let matcher = ElementMatcher(
                label: parsedMatcher.label,
                identifier: parsedMatcher.identifier,
                value: parsedMatcher.value,
                traits: parsedMatcher.traits,
                excludeTraits: parsedMatcher.excludeTraits
            )
            guard sourceHeistId != nil || matcher.hasPredicates || ordinal != nil else { return nil }
            return BatchExecutionTarget(sourceHeistId: sourceHeistId, matcher: matcher, ordinal: ordinal)
        }

        private func targetFromElementTarget(_ target: ElementTarget?) -> BatchExecutionTarget? {
            guard let target else { return nil }
            switch target {
            case .heistId(let heistId):
                return BatchExecutionTarget(sourceHeistId: heistId, matcher: ElementMatcher())
            case .matcher(let matcher, let ordinal):
                return BatchExecutionTarget(matcher: matcher, ordinal: ordinal)
            }
        }
    }
}
