#if canImport(UIKit)
#if DEBUG
import Foundation
import ButtonHeistSupport

final class MuscleAuthenticationDeadlines {

    private let deadline: Duration
    private var tasks: [Int: Task<Void, Never>] = [:]

    init(deadline: Duration) {
        self.deadline = deadline
    }

    func replace(for clientId: Int, onExpired: @escaping @Sendable () async -> Void) {
        cancel(clientId)
        let deadline = deadline
        tasks[clientId] = Task {
            guard await Task.cancellableSleep(for: deadline) else { return }
            await onExpired()
        }
    }

    func cancel(_ clientId: Int) {
        tasks.removeValue(forKey: clientId)?.cancel()
    }

    func cancelAll() {
        for task in tasks.values {
            task.cancel()
        }
        tasks.removeAll()
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
