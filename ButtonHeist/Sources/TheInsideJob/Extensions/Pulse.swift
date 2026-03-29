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

    /// Single broadcast path: refresh, hash-compare, broadcast only on change.
    private func broadcastIfChanged() {
        guard muscle.hasSubscribers else { return }
        guard let hierarchyTree = bagman.refreshAccessibilityData() else { return }

        let snapshot = bagman.snapshotElements()
        let currentHash = snapshot.hashValue

        guard currentHash != bagman.lastHierarchyHash || hierarchyInvalidated else { return }
        hierarchyInvalidated = false
        bagman.lastHierarchyHash = currentHash

        let tree = hierarchyTree.map { bagman.convertHierarchyNode($0) }
        let payload = Interface(timestamp: Date(), elements: snapshot, tree: tree)

        if let data = try? JSONEncoder().encode(ResponseEnvelope(message: .interface(payload))) {
            broadcastToSubscribed(data)
        }

        broadcastScreen()
        stakeout?.noteScreenChange()

        insideJobLogger.debug("Broadcast hierarchy update to \(self.muscle.subscribedClients.count) subscriber(s)")
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

        let payload = Interface(timestamp: Date(), elements: snapshot, tree: tree)
        sendMessage(.interface(payload), requestId: requestId, respond: respond)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
