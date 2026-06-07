import Foundation
import os

private let reachabilityLogger = Logger(subsystem: "com.buttonheist.thehandoff", category: "reachability")

extension Array where Element == DiscoveredDevice {
    /// Probe all devices in parallel and return only those that are reachable.
    /// Uses a passive transport/TLS-ready probe as a lightweight liveness check.
    /// Reachability never enters the post-handshake session lifecycle or asks
    /// the server for pre-auth identity.
    func reachable(token: String? = nil, timeout: TimeInterval = 1.5) async -> [DiscoveredDevice] {
        await withTaskGroup(of: (Int, DiscoveredDevice?).self) { group in
            for (index, device) in self.enumerated() {
                group.addTask {
                    let reachable = await device.reachability(token: token, timeout: timeout).isReachable
                    return reachable ? (index, device) : (index, nil)
                }
            }
            var indexed: [(Int, DiscoveredDevice)] = []
            for await (index, device) in group {
                if let device { indexed.append((index, device)) }
            }
            return indexed.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }
}

@ButtonHeistActor
var makeReachabilityConnection: ((DiscoveredDevice) -> any TransportReachabilityConnecting)?

enum DeviceReachability: Equatable {
    case reachable
    case unavailable
    case failed(DisconnectReason)

    var isReachable: Bool {
        if case .reachable = self {
            return true
        }
        return false
    }
}

extension DiscoveredDevice {
    @ButtonHeistActor
    func isReachable(token: String? = nil, timeout: TimeInterval = 1.5) async -> Bool {
        await reachability(token: token, timeout: timeout).isReachable
    }

    @ButtonHeistActor
    func reachability(token: String? = nil, timeout: TimeInterval = 1.5) async -> DeviceReachability {
        let connection = makeReachabilityConnection?(self) ?? DeviceConnection(device: self, token: token)
        let deviceName = name
        let resolver = ReachabilityResolver()

        // Wire the connection callbacks to resolve the probe:
        // raw socket readiness resolves reachable; `.disconnected` records
        // contract failures that should not be flattened into transport misses.
        // The resolver is one-shot so a subsequent `.disconnected` after a
        // successful socket-ready signal is a no-op.
        connection.onTransportReady = {
            reachabilityLogger.debug("Transport reachable: \(deviceName, privacy: .public)")
            resolver.resolve(.reachable)
        }
        connection.onEvent = { event in
            switch event {
            case .connected:
                break
            case .message:
                break
            case .sendFailed:
                break
            case .disconnected(let reason):
                resolver.resolve(Self.reachabilityDisconnectResult(reason))
            }
        }

        connection.connect()

        let timeoutTask = Task { @ButtonHeistActor in
            guard await Task.cancellableSleep(for: .seconds(timeout)) else { return }
            resolver.resolve(.unavailable)
        }
        defer { timeoutTask.cancel() }

        let reachability = await resolver.value
        connection.disconnect()
        if !reachability.isReachable {
            reachabilityLogger.debug("Transport probe miss: \(deviceName, privacy: .public)")
        }
        return reachability
    }

    private static func reachabilityDisconnectResult(_ reason: DisconnectReason) -> DeviceReachability {
        switch reason.phase {
        case .tls:
            return .failed(reason)
        case .discovery, .setup, .transport, .authentication, .session,
             .request, .protocolNegotiation, .client, .server:
            return .unavailable
        }
    }
}

/// One-shot resolver backing `DiscoveredDevice.reachability`. Holds a
/// continuation that is resumed exactly once by whichever signal arrives
/// first: a successful transport-ready signal, a disconnect, or the timeout.
@ButtonHeistActor
private final class ReachabilityResolver {
    /// Explicit three-state lifecycle replacing the prior
    /// `(continuation: CheckedContinuation?, pendingResult: DeviceReachability?)` pair.
    private enum State {
        /// No awaiter has registered and no result has arrived.
        case idle
        /// Awaiters are parked, waiting for the first `resolve(_:)` to fire.
        case awaiting([CheckedContinuation<DeviceReachability, Never>])
        /// A result arrived before any awaiter registered. The next
        /// `await value` returns immediately.
        case resolved(DeviceReachability)
    }

    private var state: State = .idle

    var value: DeviceReachability {
        get async {
            await withCheckedContinuation { (continuation: CheckedContinuation<DeviceReachability, Never>) in
                switch state {
                case .resolved(let value):
                    continuation.resume(returning: value)
                case .idle:
                    state = .awaiting([continuation])
                case .awaiting(var continuations):
                    continuations.append(continuation)
                    state = .awaiting(continuations)
                }
            }
        }
    }

    func resolve(_ value: DeviceReachability) {
        switch state {
        case .awaiting(let continuations):
            state = .resolved(value)
            for continuation in continuations {
                continuation.resume(returning: value)
            }
        case .idle:
            state = .resolved(value)
        case .resolved:
            return
        }
    }
}
