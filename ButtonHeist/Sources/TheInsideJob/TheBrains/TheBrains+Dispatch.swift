#if canImport(UIKit)
#if DEBUG
import Foundation
import TheScore

extension TheBrains {

    // MARK: - Command Dispatch

    /// Execute a command through the full interaction pipeline:
    /// refresh → snapshot → execute → settle → delta → result.
    /// Returns the ActionResult for TheInsideJob to send/broadcast.
    func executeCommand(_ message: ClientMessage) async -> ActionResult {
        let pendingRotorResultToken = stash.preparePendingRotorResult(
            targetedHeistId: message.pendingRotorResultTargetHeistId
        )
        defer {
            if let pendingRotorResultToken {
                stash.clearPendingRotorResult(consumedToken: pendingRotorResultToken)
            }
        }

        switch message {
        case .activate, .increment, .decrement, .performCustomAction,
             .rotor,
             .editAction, .setPasteboard, .getPasteboard, .resignFirstResponder:
            return await executeAccessibilityAction(message)

        case .touchTap, .touchLongPress, .touchSwipe, .touchDrag,
             .touchPinch, .touchRotate, .touchTwoFingerTap,
             .touchDrawPath, .touchDrawBezier:
            return await executeTouchGesture(message)

        case .typeText(let target):
            return await performInteraction(command: message) { await self.actions.executeTypeText(target) }
        case .scroll(let target):
            return await performInteraction(command: message) { await self.navigation.executeScroll(target) }
        case .scrollToVisible(let target):
            return await performScrollToVisible(target: target, command: message)
        case .elementSearch(let target):
            return await performElementSearch(target: target, command: message)
        case .scrollToEdge(let target):
            return await performInteraction(command: message) { await self.navigation.executeScrollToEdge(target) }
        case .waitFor(let target):
            return await performWaitFor(target: target)
        case .explore:
            return await performExplore()

        default:
            insideJobLogger.error("Unhandled message type in executeCommand")
            return unsupportedCommandResult(for: message, context: "executeCommand")
        }
    }

    // MARK: - Interaction Pipeline

    /// Standard interaction: refresh → snapshot → execute → delta.
    func performInteraction(
        command: ClientMessage,
        interaction: () async -> TheSafecracker.InteractionResult
    ) async -> ActionResult {
        guard refresh() != nil else {
            return treeUnavailableResult(method: Self.diagnosticMethod(for: command))
        }
        let before = captureBeforeState()
        let result = await interaction()

        return await actionResultWithDelta(
            success: result.success,
            method: result.method,
            message: result.message,
            value: result.value,
            rotorResult: result.rotorResult,
            before: before
        )
    }

    /// Scroll-to-visible can use an off-viewport entry from the most recent
    /// exploration. Preserve that union across the dispatch refresh that
    /// otherwise narrows `currentScreen` back to the live viewport.
    func performScrollToVisible(
        target: ScrollToVisibleTarget,
        command: ClientMessage
    ) async -> ActionResult {
        let screenBeforeRefresh = stash.currentScreen
        guard refresh() != nil else {
            return treeUnavailableResult(method: Self.diagnosticMethod(for: command))
        }
        let recordedScreen = recordedScreenIfCurrentViewportStillMatches(screenBeforeRefresh)
        let before = captureBeforeState()
        let result = await navigation.executeScrollToVisible(target, recordedScreen: recordedScreen)

        return await actionResultWithDelta(
            success: result.success,
            method: result.method,
            message: result.message,
            value: result.value,
            before: before
        )
    }

    /// Element search: dedicated path because the scroll loop manages its own refresh/settle.
    func performElementSearch(
        target: ElementSearchTarget,
        command: ClientMessage
    ) async -> ActionResult {
        let screenBeforeRefresh = stash.currentScreen
        guard refresh() != nil else {
            return treeUnavailableResult(method: Self.diagnosticMethod(for: command))
        }
        let recordedScreen = recordedScreenIfCurrentViewportStillMatches(screenBeforeRefresh)
        let before = captureBeforeState()
        let result = await navigation.executeElementSearch(target, recordedScreen: recordedScreen)

        var enriched = await actionResultWithDelta(
            success: result.success,
            method: result.method,
            message: result.message,
            value: result.value,
            errorKind: result.success ? nil : .elementNotFound,
            before: before
        )
        if let scrollSearch = result.scrollSearchResult {
            enriched.payload = .scrollSearch(scrollSearch)
        }
        return enriched
    }

