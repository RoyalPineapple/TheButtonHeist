#if canImport(UIKit)
#if DEBUG
import UIKit
import TheScore

extension TheInsideJob {

    // MARK: - Hierarchy Updates

    func scheduleHierarchyUpdate() {
        updateDebounceTask?.cancel()
        updateDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: updateDebounceInterval)
            if !Task.isCancelled {
                broadcastHierarchyUpdate()
            }
        }
    }

    private func broadcastHierarchyUpdate() {
        guard muscle.hasSubscribers else { return }
        guard let hierarchyTree = bagman.refreshAccessibilityData() else { return }

        let elements = bagman.snapshotElements()
        let tree = hierarchyTree.map { bagman.convertHierarchyNode($0) }

        let payload = Interface(timestamp: Date(), elements: elements, tree: tree)

        // Update hash for polling comparison
        bagman.lastHierarchyHash = elements.hashValue

        if let data = try? JSONEncoder().encode(ResponseEnvelope(message: .interface(payload))) {
            broadcastToSubscribed(data)
        }

        insideJobLogger.debug("Broadcast hierarchy update to \(self.muscle.subscribedClients.count) subscriber(s)")
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
        guard let hierarchyTree = bagman.refreshAccessibilityData() else { return }

        let elements = bagman.snapshotElements()
        let tree = hierarchyTree.map { bagman.convertHierarchyNode($0) }

        // Compute hash of current hierarchy
        let currentHash = elements.hashValue

        // Only broadcast if hierarchy changed
        if currentHash != bagman.lastHierarchyHash {
            bagman.lastHierarchyHash = currentHash

            // Broadcast hierarchy with tree
            let payload = Interface(timestamp: Date(), elements: elements, tree: tree)
            if let data = try? JSONEncoder().encode(ResponseEnvelope(message: .interface(payload))) {
                broadcastToSubscribed(data)
            }

            // Also broadcast screen when hierarchy changes
            broadcastScreen()

            // Notify stakeout of screen change (for inactivity timeout)
            stakeout?.noteScreenChange()

            insideJobLogger.debug("Polling detected change, broadcast to \(self.muscle.subscribedClients.count) subscriber(s)")
        }
    }

    // MARK: - Interface Sending

    func sendInterface(requestId: String? = nil, respond: @escaping (Data) -> Void) async {
        // Only wait if there's actually something to wait for — avoids adding latency
        // to the common idle case where the app is fully at rest.
        if bagman.hasActiveNavigationTransition() {
            _ = await bagman.waitForNavigationTransition()
        } else if bagman.hasActiveAnimations() {
            _ = await bagman.waitForAnimationsToSettle(timeout: 0.5)
            await bagman.yieldToMainQueue()
        }

        guard let hierarchyTree = bagman.refreshAccessibilityData() else {
            sendMessage(.error("Could not access root view"), requestId: requestId, respond: respond)
            return
        }

        let elements = bagman.snapshotElements()
        let tree = hierarchyTree.map { bagman.convertHierarchyNode($0) }

        let payload = Interface(timestamp: Date(), elements: elements, tree: tree)
        sendMessage(.interface(payload), requestId: requestId, respond: respond)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
