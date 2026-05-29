import Foundation

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
        let device: DiscoveredDevice
        do {
            device = try await resolveReachableDevice(
                filter: filter,
                discoveryTimeout: discoveryTimeout,
                reachabilityTimeout: resolutionTimeout
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
        connectionLifecycle.setupAutoReconnect(filter: filter)
    }

    func scheduleAutoReconnectIfNeeded(disconnectedDevice: DiscoveredDevice) {
        connectionLifecycle.scheduleAutoReconnectIfNeeded(
            disconnectedDevice: disconnectedDevice,
            policy: autoReconnectRecoveryPolicy,
            attemptTimeout: reconnectAttemptTimeout,
            runtime: self
        )
    }

    func publishReconnectStatus(_ message: String) {
        onStatus?(message)
    }

    func connectForAutoReconnect(to device: DiscoveredDevice) -> UUID {
        closeConnection()
        return openConnection(to: device)
    }

    func waitForAutoReconnectResult(timeout: TimeInterval) async throws {
        try await waitForConnectionResult(timeout: timeout)
    }

    func disconnectAutoReconnectAttempt(_ attemptID: UUID, failure: HandoffConnectionError) {
        abortConnectionAttempt(attemptID, failure: failure)
    }

    /// Compute display name with disambiguation when multiple devices have the same app.
    func displayName(for device: DiscoveredDevice) -> String {
        let appName = device.appName
        let deviceSuffix = device.deviceName.isEmpty ? "" : " (\(device.deviceName))"
        let sameAppDevices = discoveredDevices.filter { $0.appName == appName }

        guard sameAppDevices.count > 1 else { return appName }

        let sameAppAndDevice = sameAppDevices.filter { $0.deviceName == device.deviceName }
        if sameAppAndDevice.count > 1, let shortId = device.shortId {
            return "\(appName)\(deviceSuffix) [\(shortId)]"
        }
        return "\(appName)\(deviceSuffix)"
    }

    private func resolveReachableDevice(
        filter: String?,
        discoveryTimeout: UInt64,
        reachabilityTimeout: TimeInterval
    ) async throws -> DiscoveredDevice {
        let resolver = DeviceResolver(
            filter: filter,
            discoveryTimeout: discoveryTimeout,
            reachabilityTimeout: reachabilityTimeout,
            getDiscoveredDevices: { [weak self] in self?.discoveredDevices ?? [] }
        )
        return try await resolver.resolve()
    }
}
