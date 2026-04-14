#if canImport(UIKit)
#if DEBUG
import Foundation
import TheScore

extension TheBrains {

    /// Execute a command through the full interaction pipeline:
    /// refresh → snapshot → execute → settle → delta → result.
    /// Returns the ActionResult for TheInsideJob to send/broadcast.
    func executeCommand(_ message: ClientMessage) async -> ActionResult {
        switch message {
        case .activate, .increment, .decrement, .performCustomAction,
             .editAction, .setPasteboard, .getPasteboard, .resignFirstResponder:
            return await executeAccessibilityAction(message)

        case .touchTap, .touchLongPress, .touchSwipe, .touchDrag,
             .touchPinch, .touchRotate, .touchTwoFingerTap,
             .touchDrawPath, .touchDrawBezier:
            return await executeTouchGesture(message)

        case .typeText(let target):
            return await performInteraction(command: message) { await self.executeTypeText(target) }
        case .scroll(let target):
            return await performInteraction(command: message) { await self.executeScroll(target) }
        case .scrollToVisible(let target):
            return await performInteraction(command: message) { await self.executeScrollToVisible(target) }
        case .elementSearch(let target):
            return await performElementSearch(target: target, command: message)
        case .scrollToEdge(let target):
            return await performInteraction(command: message) { await self.executeScrollToEdge(target) }
        case .waitFor(let target):
            return await performWaitFor(target: target)
        case .explore:
            return await performExplore()

        default:
            insideJobLogger.error("Unhandled message type in executeCommand")
            var builder = ActionResultBuilder(method: .activate, screenName: stash.lastScreenName, screenId: stash.lastScreenId)
            builder.message = "Unhandled command"
            return builder.failure(errorKind: .unsupported)
        }
    }

    // MARK: - Interaction Pipeline

    /// Standard interaction: refresh → snapshot → execute → delta.
    func performInteraction(
        command: ClientMessage,
        interaction: () async -> TheSafecracker.InteractionResult
    ) async -> ActionResult {
        refresh()
        let before = captureBeforeState()
        let result = await interaction()

        return await actionResultWithDelta(
            success: result.success,
            method: result.method,
            message: result.message,
            value: result.value,
            before: before,
            target: command.actionTarget
        )
    }

    /// Element search: dedicated path because the scroll loop manages its own refresh/settle.
    func performElementSearch(
        target: ElementSearchTarget,
        command: ClientMessage
    ) async -> ActionResult {
        refresh()
        let before = captureBeforeState()
        let result = await executeElementSearch(target)

        return await actionResultWithDelta(
            success: result.success,
            method: result.method,
            message: result.message,
            value: result.value,
            errorKind: result.success ? nil : .elementNotFound,
            before: before
        ).adding(scrollSearchResult: result.scrollSearchResult)
    }

    /// Wait for an element to appear or disappear.
    func performWaitFor(target: WaitForTarget) async -> ActionResult {
        refresh()
        let before = captureBeforeState()
        let result = await executeWaitFor(target)

        return await actionResultWithDelta(
            success: result.success,
            method: .waitFor,
            message: result.message,
            errorKind: result.success ? nil : .timeout,
            before: before
        )
    }

    /// Execute the wait_for polling loop.
    private func executeWaitFor(_ target: WaitForTarget) async -> TheSafecracker.InteractionResult {
        let elementTarget = target.elementTarget
        let deadline = ContinuousClock.now + .seconds(target.resolvedTimeout)
        let start = CFAbsoluteTimeGetCurrent()

        stash.refresh()
        if target.resolvedAbsent {
            if !stash.hasTarget(elementTarget) {
                return .init(success: true, method: .waitFor, message: "absent confirmed after 0.0s", value: nil)
            }
        } else {
            if stash.hasTarget(elementTarget) {
                return .init(success: true, method: .waitFor, message: "matched immediately", value: nil)
            }
        }

        while ContinuousClock.now < deadline {
            _ = await tripwire.waitForAllClear(timeout: 1.0)
            stash.refresh()
            let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
            if target.resolvedAbsent {
                if !stash.hasTarget(elementTarget) {
                    return .init(success: true, method: .waitFor, message: "absent confirmed after \(elapsed)s", value: nil)
                }
            } else {
                if stash.hasTarget(elementTarget) {
                    return .init(success: true, method: .waitFor, message: "matched after \(elapsed)s", value: nil)
                }
            }
        }

        let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
        let reason = target.resolvedAbsent ? "element still present" : "element not found"
        return .failure(.waitFor, message: "timed out after \(elapsed)s (\(reason))")
    }

