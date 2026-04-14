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
        lastSentTreeHash = brains.wireHash(brains.selectElements())
        lastSentBeforeState = brains.captureBeforeState()
        lastSentScreenId = brains.screenId
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
        let currentSnapshot = brains.selectElements()
        let currentHash = brains.wireHash(currentSnapshot)

        // Fast path: tree already changed since the last response
        if let result = checkAlreadyChanged(
            before: before, currentSnapshot: currentSnapshot, currentHash: currentHash, expectation: expectation
        ) {
            sendMessage(.actionResult(result), requestId: requestId, respond: respond)
            lastSentTreeHash = currentHash
            lastSentBeforeState = brains.captureBeforeState()
            lastSentScreenId = brains.screenId
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

            let afterSnapshot = brains.selectElements()
            let afterHash = brains.wireHash(afterSnapshot)
            round += 1

            if afterHash == beforeWireHash { continue }

            let delta = brains.computeDelta(before: before, afterSnapshot: afterSnapshot)

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
        let afterSnapshot = brains.selectElements()
        let delta = brains.computeDelta(before: before, afterSnapshot: afterSnapshot)
        var timeoutBuilder = ActionResultBuilder(method: .waitForChange, snapshot: afterSnapshot)
        timeoutBuilder.message = expectation != nil
            ? "timed out after \(elapsed)s — expectation not met"
            : "timed out after \(elapsed)s — no change detected"
        timeoutBuilder.interfaceDelta = delta
        let actionResult = timeoutBuilder.failure(errorKind: .timeout)
        sendMessage(.actionResult(actionResult), requestId: requestId, respond: respond)
        lastSentTreeHash = brains.wireHash(afterSnapshot)
        lastSentBeforeState = brains.captureBeforeState()
        lastSentScreenId = brains.screenId
    }

    // MARK: - Wait For Change Helpers

    private func checkAlreadyChanged(
        before: TheBrains.BeforeState,
        currentSnapshot: [TheStash.ScreenElement],
        currentHash: Int,
        expectation: ActionExpectation?
    ) -> ActionResult? {
        guard lastSentTreeHash != 0, currentHash != lastSentTreeHash else { return nil }

        let delta = brains.computeDelta(before: before, afterSnapshot: currentSnapshot)
        var builder = ActionResultBuilder(method: .waitForChange, snapshot: currentSnapshot)
        builder.interfaceDelta = delta

        if let expectation {
            guard expectation.validate(against: builder.success()).met else { return nil }
        }

        builder.message = "already changed (0.0s)"
        return builder.success()
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
