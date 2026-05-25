import Foundation

import TheScore

extension TheFence {

    @ButtonHeistActor
    struct BatchTargetResolver {
        func semanticTarget(
            from request: ParsedRequest,
            requestElementTarget target: ElementTarget?
        ) -> SemanticActionTarget? {
            let argumentTarget = request.routedSemanticTarget
            if argumentTarget != nil { return argumentTarget }
            return targetFromElementTarget(target)
        }

        func optionalTarget(
            from request: ParsedRequest,
            requestElementTarget target: ElementTarget?
        ) throws -> SemanticActionTarget? {
            try optionalSemanticTarget(semanticTarget(from: request, requestElementTarget: target))
        }

        func requiredTarget(
            from request: ParsedRequest,
            requestElementTarget target: ElementTarget?
        ) throws -> SemanticActionTarget {
            try requiredSemanticTarget(semanticTarget(from: request, requestElementTarget: target))
        }

        func optionalSemanticTarget(_ target: SemanticActionTarget?) throws -> SemanticActionTarget? {
            guard let target else { return nil }
            return try semanticTarget(target)
        }

        func requiredSemanticTarget(_ target: SemanticActionTarget?) throws -> SemanticActionTarget {
            guard let target else {
                throw BatchStepPlanBuildError(message: "semantic action target requires matcher predicates or an ordinal selector")
            }
            return try semanticTarget(target)
        }

        private func semanticTarget(_ target: SemanticActionTarget) throws -> SemanticActionTarget {
            guard target.matcher.hasPredicates || target.ordinal != nil else {
                if let sourceHeistId = target.sourceHeistId {
                    throw BatchStepPlanBuildError(
                        message: "run_batch target \"\(sourceHeistId)\" needs matcher predicates or an ordinal selector; heistId is source metadata only"
                    )
                }
                throw BatchStepPlanBuildError(
                    message: "semantic action target requires matcher predicates or an ordinal selector; heistId is source metadata only"
                )
            }
            return target
        }

        private func targetFromElementTarget(_ target: ElementTarget?) -> SemanticActionTarget? {
            guard let target else { return nil }
            switch target {
            case .heistId(let heistId):
                return SemanticActionTarget(sourceHeistId: heistId, matcher: ElementMatcher())
            case .matcher(let matcher, let ordinal):
                return SemanticActionTarget(matcher: matcher, ordinal: ordinal)
            }
        }
    }
}
