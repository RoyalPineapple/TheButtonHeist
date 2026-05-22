import Foundation

import TheScore

extension TheFence {

    @ButtonHeistActor
    struct BatchTargetResolver {
        func executionTarget(
            from request: ParsedRequest,
            fallback target: ElementTarget?
        ) -> BatchExecutionTarget? {
            let argumentTarget = request.routedBatchTarget
            if argumentTarget != nil { return argumentTarget }
            return targetFromElementTarget(target)
        }

        func optionalTarget(
            from request: ParsedRequest,
            fallback target: ElementTarget?
        ) throws -> BatchExecutionTarget? {
            try optionalExecutionTarget(executionTarget(from: request, fallback: target))
        }

        func requiredTarget(
            from request: ParsedRequest,
            fallback target: ElementTarget?
        ) throws -> BatchExecutionTarget {
            try requiredExecutionTarget(executionTarget(from: request, fallback: target))
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
