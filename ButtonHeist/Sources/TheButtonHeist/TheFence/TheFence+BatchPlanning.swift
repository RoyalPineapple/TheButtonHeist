import Foundation

import TheScore

extension TheFence {

    struct RunBatchRequest {
        let steps: [RunBatchPreparedStep]
        let policy: BatchExecutionPolicy
    }
}
