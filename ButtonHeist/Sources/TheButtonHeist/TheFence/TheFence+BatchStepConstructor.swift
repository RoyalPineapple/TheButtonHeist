import Foundation

import TheScore

extension TheFence {

    struct BatchStepPlanBuildError: Error {
        let message: String
    }

    @ButtonHeistActor
    struct BatchStepConstructor {
        private let actionConstructor: BatchActionConstructor

        init(fence: TheFence) {
            actionConstructor = BatchActionConstructor(targetResolver: BatchTargetResolver(fence: fence))
        }

        func plan(
            index: Int,
            operation: NormalizedOperation,
            request: ParsedRequest
        ) throws -> RunBatchPreparedStep {
            let context = BatchStepPlanningContext(originalIndex: index, operation: operation, request: request)
            return try context.plan(actionConstructor.construct(context: context))
        }
    }
}
