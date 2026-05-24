import Foundation

@ButtonHeistActor
protocol HandoffReconnectRuntime: AnyObject {
    var discoveredDevices: [DiscoveredDevice] { get }
    var isConnected: Bool { get }

    func publishReconnectStatus(_ message: String)
    func connectForAutoReconnect(to device: DiscoveredDevice) -> UUID
    func waitForAutoReconnectResult(timeout: TimeInterval) async throws
    func disconnectAutoReconnectAttempt(_ attemptID: UUID, failure: HandoffConnectionError)
    func failAutoReconnect(_ failure: HandoffConnectionError)
}

/// Auto-reconnect lifecycle owner: disabled, armed, or running for exactly one selected target.
@ButtonHeistActor
final class HandoffReconnectController {
    private enum Phase {
        case disabled
        case armed(filter: String?, target: HandoffReconnectTarget?)
        case running(filter: String?, target: HandoffReconnectTarget, task: Task<Void, Never>)
    }

    private var phase: Phase = .disabled

    func setup(filter: String?) {
        switch phase {
        case .disabled:
            phase = .armed(filter: filter, target: nil)
        case .armed(let currentFilter, _):
            guard currentFilter != filter else { return }
            phase = .armed(filter: filter, target: nil)
        case .running(let currentFilter, _, let task):
            guard currentFilter != filter else { return }
            task.cancel()
            phase = .armed(filter: filter, target: nil)
        }
    }

    func disable() {
        if case .running(_, _, let task) = phase {
            task.cancel()
        }
        phase = .disabled
    }

    func cancelRunnerAndClearTarget() {
        switch phase {
        case .disabled:
            return
        case .armed(let filter, _):
            phase = .armed(filter: filter, target: nil)
        case .running(let filter, _, let task):
            task.cancel()
            phase = .armed(filter: filter, target: nil)
        }
    }

    func scheduleIfNeeded(
        disconnectedDevice: DiscoveredDevice,
        policy: AutoReconnectRecoveryPolicy,
        attemptTimeout: TimeInterval,
        runtime: any HandoffReconnectRuntime
    ) {
        guard case .armed(let filter, let existingTarget) = phase else { return }

        let target = existingTarget ?? HandoffReconnectTarget(filter: filter, device: disconnectedDevice)
        let reconnectTask = Task<Void, Never> { @ButtonHeistActor [weak self, weak runtime] in
            guard let self, let runtime else { return }
            await self.run(
                target: target,
                policy: policy,
                attemptTimeout: attemptTimeout,
                runtime: runtime
            )
        }
        phase = .running(filter: filter, target: target, task: reconnectTask)
    }

    private func run(
        target: HandoffReconnectTarget,
        policy: AutoReconnectRecoveryPolicy,
        attemptTimeout: TimeInterval,
        runtime: any HandoffReconnectRuntime
    ) async {
        runtime.publishReconnectStatus("Device disconnected — watching for reconnection...")
        var consecutiveMisses = 0

        for _ in policy.attempts {
            guard !Task.isCancelled else { return }
            guard isCurrentRunningTarget(target) else { return }

            let sleepDuration = policy.sleepDuration(afterConsecutiveDiscoveryMisses: consecutiveMisses)
            guard await Task.cancellableSleep(for: .seconds(sleepDuration)) else { return }
            guard !Task.isCancelled else { return }
            guard isCurrentRunningTarget(target) else { return }

            if let device = target.resolve(from: runtime.discoveredDevices) {
                consecutiveMisses = 0
                runtime.publishReconnectStatus("Reconnecting to \(device.name)...")
                let attemptID = runtime.connectForAutoReconnect(to: device)
                do {
                    try await runtime.waitForAutoReconnectResult(timeout: attemptTimeout)
                } catch let error as HandoffConnectionError where error == .timeout {
                    runtime.disconnectAutoReconnectAttempt(attemptID, failure: .timeout)
                } catch is CancellationError {
                    return
                } catch {
                    // The connection event already moved the phase; continue bounded retries.
                }
                if Task.isCancelled { return }
                if runtime.isConnected {
                    runtime.publishReconnectStatus("Reconnected to \(device.name)")
                    complete(target)
                    return
                }
            } else {
                consecutiveMisses += 1
            }
        }

        let failure = policy.terminalFailure(targetDisplayName: target.displayName)
        runtime.publishReconnectStatus(failure.errorDescription ?? "Auto-reconnect gave up")
        guard isCurrentRunningTarget(target) else { return }
        phase = .disabled
        runtime.failAutoReconnect(failure)
    }

    private func isCurrentRunningTarget(_ target: HandoffReconnectTarget) -> Bool {
        guard case .running(_, let currentTarget, _) = phase else { return false }
        return currentTarget == target
    }

    private func complete(_ target: HandoffReconnectTarget) {
        guard isCurrentRunningTarget(target) else { return }
        phase = .armed(filter: target.filter, target: target)
    }
}
