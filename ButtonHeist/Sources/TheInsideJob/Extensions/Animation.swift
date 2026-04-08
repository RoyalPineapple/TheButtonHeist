#if canImport(UIKit)
#if DEBUG
import UIKit
import TheScore

extension TheInsideJob {

    // MARK: - Wait For Idle Handler

    func handleWaitForIdle(_ target: WaitForIdleTarget, requestId: String? = nil, respond: @escaping (Data) -> Void) async {
        brains.refresh()
        let before = brains.captureBeforeState()
        let timeout = min(target.timeout ?? 5.0, 60.0)
        let settled = await tripwire.waitForAllClear(timeout: timeout)

        let actionResult = await brains.actionResultWithDelta(
            success: true,
            method: .waitForIdle,
            message: settled ? "UI idle" : "Timed out after \(timeout)s, UI may still be animating",
            before: before
        )
        sendMessage(.actionResult(actionResult), requestId: requestId, respond: respond)
        lastSentTreeHash = TheStash.WireConversion.toWire(stash.selectElements()).hashValue
        lastSentBeforeState = brains.captureBeforeState()
        lastSentScreenId = stash.lastScreenId
    }

    // MARK: - Wait For Change Handler

    func handleWaitForChange(_ target: WaitForChangeTarget, requestId: String? = nil, respond: @escaping (Data) -> Void) async {
        let timeout = target.resolvedTimeout
        let start = CFAbsoluteTimeGetCurrent()
        let expectation = target.expect

        // Capture baseline BEFORE refresh — this corresponds to the tree state
        // at the time of the last response, giving us a proper before-state for
        // element-level diffs on both the fast and slow paths.
        let before = brains.captureBeforeState()

        brains.refresh()
        let currentSnapshot = stash.selectElements()
        let currentHash = TheStash.WireConversion.toWire(currentSnapshot).hashValue

        // Fast path: tree already changed since the last response
        if let result = checkAlreadyChanged(
            before: before, currentSnapshot: currentSnapshot, currentHash: currentHash, expectation: expectation
        ) {
            sendMessage(.actionResult(result), requestId: requestId, respond: respond)
            lastSentTreeHash = currentHash
            lastSentBeforeState = brains.captureBeforeState()
            lastSentScreenId = stash.lastScreenId
            return
        }

        // Slow path: poll until a change lands or we time out
        let deadline = CFAbsoluteTimeGetCurrent() + timeout
        var beforeWireHash = currentHash
        var round = 0

        while CFAbsoluteTimeGetCurrent() < deadline {
            let remaining = deadline - CFAbsoluteTimeGetCurrent()
            guard remaining > 0 else { break }

            _ = await tripwire.waitForAllClear(timeout: min(remaining, 1.0))
            guard brains.refresh() != nil else { continue }

            let afterSnapshot = stash.selectElements()
            let afterHash = TheStash.WireConversion.toWire(afterSnapshot).hashValue
            round += 1

            if afterHash == beforeWireHash { continue }

            let delta = computeDelta(before: before, afterSnapshot: afterSnapshot)

            if let result = evaluateChange(
                delta: delta, afterSnapshot: afterSnapshot, expectation: expectation,
                start: start, round: round
            ) {
                sendMessage(.actionResult(result), requestId: requestId, respond: respond)
                lastSentTreeHash = afterHash
                lastSentBeforeState = brains.captureBeforeState()
                return
            }

            beforeWireHash = afterHash
            insideJobLogger.debug("wait_for_change round \(round): \(delta.kind.rawValue), expectation not yet met")
        }

        // Timeout
        let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
        let afterSnapshot = stash.selectElements()
        let delta = computeDelta(before: before, afterSnapshot: afterSnapshot)
        var timeoutBuilder = ActionResultBuilder(method: .waitForChange, snapshot: afterSnapshot)
        timeoutBuilder.message = expectation != nil
            ? "timed out after \(elapsed)s — expectation not met"
            : "timed out after \(elapsed)s — no change detected"
        timeoutBuilder.interfaceDelta = delta
        let actionResult = timeoutBuilder.failure(errorKind: .timeout)
        sendMessage(.actionResult(actionResult), requestId: requestId, respond: respond)
        lastSentTreeHash = TheStash.WireConversion.toWire(afterSnapshot).hashValue
        lastSentBeforeState = brains.captureBeforeState()
        lastSentScreenId = stash.lastScreenId
    }

    // MARK: - Wait For Change Helpers

    private func checkAlreadyChanged(
        before: TheBrains.BeforeState,
        currentSnapshot: [TheStash.ScreenElement],
        currentHash: Int,
        expectation: ActionExpectation?
    ) -> ActionResult? {
        guard lastSentTreeHash != 0, currentHash != lastSentTreeHash else { return nil }

        let delta = computeDelta(before: before, afterSnapshot: currentSnapshot)
        var builder = ActionResultBuilder(method: .waitForChange, snapshot: currentSnapshot)
        builder.interfaceDelta = delta

        if let expectation {
            guard expectation.validate(against: builder.success()).met else { return nil }
        }

        builder.message = "already changed (0.0s)"
        return builder.success()
    }

    private func computeDelta(before: TheBrains.BeforeState, afterSnapshot: [TheStash.ScreenElement]) -> InterfaceDelta {
        let afterVC = tripwire.topmostViewController().map(ObjectIdentifier.init)
        let afterElements = stash.currentHierarchy.sortedElements
        let isScreenChange = tripwire.isScreenChange(before: before.viewController, after: afterVC)
            || stash.burglar.isTopologyChanged(before: before.elements, after: afterElements)
        return TheStash.WireConversion.computeDelta(
            before: before.snapshot, after: afterSnapshot,
            afterTree: stash.currentHierarchy, isScreenChange: isScreenChange
        )
    }

    private func evaluateChange(
        delta: InterfaceDelta, afterSnapshot: [TheStash.ScreenElement],
        expectation: ActionExpectation?, start: CFAbsoluteTime, round: Int
    ) -> ActionResult? {
        let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
        var builder = ActionResultBuilder(method: .waitForChange, snapshot: afterSnapshot)
        builder.interfaceDelta = delta

        guard let expectation else {
            builder.message = "changed after \(elapsed)s (\(round) rounds)"
            return builder.success()
        }

        guard expectation.validate(against: builder.success()).met else { return nil }

        builder.message = "expectation met after \(elapsed)s (\(round) rounds)"
        return builder.success()
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