    /// Full screen exploration.
    func performExplore() async -> ActionResult {
        refresh()
        let before = captureBeforeState()

        let manifest = await exploreAndPrune()
        let afterSnapshot = stash.selectElements()

        let delta = stash.computeDelta(
            before: before.snapshot, after: afterSnapshot,
            afterTree: stash.currentHierarchy, isScreenChange: false
        )

        let exploreElements = stash.toWire(afterSnapshot)

        var builder = ActionResultBuilder(method: .explore, snapshot: afterSnapshot)
        builder.interfaceDelta = delta
        return builder.success(
            exploreResult: ExploreResult(
                elements: exploreElements,
                scrollCount: manifest.scrollCount,
                containersExplored: manifest.exploredContainers.count,
                containersSkippedObscured: manifest.skippedObscuredContainers,
                explorationTime: manifest.explorationTime
            )
        )
    }

    // MARK: - Grouped Dispatch Helpers

    private func executeAccessibilityAction(_ message: ClientMessage) async -> ActionResult {
        switch message {
        case .activate(let target):
            return await performInteraction(command: message) { await self.executeActivate(target) }
        case .increment(let target):
            return await performInteraction(command: message) { await self.executeIncrement(target) }
        case .decrement(let target):
            return await performInteraction(command: message) { await self.executeDecrement(target) }
        case .performCustomAction(let target):
            return await performInteraction(command: message) { await self.executeCustomAction(target) }
        case .editAction(let target):
            return await performInteraction(command: message) { await self.executeEditAction(target) }
        case .setPasteboard(let target):
            return await performInteraction(command: message) { await self.executeSetPasteboard(target) }
        case .getPasteboard:
            return await performInteraction(command: message) { self.executeGetPasteboard() }
        case .resignFirstResponder:
            return await performInteraction(command: message) { await self.executeResignFirstResponder() }
        default:
            var builder = ActionResultBuilder(method: .activate, screenName: nil, screenId: nil)
            builder.message = "Unhandled"
            return builder.failure(errorKind: .unsupported)
        }
    }

    private func executeTouchGesture(_ message: ClientMessage) async -> ActionResult {
        switch message {
        case .touchTap(let target):
            return await performInteraction(command: message) { await self.executeTap(target) }
        case .touchLongPress(let target):
            return await performInteraction(command: message) { await self.executeLongPress(target) }
        case .touchSwipe(let target):
            return await performInteraction(command: message) { await self.executeSwipe(target) }
        case .touchDrag(let target):
            return await performInteraction(command: message) { await self.executeDrag(target) }
        case .touchPinch(let target):
            return await performInteraction(command: message) { await self.executePinch(target) }
        case .touchRotate(let target):
            return await performInteraction(command: message) { await self.executeRotate(target) }
        case .touchTwoFingerTap(let target):
            return await performInteraction(command: message) { await self.executeTwoFingerTap(target) }
        case .touchDrawPath(let target):
            return await performInteraction(command: message) { await self.executeDrawPath(target) }
        case .touchDrawBezier(let target):
            return await performInteraction(command: message) { await self.executeDrawBezier(target) }
        default:
            var builder = ActionResultBuilder(method: .activate, screenName: nil, screenId: nil)
            builder.message = "Unhandled"
            return builder.failure(errorKind: .unsupported)
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
