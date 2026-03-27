#if canImport(UIKit)
#if DEBUG
import UIKit
import TheScore

extension TheInsideJob {

    // MARK: - Hierarchy Updates (pulse-driven)

    /// Mark the hierarchy as stale. If the pulse is settled, a coalesced
    /// broadcast fires within one frame. Otherwise, the next `.settled`
    /// transition triggers the broadcast.
    func scheduleHierarchyUpdate() {
        hierarchyInvalidated = true

        // If already settled the transition won't re-fire —
        // dispatch a coalesced broadcast within one frame.
        if tripwire.latestReading?.isSettled == true {
            updateCoalesceTask?.cancel()
            updateCoalesceTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 16_000_000) // ~1 frame coalesce
                guard !Task.isCancelled, let self, self.hierarchyInvalidated else { return }
                self.hierarchyInvalidated = false
                self.broadcastCurrentHierarchy()
            }
        }
    }

    /// Called by the pulse's `.settled` transition and the coalesce task.
    /// Reads the accessibility tree and broadcasts to subscribers.
    func broadcastCurrentHierarchy() {
        guard muscle.hasSubscribers else { return }
        guard let hierarchyTree = bagman.refreshAccessibilityData() else { return }

        let snapshot = bagman.snapshotElements()
        let tree = hierarchyTree.map { bagman.convertHierarchyNode($0) }

        let payload = Interface(timestamp: Date(), elements: snapshot.elements, tree: tree)

        bagman.lastHierarchyHash = snapshot.elements.hashValue

        if let data = try? JSONEncoder().encode(ResponseEnvelope(message: .interface(payload))) {
            broadcastToSubscribed(data)
        }

        insideJobLogger.debug("Broadcast hierarchy update to \(self.muscle.subscribedClients.count) subscriber(s)")
    }

    /// Handle pulse transitions. Wired in `start()` / `resume()`.
    func handlePulseTransition(_ transition: TheTripwire.PulseTransition) {
        if case .settled = transition, hierarchyInvalidated {
            hierarchyInvalidated = false
            broadcastCurrentHierarchy()
        }
    }

    // MARK: - Polling

    func startPollingLoop() {
        pollingTask?.cancel()
        pollingTask = Task { @MainActor in
            while isPollingEnabled && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: pollingInterval)
                if !Task.isCancelled && isPollingEnabled {
                    checkForChanges()
                }
            }
        }
    }

    private func checkForChanges() {
        guard muscle.hasSubscribers else { return }
        guard tripwire.allClear() else { return }
        guard let hierarchyTree = bagman.refreshAccessibilityData() else { return }

        let snapshot = bagman.snapshotElements()
        let tree = hierarchyTree.map { bagman.convertHierarchyNode($0) }

        let currentHash = snapshot.elements.hashValue

        if currentHash != bagman.lastHierarchyHash || hierarchyInvalidated {
            hierarchyInvalidated = false
            bagman.lastHierarchyHash = currentHash

            let payload = Interface(timestamp: Date(), elements: snapshot.elements, tree: tree)
            if let data = try? JSONEncoder().encode(ResponseEnvelope(message: .interface(payload))) {
                broadcastToSubscribed(data)
            }

            broadcastScreen()

            stakeout?.noteScreenChange()

            insideJobLogger.debug("Polling detected change, broadcast to \(self.muscle.subscribedClients.count) subscriber(s)")
        }
    }

    // MARK: - Interface Sending

    func sendInterface(requestId: String? = nil, respond: @escaping (Data) -> Void) async {
        _ = await tripwire.waitForAllClear(timeout: 0.5)

        guard let hierarchyTree = bagman.refreshAccessibilityData() else {
            sendMessage(.error("Could not access root view"), requestId: requestId, respond: respond)
            return
        }

        let snapshot = bagman.snapshotElements()
        let tree = hierarchyTree.map { bagman.convertHierarchyNode($0) }

        let payload = Interface(timestamp: Date(), elements: snapshot.elements, tree: tree)
        sendMessage(.interface(payload), requestId: requestId, respond: respond)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
