import Foundation
import Observation
import Wheelman
import TheScore
import os.log

private let logger = Logger(subsystem: "com.buttonheist", category: "mastermind")

/// Observable session orchestrator for discovering and connecting to iOS apps running InsideJob.
///
/// Thin @Observable wrapper over TheWheelman. Provides the SwiftUI-friendly API surface
/// with published state and callback hooks. All discovery, connection, keepalive, and
/// reconnect logic lives in TheWheelman.
@Observable
@MainActor
public final class TheMastermind {

    // MARK: - Observable State

    public private(set) var discoveredDevices: [DiscoveredDevice] = []
    public private(set) var connectedDevice: DiscoveredDevice?
    public private(set) var serverInfo: ServerInfo?
    public private(set) var currentInterface: Interface?
    public private(set) var currentScreen: ScreenPayload?
    public private(set) var isRecording: Bool = false
    public private(set) var isDiscovering: Bool = false
    public private(set) var connectionState: ConnectionState = .disconnected

    public enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    // MARK: - Callbacks (for non-SwiftUI usage)

    public var onDeviceDiscovered: ((DiscoveredDevice) -> Void)?
    public var onDeviceLost: ((DiscoveredDevice) -> Void)?
    public var onConnected: ((ServerInfo) -> Void)?
    public var onDisconnected: ((Error?) -> Void)?
    public var onInterfaceUpdate: ((Interface) -> Void)?
    public var onActionResult: ((ActionResult) -> Void)?
    public var onScreen: ((ScreenPayload) -> Void)?
    public var onRecordingStarted: (() -> Void)?
    public var onRecording: ((RecordingPayload) -> Void)?
    public var onRecordingError: ((String) -> Void)?
    public var onTokenReceived: ((String) -> Void)?
    public var onSessionLocked: ((SessionLockedPayload) -> Void)?
    public var onAuthFailed: ((String) -> Void)?

    // MARK: - Configuration (forwarded to TheWheelman)

    public var token: String? {
        get { wheelman.token }
        set { wheelman.token = newValue }
    }

    public var forceSession: Bool {
        get { wheelman.forceSession }
        set { wheelman.forceSession = newValue }
    }

    public var driverId: String? {
        get { wheelman.driverId }
        set { wheelman.driverId = newValue }
    }

    public var autoSubscribe: Bool {
        get { wheelman.autoSubscribe }
        set { wheelman.autoSubscribe = newValue }
    }

    // MARK: - The Wheelman

    public let wheelman = TheWheelman()

    // MARK: - Init

    public init() {
        wireUpWheelman()
    }

    private func wireUpWheelman() {
        wheelman.onDeviceFound = { [weak self] device in
            guard let self else { return }
            self.discoveredDevices = self.wheelman.discoveredDevices
            self.isDiscovering = self.wheelman.isDiscovering
            self.onDeviceDiscovered?(device)
        }

        wheelman.onDeviceLost = { [weak self] device in
            guard let self else { return }
            self.discoveredDevices = self.wheelman.discoveredDevices
            self.onDeviceLost?(device)
        }

        wheelman.onConnected = { [weak self] info in
            guard let self else { return }
            self.connectionState = .connected
            self.connectedDevice = self.wheelman.connectedDevice
            self.serverInfo = info
            self.onConnected?(info)
        }

        wheelman.onDisconnected = { [weak self] error in
            guard let self else { return }
            // Preserve .failed state (e.g., from sessionLocked)
            if case .failed = self.connectionState {
                // keep .failed
            } else {
                self.connectionState = .disconnected
            }
            self.connectedDevice = nil
            self.serverInfo = nil
            self.currentInterface = nil
            self.currentScreen = nil
            self.isRecording = false
            self.onDisconnected?(error)
        }

        wheelman.onInterface = { [weak self] payload in
            self?.currentInterface = payload
            self?.onInterfaceUpdate?(payload)
        }

        wheelman.onActionResult = { [weak self] result in
            self?.onActionResult?(result)
        }

        wheelman.onScreen = { [weak self] payload in
            self?.currentScreen = payload
            self?.onScreen?(payload)
        }

        wheelman.onRecordingStarted = { [weak self] in
            self?.isRecording = true
            self?.onRecordingStarted?()
        }
        wheelman.onRecording = { [weak self] payload in
            self?.isRecording = false
            self?.onRecording?(payload)
        }
        wheelman.onRecordingError = { [weak self] message in
            self?.isRecording = false
            self?.onRecordingError?(message)
        }

        wheelman.onError = { [weak self] message in
            self?.connectionState = .failed(message)
        }

        wheelman.onAuthApproved = { [weak self] approvedToken in
            self?.onTokenReceived?(approvedToken)
        }

        wheelman.onSessionLocked = { [weak self] payload in
            self?.connectionState = .failed(payload.message)
            self?.onSessionLocked?(payload)
        }

        wheelman.onAuthFailed = { [weak self] reason in
            self?.connectionState = .failed(reason)
            self?.onAuthFailed?(reason)
        }
    }

