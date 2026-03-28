import Foundation
import os
import ButtonHeist

@ButtonHeistActor
final class DeviceConnector {
    let handoff = TheHandoff()
    private let deviceFilter: String?
    private let quiet: Bool
    private let discoveryTimeout: UInt64
    private let connectionTimeout: UInt64

    init(deviceFilter: String?,
         token: String? = nil, quiet: Bool = false,
         discoveryTimeout: TimeInterval = 5, connectionTimeout: TimeInterval = 5) {
        self.deviceFilter = deviceFilter
            ?? EnvironmentKey.buttonheistDevice.value
        self.quiet = quiet
        self.discoveryTimeout = UInt64(discoveryTimeout * 1_000_000_000)
        self.connectionTimeout = UInt64(connectionTimeout * 1_000_000_000)
        self.handoff.token = token ?? EnvironmentKey.buttonheistToken.value
        self.handoff.driverId = EnvironmentKey.buttonheistDriverId.value
        self.handoff.autoSubscribe = false
    }

    /// Connect to a device via Bonjour discovery.
    func connect() async throws {
        if !quiet { logStatus("Searching for iOS devices...") }
        handoff.startDiscovery()

        let device = try await resolveReachableDevice()

        if !quiet {
            logStatus("Found: \(handoff.displayName(for: device))")
        }

        try await connectToDevice(device)
    }

    func disconnect() {
        handoff.disconnect()
        handoff.stopDiscovery()
    }

    // MARK: - Commands (delegated to handoff)

    func send(_ message: ClientMessage) {
        handoff.send(message)
    }

    func requestInterface() {
        handoff.send(.requestInterface)
    }

    func waitForActionResult(timeout: TimeInterval) async throws -> ActionResult {
        try await waitForResponse(timeout: timeout) { complete in
            handoff.onActionResult = { result, _ in complete(.success(result)) }
        }
    }

    func waitForInterface(timeout: TimeInterval = 10.0) async throws -> Interface {
        try await waitForResponse(timeout: timeout) { complete in
            handoff.onInterface = { payload, _ in complete(.success(payload)) }
        }
    }

    func waitForScreen(timeout: TimeInterval = 30.0) async throws -> ScreenPayload {
        try await waitForResponse(timeout: timeout) { complete in
            handoff.onScreen = { payload, _ in complete(.success(payload)) }
        }
    }

    func waitForRecording(timeout: TimeInterval = 120.0) async throws -> RecordingPayload {
        try await waitForResponse(timeout: timeout) { complete in
            handoff.onRecording = { complete(.success($0)) }
            handoff.onRecordingError = { complete(.failure(FenceError.actionFailed($0))) }
        }
    }

    private func waitForResponse<T: Sendable>(
        timeout: TimeInterval,
        install: (@escaping @Sendable (Result<T, Error>) -> Void) -> Void
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let didResume = OSAllocatedUnfairLock(initialState: false)

            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                let shouldResume = didResume.withLock { flag -> Bool in
                    guard !flag else { return false }
                    flag = true
                    return true
                }
                if shouldResume {
                    continuation.resume(throwing: FenceError.actionTimeout)
                }
            }

            install { result in
                let shouldResume = didResume.withLock { flag -> Bool in
                    guard !flag else { return false }
                    flag = true
                    return true
                }
                if shouldResume {
                    timeoutTask.cancel()
                    continuation.resume(with: result)
                }
            }
        }
    }

    // MARK: - Private

    private func resolveReachableDevice() async throws -> DiscoveredDevice {
        let resolver = DeviceResolver(
            filter: deviceFilter,
            discoveryTimeout: discoveryTimeout,
            getDiscoveredDevices: { [handoff] in handoff.discoveredDevices }
        )
        do {
            return try await resolver.resolve()
        } catch let error as DeviceResolver.ResolutionError {
            switch error {
            case .noDeviceFound:
                throw FenceError.noDeviceFound
            case .noMatchingDevice(let filter, let available):
                throw FenceError.noMatchingDevice(filter: filter, available: available)
            }
        }
    }

    private func connectToDevice(_ device: DiscoveredDevice) async throws {
        if !quiet { logStatus("Connecting...") }

        var connected = false
        var connectionError: Error?
        handoff.onConnected = { _ in connected = true }
        handoff.onDisconnected = { reason in if connectionError == nil { connectionError = reason } }
        // Intentional: print the token so anyone with debug console access can reconnect.
        // This is a dev tool — if you can see the console, you already have full access.
        handoff.onAuthApproved = { token in
            if let token {
                logStatus("BUTTONHEIST_TOKEN=\(token)")
            }
        }
        handoff.onAuthFailed = { reason in
            connectionError = FenceError.authFailed(reason)
        }
        handoff.onSessionLocked = { payload in
            connectionError = FenceError.sessionLocked(payload.message)
        }
        handoff.connect(to: device)

        let connStart = DispatchTime.now()
        while !connected && connectionError == nil {
            if DispatchTime.now().uptimeNanoseconds - connStart.uptimeNanoseconds > connectionTimeout {
                throw FenceError.connectionTimeout
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        if let error = connectionError {
            throw error
        }

        if !quiet { logStatus("Connected") }
    }
}
