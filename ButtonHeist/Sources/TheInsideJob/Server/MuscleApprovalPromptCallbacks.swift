#if canImport(UIKit)
#if DEBUG
import Foundation

@MainActor
final class MuscleApprovalPromptCallbacks {

    private let alerts: AlertPresenter
    private let tasks = TaskTracker()

    init(alerts: AlertPresenter) {
        self.alerts = alerts
    }

    func show(
        clientId: Int,
        onAllow: @escaping @Sendable () async -> Void,
        onDeny: @escaping @Sendable () async -> Void
    ) {
        alerts.presentApproval(
            clientId: clientId,
            onAllow: { [weak self] in
                self?.schedule(onAllow)
            },
            onDeny: { [weak self] in
                self?.schedule(onDeny)
            }
        )
    }

    func dismiss() {
        alerts.dismiss()
    }

    func cancelAll() {
        tasks.cancelAll()
    }

    private func schedule(_ body: @escaping @Sendable () async -> Void) {
        let task = Task {
            await body()
        }
        record(task)
    }

    private func record(_ task: Task<Void, Never>) {
        tasks.record(task)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
