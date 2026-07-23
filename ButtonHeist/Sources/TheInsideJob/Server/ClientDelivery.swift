import Foundation
import os

import TheScore

let muscleLogger = ButtonHeistLog.logger(.insideJob(.auth))

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
        guard latestGeneration.map({ generation > $0 }) ?? true else { return .rejected }
        self = .wiring(generation)
        return .admitted
    }

    mutating func install(_ callbacks: Callbacks, for generation: Generation) -> InstallOutcome {
        guard case .wiring(let currentGeneration) = self,
              currentGeneration == generation
        else { return .rejected }
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
            return .rejected
        }
    }

    mutating func reset() {
        self = .idle(latest: latestGeneration)
    }

    func send(
        _ data: Data,
        toClient clientId: Int,
        generation: Generation
    ) async -> ServerSendOutcome {
        guard case .admitted(let callbacks) = deliveryDecision(for: generation) else {
            return .failed(.transportUnavailable)
        }
        return await callbacks.sendToClient(data, clientId)
    }

    func respond(
        _ data: Data,
        using respond: @escaping SocketResponseHandler,
        generation: Generation
    ) async -> ServerSendOutcome {
        guard case .admitted = deliveryDecision(for: generation) else {
            return .failed(.transportUnavailable)
        }
        return await respond(data)
    }

    @discardableResult
    func disconnect(_ clientId: Int, generation: Generation) async -> DeliveryOutcome {
        switch deliveryDecision(for: generation) {
        case .admitted(let callbacks):
            await callbacks.disconnectClient(clientId)
            return .delivered
        case .rejected:
            return .rejected
        case .callbacksUnavailable:
            return .failed(.callbacksNotInstalled("disconnectClient"))
        }
    }

    @discardableResult
    func clientAuthenticated(
        _ clientId: Int,
        respond: @escaping SocketResponseHandler,
        generation: Generation
    ) async -> DeliveryOutcome {
        switch deliveryDecision(for: generation) {
        case .admitted(let callbacks):
            await callbacks.onClientAuthenticated(clientId, respond)
            return .delivered
        case .rejected:
            return .rejected
        case .callbacksUnavailable:
            return .failed(.callbacksNotInstalled("onClientAuthenticated"))
        }
    }

    func isWired(generation: Generation) -> Bool {
        guard case .wired(let currentGeneration, _) = self else { return false }
        return currentGeneration == generation
    }

    private enum DeliveryDecision {
        case admitted(Callbacks)
        case rejected
        case callbacksUnavailable
    }

    private func deliveryDecision(for candidate: Generation) -> DeliveryDecision {
        switch self {
        case .wired(let current, let callbacks) where current == candidate:
            return .admitted(callbacks)
        case .wiring(let current) where current == candidate,
             .idle(let current?) where current == candidate:
            return .callbacksUnavailable
        case .idle(latest: nil):
            return .callbacksUnavailable
        case .idle, .wiring, .wired:
            return .rejected
        }
    }
}
