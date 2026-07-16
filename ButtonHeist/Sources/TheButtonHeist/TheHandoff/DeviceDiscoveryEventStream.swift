import Foundation
import Network

enum DeviceDiscoveryBrowserEvent: Sendable {
    case resultsChanged(Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>)
    case stateChanged(DeviceDiscoveryBrowserState)
}

/// The single ordered bridge from one NWBrowser callback queue into the
/// Button Heist actor. Finishing the stream invalidates every captured callback
/// from that browser generation.
final class DeviceDiscoveryEventStream: Sendable {
    let events: AsyncStream<DeviceDiscoveryBrowserEvent>

    private let continuation: AsyncStream<DeviceDiscoveryBrowserEvent>.Continuation

    init() {
        let stream = AsyncStream<DeviceDiscoveryBrowserEvent>.makeStream()
        self.events = stream.stream
        self.continuation = stream.continuation
    }

    func yield(_ event: DeviceDiscoveryBrowserEvent) {
        continuation.yield(event)
    }

    func finish() {
        continuation.finish()
    }
}
