import Foundation

import TheScore

extension TheFence {

    struct BatchStepPlanBuildError: Error {
        let message: String
    }

    @ButtonHeistActor
    struct BatchStepConstructor {
        private let actionConstructor: BatchActionConstructor

        init() {
            actionConstructor = BatchActionConstructor()
        }

        func plan(
            index: Int,
            request: ParsedRequest
        ) throws -> RunBatchPreparedStep {
            let context = BatchStepPlanningContext(originalIndex: index, request: request)
            return try context.plan(actionConstructor.construct(context: context))
        }
    }
}
