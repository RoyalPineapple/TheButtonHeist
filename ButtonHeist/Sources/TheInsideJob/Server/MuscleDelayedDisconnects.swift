#if canImport(UIKit)
#if DEBUG
import Foundation
import ButtonHeistSupport

final class MuscleDelayedDisconnects {

    private let gracePeriod: Duration
    private let tasks = TaskTracker()

    init(gracePeriod: Duration) {
        self.gracePeriod = gracePeriod
    }

    var taskCountForTesting: Int {
        tasks.taskCountForTesting
    }

    func schedule(clientId: Int, disconnect: @escaping @Sendable () async -> Void) {
        let gracePeriod = gracePeriod
        tasks.spawn {
            guard await Task.cancellableSleep(for: gracePeriod) else { return }
            await disconnect()
        }
    }

    func cancelAll() {
        tasks.cancelAll()
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
