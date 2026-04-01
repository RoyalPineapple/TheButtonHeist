#if canImport(UIKit)
#if DEBUG
import UIKit
import TheScore

extension TheInsideJob {

    // MARK: - Hierarchy Invalidation

    /// Mark the hierarchy as stale. The pulse loop will pick this up
    /// on the next settle event and broadcast if the tree actually changed.
    func scheduleHierarchyUpdate() {
        hierarchyInvalidated = true
    }

    /// Handle pulse transitions. Wired in `start()` / `resume()`.
    func handlePulseTransition(_ transition: TheTripwire.PulseTransition) {
        if case .settled = transition, hierarchyInvalidated {
            broadcastIfChanged()
        }
    }

    // MARK: - Pulse (settle-driven)

    func startPollingLoop() {
        pollingTask?.cancel()
        pollingTask = Task { @MainActor in
            while isPollingEnabled && !Task.isCancelled {
                let settled = await tripwire.waitForAllClear(timeout: pollingTimeoutSeconds)
                guard !Task.isCancelled, isPollingEnabled else { break }
                if settled {
                    broadcastIfChanged()
                }
            }
        }
    }

    /// Refresh the hierarchy and broadcast to subscribers if it changed.
    /// The refresh always runs — even without subscribers — so TheBagman's
    /// state is never stale when a new client connects.
    private func broadcastIfChanged() {
        guard let parseResult = bagman.refresh() else { return }
        hierarchyInvalidated = false

        guard muscle.hasSubscribers else { return }

        let snapshot = bagman.snapshot(.visible)
        let wireElements = bagman.toWire(snapshot)
        let currentHash = wireElements.hashValue

        guard currentHash != bagman.lastHierarchyHash else { return }
        bagman.lastHierarchyHash = currentHash

        let tree = parseResult.hierarchy.map { bagman.convertHierarchyNode($0) }
        let payload = Interface(timestamp: Date(), elements: wireElements, tree: tree)

        broadcastToSubscribed(.interface(payload))

        broadcastScreen()
        stakeout?.noteScreenChange()

        insideJobLogger.debug("Broadcast hierarchy update to \(self.muscle.subscribedClients.count) subscriber(s)")
    }

    // MARK: - Interface Sending

    func sendInterface(requestId: String? = nil, respond: @escaping (Data) -> Void) async {
        _ = await tripwire.waitForAllClear(timeout: 0.5)

        guard let parseResult = bagman.refresh() else {
            sendMessage(.error("Could not access root view"), requestId: requestId, respond: respond)
            return
        }

        let snapshot = bagman.snapshot(.visible)
        let tree = parseResult.hierarchy.map { bagman.convertHierarchyNode($0) }

        let payload = Interface(timestamp: Date(), elements: bagman.toWire(snapshot), tree: tree)
        sendMessage(.interface(payload), requestId: requestId, respond: respond)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