    // MARK: - Discovery (delegated)

    public func startDiscovery() {
        wheelman.startDiscovery()
        isDiscovering = wheelman.isDiscovering
    }

    public func stopDiscovery() {
        wheelman.stopDiscovery()
        isDiscovering = false
        discoveredDevices = []
    }

    // MARK: - Connection (delegated)

    public func connect(to device: DiscoveredDevice) {
        connectionState = .connecting
        wheelman.connect(to: device)
    }

    public func disconnect() {
        wheelman.disconnect()
        connectionState = .disconnected
        connectedDevice = nil
        serverInfo = nil
        currentInterface = nil
        currentScreen = nil
        isRecording = false
    }

    // MARK: - Commands

    public func requestInterface() {
        wheelman.send(.requestInterface)
    }

    public func send(_ message: ClientMessage) {
        wheelman.send(message)
    }

    /// Force-close the connection, triggering the onDisconnected callback.
    public func forceDisconnect() {
        guard connectionState == .connected else { return }
        logger.warning("Force-disconnecting stale connection")
        disconnect()
        onDisconnected?(ActionError.timeout)
    }

    // MARK: - Async Wait Methods

    public func waitForActionResult(timeout: TimeInterval) async throws -> ActionResult {
        try await withCheckedThrowingContinuation { continuation in
            var didResume = false

            let timeoutTask = Task { @MainActor in
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if !didResume {
                    didResume = true
                    continuation.resume(throwing: ActionError.timeout)
                }
            }

            onActionResult = { result in
                if !didResume {
                    didResume = true
                    timeoutTask.cancel()
                    continuation.resume(returning: result)
                }
            }
        }
    }

    public func waitForInterface(timeout: TimeInterval = 10.0) async throws -> Interface {
        try await withCheckedThrowingContinuation { continuation in
            var didResume = false

            let timeoutTask = Task { @MainActor in
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if !didResume {
                    didResume = true
                    continuation.resume(throwing: ActionError.timeout)
                }
            }

            onInterfaceUpdate = { payload in
                if !didResume {
                    didResume = true
                    timeoutTask.cancel()
                    continuation.resume(returning: payload)
                }
            }
        }
    }

    public func waitForScreen(timeout: TimeInterval = 30.0) async throws -> ScreenPayload {
        try await withCheckedThrowingContinuation { continuation in
            var didResume = false

            let timeoutTask = Task { @MainActor in
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if !didResume {
                    didResume = true
                    continuation.resume(throwing: ActionError.timeout)
                }
            }

            onScreen = { payload in
                if !didResume {
                    didResume = true
                    timeoutTask.cancel()
                    continuation.resume(returning: payload)
                }
            }
        }
    }

    public func waitForRecording(timeout: TimeInterval = 120.0) async throws -> RecordingPayload {
        try await withCheckedThrowingContinuation { continuation in
            var didResume = false

            let timeoutTask = Task { @MainActor in
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if !didResume {
                    didResume = true
                    continuation.resume(throwing: ActionError.timeout)
                }
            }

            onRecording = { payload in
                if !didResume {
                    didResume = true
                    timeoutTask.cancel()
                    continuation.resume(returning: payload)
                }
            }

            onRecordingError = { message in
                if !didResume {
                    didResume = true
                    timeoutTask.cancel()
                    continuation.resume(throwing: RecordingError.serverError(message))
                }
            }
        }
    }

    public enum RecordingError: Error, LocalizedError {
        case serverError(String)
        public var errorDescription: String? {
            switch self {
            case .serverError(let msg): return "Recording failed: \(msg)"
            }
        }
    }

    public enum ActionError: Error, LocalizedError {
        case timeout
        public var errorDescription: String? {
            switch self {
            case .timeout: return "Action timed out"
            }
        }
    }

    // MARK: - Display Names (delegated)

    public func displayName(for device: DiscoveredDevice) -> String {
        wheelman.displayName(for: device)
    }

    public var connectedDeviceDisplayName: String? {
        guard let device = connectedDevice else { return nil }
        return displayName(for: device)
    }
}
