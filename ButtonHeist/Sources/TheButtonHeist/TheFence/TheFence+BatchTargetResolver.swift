import Foundation

import TheScore

extension TheFence {

    @ButtonHeistActor
    struct BatchTargetResolver {
        func executionTarget(
            from request: ParsedRequest,
            commandTarget target: ElementTarget?
        ) -> BatchExecutionTarget? {
            let argumentTarget = request.routedBatchTarget
            if argumentTarget != nil { return argumentTarget }
            return targetFromElementTarget(target)
        }

        func optionalTarget(
            from request: ParsedRequest,
            commandTarget target: ElementTarget?
        ) throws -> BatchExecutionTarget? {
            try optionalExecutionTarget(executionTarget(from: request, commandTarget: target))
        }

        func requiredTarget(
            from request: ParsedRequest,
            commandTarget target: ElementTarget?
        ) throws -> BatchExecutionTarget {
            try requiredExecutionTarget(executionTarget(from: request, commandTarget: target))
        }

        func optionalExecutionTarget(_ target: BatchExecutionTarget?) throws -> BatchExecutionTarget? {
            guard let target else { return nil }
            return try executionTarget(target)
        }

        func requiredExecutionTarget(_ target: BatchExecutionTarget?) throws -> BatchExecutionTarget {
            guard let target else {
                throw BatchStepPlanBuildError(message: "typed batch target requires matcher predicates or an ordinal selector")
            }
            return try executionTarget(target)
        }

        private func executionTarget(_ target: BatchExecutionTarget) throws -> BatchExecutionTarget {
            guard target.matcher.hasPredicates || target.ordinal != nil else {
                if let sourceHeistId = target.sourceHeistId {
                    throw BatchStepPlanBuildError(
                        message: "run_batch target \"\(sourceHeistId)\" needs matcher predicates or an ordinal selector; heistId is source metadata only"
                    )
                }
                throw BatchStepPlanBuildError(
                    message: "typed batch target requires matcher predicates or an ordinal selector; heistId is source metadata only"
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
