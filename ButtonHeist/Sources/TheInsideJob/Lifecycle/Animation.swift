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
        brains.recordSentState()
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

        guard let initial = brains.refreshAndSnapshot() else {
            sendMessage(.error("Could not access root view"), requestId: requestId, respond: respond)
            return
        }

        // Fast path: tree already changed since the last response
        let lastHash = brains.lastSentState?.treeHash ?? 0
        if lastHash != 0, initial.wireHash != lastHash {
            let delta = brains.computeDelta(before: before, afterSnapshot: initial.snapshot)
            if let result = evaluateChange(
                delta: delta, afterSnapshot: initial.snapshot, expectation: expectation,
                start: start, round: 0, message: "already changed (0.0s)"
            ) {
                sendMessage(.actionResult(result), requestId: requestId, respond: respond)
                brains.recordSentState(treeHash: initial.wireHash)
                return
            }
        }

        // Slow path: poll until a change lands or we time out
        let deadline = CFAbsoluteTimeGetCurrent() + timeout
        var beforeWireHash = initial.wireHash
        var round = 0

        while CFAbsoluteTimeGetCurrent() < deadline {
            let remaining = deadline - CFAbsoluteTimeGetCurrent()
            guard remaining > 0 else { break }

            _ = await tripwire.waitForAllClear(timeout: min(remaining, 1.0))
            guard let current = brains.refreshAndSnapshot() else { continue }
            round += 1

            if current.wireHash == beforeWireHash { continue }

            let delta = brains.computeDelta(before: before, afterSnapshot: current.snapshot)
            let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)

            if let result = evaluateChange(
                delta: delta, afterSnapshot: current.snapshot, expectation: expectation,
                start: start, round: round, message: "changed after \(elapsed)s (\(round) rounds)"
            ) {
                sendMessage(.actionResult(result), requestId: requestId, respond: respond)
                brains.recordSentState(treeHash: current.wireHash)
                return
            }

            beforeWireHash = current.wireHash
            insideJobLogger.debug("wait_for_change round \(round): \(delta.kind.rawValue), expectation not yet met")
        }

        // Timeout
        let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
        let afterSnapshot: [TheStash.ScreenElement]
        if let current = brains.refreshAndSnapshot() {
            afterSnapshot = current.snapshot
        } else {
            afterSnapshot = []
        }
        let delta = brains.computeDelta(before: before, afterSnapshot: afterSnapshot)
        var builder = ActionResultBuilder(method: .waitForChange, snapshot: afterSnapshot)
        builder.message = expectation != nil
            ? "timed out after \(elapsed)s — expectation not met"
            : "timed out after \(elapsed)s — no change detected"
        builder.interfaceDelta = delta
        sendMessage(.actionResult(builder.failure(errorKind: .timeout)), requestId: requestId, respond: respond)
        brains.recordSentState()
    }

    // MARK: - Wait For Change Helpers

    private func evaluateChange(
        delta: InterfaceDelta,
        afterSnapshot: [TheStash.ScreenElement],
        expectation: ActionExpectation?,
        start: CFAbsoluteTime,
        round: Int,
        message: String
    ) -> ActionResult? {
        var builder = ActionResultBuilder(method: .waitForChange, snapshot: afterSnapshot)
        builder.interfaceDelta = delta

        guard let expectation else {
            builder.message = message
            return builder.success()
        }

        guard expectation.validate(against: builder.success()).met else { return nil }

        let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
        builder.message = "expectation met after \(elapsed)s (\(round) rounds)"
        return builder.success()
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
