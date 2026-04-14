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

    func makePollingTask(interval: TimeInterval) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            guard let self else { return }
            while self.isPollingEnabled && !Task.isCancelled {
                let settled = await self.tripwire.waitForAllClear(timeout: interval)
                guard !Task.isCancelled, self.isPollingEnabled else { break }
                if settled {
                    self.broadcastIfChanged()
                }
            }
        }
    }

    /// Refresh the hierarchy and broadcast to subscribers if it changed.
    /// The refresh always runs (via brains) — even without subscribers —
    /// so the state is never stale when a new client connects.
    private func broadcastIfChanged() {
        guard let payload = brains.broadcastInterfaceIfChanged() else {
            hierarchyInvalidated = false
            return
        }
        hierarchyInvalidated = false

        guard muscle.hasSubscribers else { return }

        broadcastToSubscribed(.interface(payload))
        broadcastScreen()
        stakeout?.noteScreenChange()

        insideJobLogger.debug("Broadcast hierarchy update to \(self.muscle.subscribedClients.count) subscriber(s)")
    }

    // MARK: - Interface Sending

    func sendInterface(requestId: String? = nil, respond: @escaping (Data) -> Void) async {
        _ = await tripwire.waitForAllClear(timeout: 0.5)

        guard brains.refresh() != nil else {
            sendMessage(.error("Could not access root view"), requestId: requestId, respond: respond)
            return
        }

        let manifest = await brains.exploreAndPrune()
        insideJobLogger.info("Explore: \(manifest.elementCount) elements (\(manifest.scrollCount) scrolls, \(String(format: "%.2f", manifest.explorationTime))s)")

        let payload = brains.currentInterface()
        sendMessage(.interface(payload), requestId: requestId, respond: respond)
        brains.recordSentState(treeHash: payload.elements.hashValue)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
