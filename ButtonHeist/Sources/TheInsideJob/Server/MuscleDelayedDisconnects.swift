#if canImport(UIKit)
#if DEBUG
import Foundation
import ButtonHeistSupport

extension ClientAdmission {
final class DelayedDisconnects: Sendable {

    private let gracePeriod: Duration
    private let tasks = TaskTracker()

    init(gracePeriod: Duration) {
        self.gracePeriod = gracePeriod
    }

    var taskCountForTesting: Int {
        tasks.snapshot.taskCount
    }

    func schedule(clientId: Int, disconnect: @escaping @Sendable () async -> Void) {
        let gracePeriod = gracePeriod
        tasks.spawn {
            guard await Task.cancellableSleep(for: gracePeriod) else { return }
            await disconnect()
        }
    }

    func drain() async {
        await tasks.drain()
    }
}
}

#endif // DEBUG
#endif // canImport(UIKit)