    private func recordedScreenIfCurrentViewportStillMatches(_ screenBeforeRefresh: Screen) -> Screen? {
        let currentViewportIds = stash.currentScreen.heistIds
        guard !screenBeforeRefresh.elements.isEmpty,
              currentViewportIds.isSubset(of: screenBeforeRefresh.heistIds) else {
            return nil
        }
        return screenBeforeRefresh
    }

    /// Wait for an element to appear or disappear.
    func performWaitFor(target: WaitForTarget) async -> ActionResult {
        guard refresh() != nil else {
            return treeUnavailableResult(method: .waitFor)
        }
        let before = captureBeforeState()
        let result = await executeWaitFor(target)
        let errorKind: ErrorKind? = {
            guard !result.success else { return nil }
            switch result.failureKind {
            case .treeUnavailable: return .actionFailed
            case .timeout, .none: return .timeout
            }
        }()

        return await actionResultWithDelta(
            success: result.success,
            method: .waitFor,
            message: result.message,
            errorKind: errorKind,
            before: before
        )
    }

    /// Execute the wait_for polling loop.
    private func executeWaitFor(_ target: WaitForTarget) async -> TheSafecracker.InteractionResult {
        let elementTarget = target.elementTarget
        let deadline = ContinuousClock.now + .seconds(target.resolvedTimeout)
        let start = CFAbsoluteTimeGetCurrent()

        guard stash.refresh() != nil else {
            return .failure(.waitFor, message: TheBrains.treeUnavailableMessage, failureKind: .treeUnavailable)
        }
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
            guard stash.refresh() != nil else {
                return .failure(.waitFor, message: TheBrains.treeUnavailableMessage, failureKind: .treeUnavailable)
            }
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
        return .failure(.waitFor, message: "timed out after \(elapsed)s (\(reason))", failureKind: .timeout)
    }

    /// Full screen exploration.
    func performExplore() async -> ActionResult {
        guard refresh() != nil else {
            return treeUnavailableResult(method: .explore)
        }
        let before = captureBeforeState()

        let manifest = await navigation.exploreAndPrune()
        let afterSnapshot = stash.selectElements()

        let delta = TheStash.InterfaceDiff.computeDelta(
            before: before.snapshot, after: afterSnapshot,
            beforeTree: before.tree,
            beforeTreeHash: before.treeHash,
            afterTree: stash.wireTree(),
            isScreenChange: false
        )

        let exploreElements = TheStash.WireConversion.toWire(afterSnapshot)

        var builder = ActionResultBuilder(method: .explore, snapshot: afterSnapshot)
        builder.interfaceDelta = delta
        return builder.success(
            exploreResult: ExploreResult(
                elements: exploreElements,
                scrollCount: manifest.scrollCount,
                containersExplored: manifest.exploredContainers.count,
                explorationTime: manifest.explorationTime
            )
        )
    }

    // MARK: - Grouped Dispatch Helpers

    private func executeAccessibilityAction(_ message: ClientMessage) async -> ActionResult {
        switch message {
        case .activate(let target):
            return await performInteraction(command: message) { await self.actions.executeActivate(target) }
        case .increment(let target):
            return await performInteraction(command: message) { await self.actions.executeIncrement(target) }
        case .decrement(let target):
            return await performInteraction(command: message) { await self.actions.executeDecrement(target) }
        case .performCustomAction(let target):
            return await performInteraction(command: message) { await self.actions.executeCustomAction(target) }
        case .rotor(let target):
            return await performInteraction(command: message) {
                await self.actions.executeRotor(target)
            }
        case .editAction(let target):
            return await performInteraction(command: message) { await self.actions.executeEditAction(target) }
        case .setPasteboard(let target):
            return await performInteraction(command: message) { await self.actions.executeSetPasteboard(target) }
        case .getPasteboard:
            return await performInteraction(command: message) { self.actions.executeGetPasteboard() }
        case .resignFirstResponder:
            return await performInteraction(command: message) { await self.actions.executeResignFirstResponder() }
        default:
            return unsupportedCommandResult(for: message, context: "executeAccessibilityAction")
        }
    }

