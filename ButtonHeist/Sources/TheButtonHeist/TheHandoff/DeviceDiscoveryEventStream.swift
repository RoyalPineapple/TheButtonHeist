import Foundation
import Network
import os

enum DeviceDiscoveryBrowserEvent: Sendable {
    case resultsChanged(Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>)
    case stateChanged(DeviceDiscoveryBrowserState)
}

/// The single ordered bridge from one NWBrowser callback queue into the
/// Button Heist actor. Finishing the stream invalidates every captured callback
/// from that browser generation.
final class DeviceDiscoveryEventStream: Sendable {
    enum Admission: Sendable {
        case accepted
        case overflow
        case terminated
    }

    enum TerminalReason: Sendable {
        case finished
        case continuationTerminated
        case overflow
    }

    private enum GenerationState {
        case accepting
        case invalidated(TerminalReason)
    }

    static let bufferLimit = 512

    let events: AsyncStream<DeviceDiscoveryBrowserEvent>

    private let continuation: AsyncStream<DeviceDiscoveryBrowserEvent>.Continuation
    private let generationState = OSAllocatedUnfairLock(initialState: GenerationState.accepting)

    init() {
        let stream = AsyncStream<DeviceDiscoveryBrowserEvent>.makeStream(
            bufferingPolicy: .bufferingOldest(Self.bufferLimit)
        )
        self.events = stream.stream
        self.continuation = stream.continuation
    }

    func yield(_ event: DeviceDiscoveryBrowserEvent) -> Admission {
        let admission = generationState.withLock { state in
            guard case .accepting = state else { return Admission.terminated }
            switch continuation.yield(event) {
            case .enqueued:
                return .accepted
            case .dropped:
                state = .invalidated(.overflow)
                return .overflow
            case .terminated:
                state = .invalidated(.continuationTerminated)
                return .terminated
            @unknown default:
                state = .invalidated(.overflow)
                return .overflow
            }
        }
        if case .overflow = admission {
            continuation.finish()
        }
        return admission
    }

    func finish() {
        let shouldFinish = generationState.withLock { state in
            guard case .accepting = state else { return false }
            state = .invalidated(.finished)
            return true
        }
        if shouldFinish {
            continuation.finish()
        }
    }

    var isGenerationActive: Bool {
        generationState.withLock { state in
            guard case .accepting = state else { return false }
            return true
        }
    }

    var terminalReason: TerminalReason? {
        generationState.withLock { state in
            guard case .invalidated(let reason) = state else { return nil }
            return reason
        }
    }
}
