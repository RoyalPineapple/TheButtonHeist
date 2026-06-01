import Foundation

import TheScore

extension TheFence {
    struct HeistPlaybackContract {
        let plan: HeistPlan
    }

    @ButtonHeistActor
    func readHeistPlayback(contentsOf url: URL) throws -> HeistPlaybackContract {
        do {
            return try validateHeistPlayback(HeistStore.readHeist(from: url))
        } catch StorageError.heistRecording(.heistReadFailed(_, let reason))
            where reason.contains("Unsupported heist plan version") {
            throw FenceError.invalidRequest(reason)
        }
    }

    @ButtonHeistActor
    func validateHeistPlayback(_ plan: HeistPlan) throws -> HeistPlaybackContract {
        HeistPlaybackContract(plan: plan)
    }
}
