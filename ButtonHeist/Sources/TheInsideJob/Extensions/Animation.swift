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
    }

    // MARK: - Wait For Change Handler

    func handleWaitForChange(_ target: WaitForChangeTarget, requestId: String? = nil, respond: @escaping (Data) -> Void) async {
        brains.refresh()
        let before = brains.captureBeforeState()

        let timeout = target.resolvedTimeout
        let deadline = CFAbsoluteTimeGetCurrent() + timeout
        let start = CFAbsoluteTimeGetCurrent()
        let expectation = target.expect

        let beforeSnapshot = stash.selectElements()
        var beforeWireHash = TheStash.WireConversion.toWire(beforeSnapshot).hashValue
        var round = 0

        while CFAbsoluteTimeGetCurrent() < deadline {
            let remaining = deadline - CFAbsoluteTimeGetCurrent()
            guard remaining > 0 else { break }

            _ = await tripwire.waitForAllClear(timeout: min(remaining, 1.0))
            guard brains.refresh() != nil else { continue }

            let afterSnapshot = stash.selectElements()
            let afterWire = TheStash.WireConversion.toWire(afterSnapshot)
            let afterHash = afterWire.hashValue

            round += 1

            // No tree change this cycle — keep waiting
            if afterHash == beforeWireHash { continue }

            // Tree changed — compute delta and check expectation
            let afterVC = tripwire.topmostViewController().map(ObjectIdentifier.init)
            let afterElements = stash.currentHierarchy.sortedElements
            let isScreenChange = tripwire.isScreenChange(before: before.viewController, after: afterVC)
                || stash.burglar.isTopologyChanged(before: before.elements, after: afterElements)

            let delta = TheStash.WireConversion.computeDelta(
                before: before.snapshot, after: afterSnapshot,
                afterTree: stash.currentHierarchy, isScreenChange: isScreenChange
            )

            // No expectation → any change satisfies the wait
            guard let expectation else {
                let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
                let actionResult = ActionResult(
                    success: true,
                    method: .waitForChange,
                    message: "changed after \(elapsed)s (\(round) rounds)",
                    interfaceDelta: delta,
                    screenName: afterSnapshot.screenName,
                    screenId: afterSnapshot.screenId
                )
                sendMessage(.actionResult(actionResult), requestId: requestId, respond: respond)
                return
            }

            // Build a synthetic ActionResult to evaluate the expectation against
            let checkResult = ActionResult(
                success: true, method: .waitForChange,
                interfaceDelta: delta,
                screenName: afterSnapshot.screenName,
                screenId: afterSnapshot.screenId
            )
            let validation = expectation.validate(against: checkResult)
            if validation.met {
                let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
                let actionResult = ActionResult(
                    success: true,
                    method: .waitForChange,
                    message: "expectation met after \(elapsed)s (\(round) rounds)",
                    interfaceDelta: delta,
                    screenName: afterSnapshot.screenName,
                    screenId: afterSnapshot.screenId
                )
                sendMessage(.actionResult(actionResult), requestId: requestId, respond: respond)
                return
            }

            // Expectation not met — update baseline and keep waiting
            beforeWireHash = afterHash
            insideJobLogger.debug("wait_for_change round \(round): \(delta.kind.rawValue), expectation not yet met")
        }

        // Timeout — return what we have
        let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
        let afterSnapshot = stash.selectElements()
        let afterVC = tripwire.topmostViewController().map(ObjectIdentifier.init)
        let isScreenChange = tripwire.isScreenChange(before: before.viewController, after: afterVC)
        let delta = TheStash.WireConversion.computeDelta(
            before: before.snapshot, after: afterSnapshot,
            afterTree: stash.currentHierarchy, isScreenChange: isScreenChange
        )
        let message = expectation != nil
            ? "timed out after \(elapsed)s — expectation not met"
            : "timed out after \(elapsed)s — no change detected"
        let actionResult = ActionResult(
            success: false,
            method: .waitForChange,
            message: message,
            errorKind: .timeout,
            interfaceDelta: delta,
            screenName: afterSnapshot.screenName,
            screenId: afterSnapshot.screenId
        )
        sendMessage(.actionResult(actionResult), requestId: requestId, respond: respond)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