    private func executeTouchGesture(_ message: ClientMessage) async -> ActionResult {
        switch message {
        case .touchTap(let target):
            return await performInteraction(command: message) { await self.actions.executeTap(target) }
        case .touchLongPress(let target):
            return await performInteraction(command: message) { await self.actions.executeLongPress(target) }
        case .touchSwipe(let target):
            return await performInteraction(command: message) { await self.actions.executeSwipe(target) }
        case .touchDrag(let target):
            return await performInteraction(command: message) { await self.actions.executeDrag(target) }
        case .touchPinch(let target):
            return await performInteraction(command: message) { await self.actions.executePinch(target) }
        case .touchRotate(let target):
            return await performInteraction(command: message) { await self.actions.executeRotate(target) }
        case .touchTwoFingerTap(let target):
            return await performInteraction(command: message) { await self.actions.executeTwoFingerTap(target) }
        case .touchDrawPath(let target):
            return await performInteraction(command: message) { await self.actions.executeDrawPath(target) }
        case .touchDrawBezier(let target):
            return await performInteraction(command: message) { await self.actions.executeDrawBezier(target) }
        default:
            return unsupportedCommandResult(for: message, context: "executeTouchGesture")
        }
    }

    private func unsupportedCommandResult(for message: ClientMessage, context: String) -> ActionResult {
        var builder = ActionResultBuilder(
            method: Self.diagnosticMethod(for: message),
            screenName: stash.lastScreenName,
            screenId: stash.lastScreenId
        )
        builder.message = "Unsupported command '\(message.canonicalName)' in \(context)"
        return builder.failure(errorKind: .unsupported)
    }

    /// Map a ClientMessage to the ActionMethod that best identifies it for diagnostic output.
    /// Handshake/control messages have no natural ActionMethod and fall back to `.activate`.
    private static func diagnosticMethod(for message: ClientMessage) -> ActionMethod {
        switch message {
        case .activate: return .activate
        case .increment: return .increment
        case .decrement: return .decrement
        case .performCustomAction: return .customAction
        case .rotor: return .rotor
        case .editAction: return .editAction
        case .setPasteboard: return .setPasteboard
        case .getPasteboard: return .getPasteboard
        case .resignFirstResponder: return .resignFirstResponder
        case .touchTap: return .syntheticTap
        case .touchLongPress: return .syntheticLongPress
        case .touchSwipe: return .syntheticSwipe
        case .touchDrag: return .syntheticDrag
        case .touchPinch: return .syntheticPinch
        case .touchRotate: return .syntheticRotate
        case .touchTwoFingerTap: return .syntheticTwoFingerTap
        case .touchDrawPath, .touchDrawBezier: return .syntheticDrawPath
        case .typeText: return .typeText
        case .scroll: return .scroll
        case .scrollToVisible: return .scrollToVisible
        case .elementSearch: return .elementSearch
        case .scrollToEdge: return .scrollToEdge
        case .waitForIdle: return .waitForIdle
        case .waitFor: return .waitFor
        case .waitForChange: return .waitForChange
        case .explore: return .explore
        case .clientHello, .authenticate, .requestInterface, .subscribe, .unsubscribe,
             .ping, .status, .requestScreen, .startRecording, .stopRecording, .watch:
            return .activate
        }
    }

}

private extension ClientMessage {

    var pendingRotorResultTargetHeistId: String? {
        switch self {
        case .activate(let target),
             .increment(let target),
             .decrement(let target):
            return target.exactHeistId
        case .performCustomAction(let target):
            return target.elementTarget.exactHeistId
        case .rotor(let target):
            return target.currentHeistId
        case .touchTap(let target):
            return target.elementTarget?.exactHeistId
        case .touchLongPress(let target):
            return target.elementTarget?.exactHeistId
        case .touchSwipe(let target):
            return target.elementTarget?.exactHeistId
        case .touchDrag(let target):
            return target.elementTarget?.exactHeistId
        case .touchPinch(let target):
            return target.elementTarget?.exactHeistId
        case .touchRotate(let target):
            return target.elementTarget?.exactHeistId
        case .touchTwoFingerTap(let target):
            return target.elementTarget?.exactHeistId
        case .typeText(let target):
            return target.elementTarget?.exactHeistId
        case .clientHello,
             .authenticate,
             .requestInterface,
             .subscribe,
             .unsubscribe,
             .ping,
             .status,
             .touchDrawPath,
             .touchDrawBezier,
             .editAction,
             .scroll,
             .scrollToVisible,
             .elementSearch,
             .scrollToEdge,
             .resignFirstResponder,
             .setPasteboard,
             .getPasteboard,
             .waitForIdle,
             .waitFor,
             .waitForChange,
             .requestScreen,
             .explore,
             .startRecording,
             .stopRecording,
             .watch:
            return nil
        }
    }
}

private extension ElementTarget {
    var exactHeistId: String? {
        if case .heistId(let heistId) = self {
            return heistId
        }
        return nil
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
