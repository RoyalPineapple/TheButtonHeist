import Foundation
import TheScore

extension TheFence {

    /// Connect to a device and optionally enable auto-reconnect.
    public func start() async throws {
        if handoff.connectionLifecycle.isConnected {
            return
        }

        try await connect()
        if config.autoReconnect {
            let filter = config.deviceFilter ?? EnvironmentKey.buttonheistDevice.value
            handoff.setupAutoReconnect(filter: filter)
        }
    }

    /// Disconnect and cancel all pending requests.
    public func stop() {
        clearClientSessionState(
            error: FenceError.connectionFailure(ConnectionFailure(disconnectReason: .localDisconnect))
        )
        handoff.disableAutoReconnect()
        handoff.disconnect()
        handoff.stopDiscovery()
    }

    func handleHandoffConnectionStateChanged(_ state: HandoffConnectionPhase) {
        switch state {
        case .failed(let failure):
            clearClientSessionState(error: sessionStateError(for: failure))
        case .disconnected:
            guard let failure = handoff.connectionLifecycle.diagnosticFailure,
                  case .disconnected = failure
            else { return }
            clearClientSessionState(error: sessionStateError(for: failure))
        case .reconnecting, .connecting, .connected:
            break
        }
    }

    func clearClientSessionState(error: Error) {
        cancelAllPendingRequests(error: error)
    }

    private func sessionStateError(for failure: HandoffConnectionError) -> Error {
        if case .disconnected(let reason) = failure {
            return FenceError.connectionFailure(ConnectionFailure(disconnectReason: reason))
        }
        return FenceError(failure)
    }

    private func connect() async throws {
        if let directDevice = config.directDevice {
            try await connectDirect(to: directDevice)
            return
        }
        let filter = config.deviceFilter ?? EnvironmentKey.buttonheistDevice.value
        do {
            try await handoff.connectWithDiscovery(
                filter: filter,
                timeout: config.connectionTimeout
            )
        } catch let error as HandoffConnectionError {
            throw FenceError(error)
        }
    }

    private func connectDirect(to device: DiscoveredDevice) async throws {
        handoff.onStatus?("Connecting to \(device.name)...")
        let resolutionTimeout = TheHandoff.connectionResolutionTimeout(for: config.connectionTimeout)
        switch await device.reachability(
            token: handoff.serverMessageRouter.authToken,
            timeout: resolutionTimeout
        ) {
        case .reachable:
            break
        case .failed(let reason):
            throw FenceError(HandoffConnectionError.disconnected(reason))
        case .unavailable:
            let details = FailureDetails(
                code: .connectionEndpointUnreachable,
                hint: "Check that the app is running at \(device.name), then retry the command."
            )
            throw FenceError.connectionFailure(ConnectionFailure(
                message: "Could not reach ButtonHeist server at \(device.name)",
                failureCode: details.code,
                hint: details.hint
            ))
        }

        let attemptID = handoff.connect(to: device)
        do {
            try await handoff.waitForConnectionResult(timeout: config.connectionTimeout)
        } catch let error as HandoffConnectionError where error == .timeout {
            handoff.abortConnectionAttempt(attemptID, failure: .timeout)
            throw FenceError(error)
        } catch let error as HandoffConnectionError {
            throw FenceError(error)
        }
        handoff.onStatus?("Connected to \(device.name)")
    }
}
