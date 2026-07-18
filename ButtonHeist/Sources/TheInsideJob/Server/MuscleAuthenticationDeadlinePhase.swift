#if canImport(UIKit)
#if DEBUG
import TheScore
import ButtonHeistSupport

extension ClientAdmission.Timeout {
    static func effects(
        clientId: Int,
        state: ClientAdmission.Authentication.State?,
        timeoutSeconds: UInt64
    ) -> [ClientAdmission.Effect] {
        guard let state, !state.isAuthenticated else { return [] }

        let message: ServerErrorMessage
        do {
            message = try ServerErrorMessage(
                validating: "Authentication timed out after \(timeoutSeconds) seconds."
            )
        } catch {
            return [
                .log(.authenticationTimeout(clientId: clientId, timeoutSeconds: timeoutSeconds)),
                .delayedDisconnect(clientId: clientId),
            ]
        }
        let error = ServerError(kind: .authFailure, message: message)

        return [
            .log(.authenticationTimeout(clientId: clientId, timeoutSeconds: timeoutSeconds)),
            .sendClient(.error(error), requestId: nil, clientId: clientId),
            .delayedDisconnect(clientId: clientId),
        ]
    }

    final class Deadlines {
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
}
#endif // DEBUG
#endif // canImport(UIKit)
