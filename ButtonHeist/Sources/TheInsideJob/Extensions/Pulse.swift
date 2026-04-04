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
    /// The refresh always runs — even without subscribers — so TheBagman's
    /// state is never stale when a new client connects.
    private func broadcastIfChanged() {
        guard let parseResult = bagman.refresh() else { return }
        hierarchyInvalidated = false

        guard muscle.hasSubscribers else { return }

        let snapshot = bagman.selectElements(.viewport)
        bagman.markPresented(snapshot)
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

        guard bagman.refresh() != nil else {
            sendMessage(.error("Could not access root view"), requestId: requestId, respond: respond)
            return
        }

        // First request seeds the registry with a full explore. After that,
        // every action runs exploreScreen so the registry stays current.
        // Either way, return .all — the caller may filter to off-screen elements
        // and expects stable traversal order across the full registry.
        if !bagman.hasServedInterface {
            let manifest = await bagman.exploreAndPrune()
            bagman.hasServedInterface = true
            let elementCount = bagman.screenElements.count
            let time = String(format: "%.2f", manifest.explorationTime)
            insideJobLogger.info("Initial explore: \(elementCount) elements (\(manifest.scrollCount) scrolls, \(time)s)")
        }

        let snapshot = bagman.selectElements(.all)
        bagman.markPresented(snapshot)
        let tree = bagman.currentHierarchy.isEmpty ? nil : bagman.currentHierarchy.map { bagman.convertHierarchyNode($0) }
        let payload = Interface(timestamp: Date(), elements: bagman.toWire(snapshot), tree: tree)
        sendMessage(.interface(payload), requestId: requestId, respond: respond)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
