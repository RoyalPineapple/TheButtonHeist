import Foundation
import ButtonHeistSupport

@ButtonHeistActor
extension TheHandoff {

    /// Discover a device (optionally matching a filter) and connect to it.
    /// Starts discovery if not already active, polls until a matching device appears
    /// or the bounded resolution window expires. Suspends on
    /// `waitForConnectionResult` for the connection outcome.
    func connectWithDiscovery(
        filter: String?,
        timeout: TimeInterval = 30
    ) async throws {
        disconnectForReplacement()
        onStatus?("Searching for iOS devices...")
        let startedDiscovery = !hasActiveDiscoverySession
        if startedDiscovery { startDiscovery() }

        let resolutionTimeout = Self.connectionResolutionTimeout(for: timeout)
        let discoveryTimeout = UInt64(resolutionTimeout * 1_000_000_000)
        let target = DeviceResolutionTarget(filter: filter)
        let device: DiscoveredDevice
        do {
            device = try await resolveTargetDevice(
                target: target,
                discoveryTimeout: discoveryTimeout
            )
        } catch {
            if startedDiscovery { stopDiscovery() }
            if let connectionError = error as? HandoffConnectionError {
                connectionLifecycle.recordAttemptFailure(connectionError)
            }
            throw error
        }

        onStatus?("Found: \(displayName(for: device))")
        onStatus?("Connecting...")

        let attemptID = connect(to: device)
        do {
            try await waitForConnectionResult(timeout: timeout)
        } catch let error as HandoffConnectionError where error == .timeout {
            abortConnectionAttempt(attemptID, failure: .timeout)
            throw error
        }
        onStatus?("Connected to \(displayName(for: device))")
    }

    static func connectionResolutionTimeout(for timeout: TimeInterval) -> TimeInterval {
        min(max(timeout, 0.05), 2.0)
    }

    func setupAutoReconnect(filter: String?) {
        _ = connectionLifecycle.setup(filter: filter)
    }

    func scheduleAutoReconnectIfNeeded(disconnectedDevice: DiscoveredDevice) {
        guard let target = connectionLifecycle.targetForDisconnectedDevice(disconnectedDevice) else { return }
        guard connectionLifecycle.run(
            target: target,
            operation: { [weak self] run in
                await self?.runAutoReconnect(run: run)
            }
        ) != nil else { return }
    }

    /// Compute display name with disambiguation when multiple devices have the same app.
    func displayName(for device: DiscoveredDevice) -> String {
        device.displayName(among: discoveredDevices)
    }

    private func resolveTargetDevice(
        target: DeviceResolutionTarget,
        discoveryTimeout: UInt64
    ) async throws -> DiscoveredDevice {
        let resolver = DeviceResolver(
            target: target,
            discoveryTimeout: discoveryTimeout,
            getDiscoveredDevices: { [weak self] in self?.discoveredDevices ?? [] }
        )
        return try await resolver.resolve()
    }

    private func runAutoReconnect(run: HandoffReconnectRunContext) async {
        let target = run.target
        let policy = autoReconnectRecoveryPolicy
        onStatus?("Device disconnected — watching for reconnection...")

        for _ in policy.attempts {
            guard connectionLifecycle.isCurrentRun(run) else { return }
            connectionLifecycle.markReconnecting(target: target, runID: run.id)

            let sleepDuration = policy.sleepDuration(afterConsecutiveDiscoveryMisses: 0)
            guard await reconnectSleeper(sleepDuration) else { return }
            guard connectionLifecycle.isCurrentRun(run) else { return }

            let device = target.device
            onStatus?("Reconnecting to \(device.name)...")
            closeConnection()
            let attemptID = openConnection(to: device)
            do {
                try await waitForConnectionResult(timeout: reconnectAttemptTimeout)
            } catch let error as HandoffConnectionError where error == .timeout {
                abortConnectionAttempt(attemptID, failure: .timeout)
            } catch is CancellationError {
                return
            } catch {
                // The connection phase already recorded the attempt failure; keep retrying until the bounded policy expires.
            }

            guard connectionLifecycle.isCurrentRun(run) else { return }
            if isConnected {
                guard connectionLifecycle.finishSuccess(run) else { return }
                onStatus?("Reconnected to \(device.name)")
                return
            }
        }

        let failure = policy.terminalFailure(targetDisplayName: target.device.name)
        onStatus?(failure.errorDescription ?? "Auto-reconnect gave up")
        _ = connectionLifecycle.finishFailure(run, failure: failure)
    }
}
