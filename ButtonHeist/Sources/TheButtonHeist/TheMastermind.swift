import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.buttonheist", category: "mastermind")

/// Observable session orchestrator for discovering and connecting to iOS apps running TheInsideJob.
///
/// Thin @Observable wrapper over TheHandoff. Provides the SwiftUI-friendly API surface
/// with published state and callback hooks. All discovery, connection, keepalive, and
/// reconnect logic lives in TheHandoff.
@Observable
@ButtonHeistActor
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
    public var onDisconnected: ((DisconnectReason) -> Void)?
    public var onInterfaceUpdate: ((Interface) -> Void)?
    public var onActionResult: ((ActionResult) -> Void)?
    public var onScreen: ((ScreenPayload) -> Void)?
    public var onRecordingStarted: (() -> Void)?
    public var onRecording: ((RecordingPayload) -> Void)?
    public var onRecordingError: ((String) -> Void)?
    public var onAuthApproved: ((String?) -> Void)?
    public var onSessionLocked: ((SessionLockedPayload) -> Void)?
    public var onAuthFailed: ((String) -> Void)?
    public var onInteraction: ((InteractionEvent) -> Void)?

    // MARK: - Configuration (forwarded to TheHandoff)

    public var token: String? {
        get { handoff.token }
        set { handoff.token = newValue }
    }

    public var driverId: String? {
        get { handoff.driverId }
        set { handoff.driverId = newValue }
    }

    public var autoSubscribe: Bool {
        get { handoff.autoSubscribe }
        set { handoff.autoSubscribe = newValue }
    }

    // MARK: - The Handoff

    public let handoff = TheHandoff()

    // MARK: - Pending Request Tracking

    private var pendingActionRequests: [String: CheckedContinuation<ActionResult, Error>] = [:]
    private var pendingInterfaceRequests: [String: CheckedContinuation<Interface, Error>] = [:]
    private var pendingScreenRequests: [String: CheckedContinuation<ScreenPayload, Error>] = [:]

    // MARK: - Init

    public init() {
        wireUpHandoff()
    }

    private func wireUpHandoff() {
        wireUpDiscoveryCallbacks()
        wireUpConnectionCallbacks()
        wireUpMessageCallbacks()
    }

    private func wireUpDiscoveryCallbacks() {
        handoff.onDeviceFound = { [weak self] device in
            guard let self else { return }
            self.discoveredDevices = self.handoff.discoveredDevices
            self.isDiscovering = self.handoff.isDiscovering
            self.onDeviceDiscovered?(device)
        }

        handoff.onDeviceLost = { [weak self] device in
            guard let self else { return }
            self.discoveredDevices = self.handoff.discoveredDevices
            self.onDeviceLost?(device)
        }
    }

    private func wireUpConnectionCallbacks() {
        handoff.onConnected = { [weak self] info in
            guard let self else { return }
            self.connectionState = .connected
            self.connectedDevice = self.handoff.connectedDevice
            self.serverInfo = info
            self.onConnected?(info)
        }

        handoff.onDisconnected = { [weak self] reason in
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
            self.onDisconnected?(reason)
        }

        handoff.onError = { [weak self] message in
            guard let self else { return }
            self.connectionState = .failed(message)
        }

        handoff.onAuthApproved = { [weak self] approvedToken in
            guard let self else { return }
            self.onAuthApproved?(approvedToken)
        }

        handoff.onSessionLocked = { [weak self] payload in
            guard let self else { return }
            self.connectionState = .failed(payload.message)
            self.onSessionLocked?(payload)
        }

        handoff.onAuthFailed = { [weak self] reason in
            guard let self else { return }
            self.connectionState = .failed(reason)
            self.onAuthFailed?(reason)
        }
    }

    private func wireUpMessageCallbacks() {
        handoff.onInterface = { [weak self] payload, requestId in
            guard let self else { return }
            if let requestId, let continuation = self.pendingInterfaceRequests.removeValue(forKey: requestId) {
                continuation.resume(returning: payload)
            } else {
                self.currentInterface = payload
                self.onInterfaceUpdate?(payload)
            }
        }

        handoff.onActionResult = { [weak self] result, requestId in
            guard let self else { return }
            if let requestId, let continuation = self.pendingActionRequests.removeValue(forKey: requestId) {
                continuation.resume(returning: result)
            } else {
                self.onActionResult?(result)
            }
        }

        handoff.onScreen = { [weak self] payload, requestId in
            guard let self else { return }
            if let requestId, let continuation = self.pendingScreenRequests.removeValue(forKey: requestId) {
                continuation.resume(returning: payload)
            } else {
                self.currentScreen = payload
                self.onScreen?(payload)
            }
        }

        handoff.onRecordingStarted = { [weak self] in
            guard let self else { return }
            self.isRecording = true
            self.onRecordingStarted?()
        }
        handoff.onRecording = { [weak self] payload in
            guard let self else { return }
            self.isRecording = false
            self.onRecording?(payload)
        }
        handoff.onRecordingError = { [weak self] message in
            guard let self else { return }
            self.isRecording = false
            self.onRecordingError?(message)
        }

        handoff.onInteraction = { [weak self] event in
            self?.onInteraction?(event)
        }
    }

    // MARK: - Discovery (delegated)

    public func startDiscovery() {
        handoff.startDiscovery()
        isDiscovering = handoff.isDiscovering
    }

    public func stopDiscovery() {
        handoff.stopDiscovery()
        isDiscovering = false
        discoveredDevices = []
    }

    /// Discover devices and validate each deduped advertisement as it appears.
    public func discoverReachableDevices(
        timeout: TimeInterval = 3.0,
        probeTimeout: TimeInterval = 0.5,
        retryInterval: TimeInterval = 0.2
    ) async -> [DiscoveredDevice] {
        let startedTemporaryDiscovery = !handoff.hasActiveDiscoverySession
        if startedTemporaryDiscovery {
            startDiscovery()
        }
        defer {
            if startedTemporaryDiscovery {
                stopDiscovery()
            }
        }

        let deadline = Date().addingTimeInterval(timeout)
        var reachableIDs: Set<String> = []
        var nextProbeAt: [String: Date] = [:]

        while Date() < deadline {
            let snapshot = discoveredDevices
            let currentIDs = Set(snapshot.map(\.id))
            reachableIDs = reachableIDs.filter { currentIDs.contains($0) }
            nextProbeAt = nextProbeAt.filter { currentIDs.contains($0.key) }

            let now = Date()
            let dueDevices = snapshot.filter { device in
                !reachableIDs.contains(device.id) &&
                    (nextProbeAt[device.id] ?? .distantPast) <= now
            }

            if !dueDevices.isEmpty {
                let probed = await withTaskGroup(of: (String, Bool).self, returning: [(String, Bool)].self) { group in
                    for device in dueDevices {
                        group.addTask {
                            (device.id, await device.isReachable(timeout: probeTimeout))
                        }
                    }

                    var results: [(String, Bool)] = []
                    for await result in group {
                        results.append(result)
                    }
                    return results
                }

                let retryAt = Date().addingTimeInterval(retryInterval)
                for (id, isReachable) in probed {
                    if isReachable {
                        reachableIDs.insert(id)
                        nextProbeAt.removeValue(forKey: id)
                    } else {
                        nextProbeAt[id] = retryAt
                    }
                }
            }

            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        return discoveredDevices.filter { reachableIDs.contains($0.id) }
    }

    // MARK: - Connection (delegated)

    public func connect(to device: DiscoveredDevice) {
        connectionState = .connecting
        handoff.connect(to: device)
    }

    public func disconnect() {
        // Cancel all pending requests
        for (_, continuation) in pendingActionRequests {
            continuation.resume(throwing: ActionError.timeout)
        }
        pendingActionRequests.removeAll()
        for (_, continuation) in pendingInterfaceRequests {
            continuation.resume(throwing: ActionError.timeout)
        }
        pendingInterfaceRequests.removeAll()
        for (_, continuation) in pendingScreenRequests {
            continuation.resume(throwing: ActionError.timeout)
        }
        pendingScreenRequests.removeAll()

        handoff.disconnect()
        connectionState = .disconnected
        connectedDevice = nil
        serverInfo = nil
        currentInterface = nil
        currentScreen = nil
        isRecording = false
    }

    // MARK: - Commands

    public func requestInterface() {
        handoff.send(.requestInterface)
    }

    public func send(_ message: ClientMessage, requestId: String? = nil) {
        handoff.send(message, requestId: requestId)
    }

    /// Force-close the connection, triggering the onDisconnected callback.
    public func forceDisconnect() {
        guard connectionState == .connected else { return }
        logger.warning("Force-disconnecting stale connection")
        disconnect()
        onDisconnected?(.localDisconnect)
    }

    // MARK: - Async Wait Methods

    public func waitForActionResult(requestId: String? = nil, timeout: TimeInterval) async throws -> ActionResult {
        if let requestId {
            return try await withCheckedThrowingContinuation { continuation in
                pendingActionRequests[requestId] = continuation
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    self?.timeoutActionRequest(requestId)
                }
            }
        }
        return try await waitForResponse(timeout: timeout) { complete in
            onActionResult = { complete(.success($0)) }
        }
    }

    public func waitForInterface(requestId: String? = nil, timeout: TimeInterval = 10.0) async throws -> Interface {
        if let requestId {
            return try await withCheckedThrowingContinuation { continuation in
                pendingInterfaceRequests[requestId] = continuation
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    self?.timeoutInterfaceRequest(requestId)
                }
            }
        }
        return try await waitForResponse(timeout: timeout) { complete in
            onInterfaceUpdate = { complete(.success($0)) }
        }
    }

    public func waitForScreen(requestId: String? = nil, timeout: TimeInterval = 30.0) async throws -> ScreenPayload {
        if let requestId {
            return try await withCheckedThrowingContinuation { continuation in
                pendingScreenRequests[requestId] = continuation
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    self?.timeoutScreenRequest(requestId)
                }
            }
        }
        return try await waitForResponse(timeout: timeout) { complete in
            onScreen = { complete(.success($0)) }
        }
    }

    public func waitForRecording(timeout: TimeInterval = 120.0) async throws -> RecordingPayload {
        try await waitForResponse(timeout: timeout) { complete in
            onRecording = { complete(.success($0)) }
            onRecordingError = { complete(.failure(RecordingError.serverError($0))) }
        }
    }

    private func waitForResponse<T: Sendable>(
        timeout: TimeInterval,
        install: (@escaping @Sendable (Result<T, Error>) -> Void) -> Void
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            nonisolated(unsafe) var didResume = false

            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if !didResume {
                    didResume = true
                    continuation.resume(throwing: ActionError.timeout)
                }
            }

            install { result in
                if !didResume {
                    didResume = true
                    timeoutTask.cancel()
                    continuation.resume(with: result)
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
        handoff.displayName(for: device)
    }

    public var connectedDeviceDisplayName: String? {
        guard let device = connectedDevice else { return nil }
        return displayName(for: device)
    }

    private func timeoutActionRequest(_ requestId: String) {
        if let cont = pendingActionRequests.removeValue(forKey: requestId) {
            cont.resume(throwing: ActionError.timeout)
        }
    }

    private func timeoutInterfaceRequest(_ requestId: String) {
        if let cont = pendingInterfaceRequests.removeValue(forKey: requestId) {
            cont.resume(throwing: ActionError.timeout)
        }
    }

    private func timeoutScreenRequest(_ requestId: String) {
        if let cont = pendingScreenRequests.removeValue(forKey: requestId) {
            cont.resume(throwing: ActionError.timeout)
        }
    }
}
