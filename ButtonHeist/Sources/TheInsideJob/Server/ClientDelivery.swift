import Foundation
import os

/// Typed callback/delivery wiring for `TheMuscle`.
enum ClientDelivery: Sendable {
    struct Generation: RawRepresentable, Comparable, Sendable {
        let rawValue: UInt64

        init(rawValue: UInt64) {
            self.rawValue = rawValue
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    struct Callbacks: Sendable {
        var sendToClient: @Sendable (_ data: Data, _ clientId: Int) async -> ServerSendOutcome
        var disconnectClient: @Sendable (_ clientId: Int) async -> Void
        var onClientAuthenticated: @MainActor @Sendable (
            _ clientId: Int,
            _ respond: @escaping SocketResponseHandler
        ) async -> Void
    }

    enum BeginOutcome: Equatable, Sendable {
        case admitted
        case rejected
    }

    enum DeliveryOutcome: Equatable, Sendable {
        case delivered
        case rejected
        case failed(ClientDeliveryFailure)
    }

    enum InstallOutcome: Equatable, Sendable {
        case installed
        case rejected
    }

    enum InvalidateOutcome: Equatable, Sendable {
        case invalidated
        case rejected
    }

    enum ClientDeliveryFailure: Error, Equatable, Sendable {
        case callbacksNotInstalled(String)
    }

    case idle(latest: Generation?)
    case wiring(Generation)
    case wired(Generation, Callbacks)

    var generation: Generation? {
        switch self {
        case .idle:
            nil
        case .wiring(let generation), .wired(let generation, _):
            generation
        }
    }

    var latestGeneration: Generation? {
        switch self {
        case .idle(let latest):
            latest
        case .wiring(let generation), .wired(let generation, _):
            generation
        }
    }

    @discardableResult
    mutating func begin(_ generation: Generation) -> BeginOutcome {
        guard latestGeneration.map({ generation > $0 }) ?? true else {
            logRejection(.begin, candidate: generation)
            return .rejected
        }
        self = .wiring(generation)
        return .admitted
    }

    mutating func install(_ callbacks: Callbacks, for generation: Generation) -> InstallOutcome {
        guard case .wiring(let currentGeneration) = self,
              currentGeneration == generation
        else {
            logRejection(.install, candidate: generation)
            return .rejected
        }
        self = .wired(generation, callbacks)
        return .installed
    }

    @discardableResult
    mutating func invalidate(_ generation: Generation) -> InvalidateOutcome {
        switch self {
        case .wiring(let currentGeneration) where currentGeneration == generation,
             .wired(let currentGeneration, _) where currentGeneration == generation:
            self = .idle(latest: generation)
            return .invalidated
        default:
            logRejection(.invalidate, candidate: generation)
            return .rejected
        }
    }

    mutating func reset() {
        self = .idle(latest: latestGeneration)
    }

    func send(_ data: Data, toClient clientId: Int) async -> ServerSendOutcome {
        guard case .wired(_, let callbacks) = self else {
            return .failed(.transportUnavailable)
        }
        return await callbacks.sendToClient(data, clientId)
    }

    @discardableResult
    func disconnect(_ clientId: Int) async -> DeliveryOutcome {
        guard case .wired(_, let callbacks) = self else {
            return .failed(.callbacksNotInstalled("disconnectClient"))
        }
        await callbacks.disconnectClient(clientId)
        return .delivered
    }

    @discardableResult
    func clientAuthenticated(
        _ clientId: Int,
        respond: @escaping SocketResponseHandler
    ) async -> DeliveryOutcome {
        guard case .wired(_, let callbacks) = self else {
            return .failed(.callbacksNotInstalled("onClientAuthenticated"))
        }
        await callbacks.onClientAuthenticated(clientId, respond)
        return .delivered
    }

    private enum Operation: String {
        case begin
        case install
        case invalidate
    }

    private func logRejection(_ operation: Operation, candidate: Generation) {
        let current = latestGeneration.map { String($0.rawValue) } ?? "none"
        muscleLogger.debug(
            "Rejected callback \(operation.rawValue, privacy: .public): candidate=\(candidate.rawValue) current=\(current, privacy: .public)"
        )
    }
}
