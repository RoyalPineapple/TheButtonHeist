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
            return treeUnavailableResult(method: fallbackMethod(for: command))
        }
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
        guard refresh() != nil else {
            return treeUnavailableResult(method: fallbackMethod(for: command))
        }
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
        guard refresh() != nil else {
            return treeUnavailableResult(method: .waitFor)
        }
        let before = captureBeforeState()
        let result = await executeWaitFor(target)
        let errorKind: ErrorKind? = result.success
            ? nil
            : (result.message == TheBrains.treeUnavailableMessage ? .actionFailed : .timeout)

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
            return .failure(.waitFor, message: TheBrains.treeUnavailableMessage)
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
                return .failure(.waitFor, message: TheBrains.treeUnavailableMessage)
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
        return .failure(.waitFor, message: "timed out after \(elapsed)s (\(reason))")
    }

    /// Full screen exploration.
    func performExplore() async -> ActionResult {
        guard refresh() != nil else {
            return treeUnavailableResult(method: .explore)
        }
        let before = captureBeforeState()

        let manifest = await exploreAndPrune()
        let afterSnapshot = stash.selectElements()

        let delta = stash.computeDelta(
            before: before.snapshot, after: afterSnapshot,
            beforeTree: before.tree,
            beforeTreeHash: before.treeHash,
            isScreenChange: false
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
            return unsupportedCommandResult(for: message, context: "executeAccessibilityAction")
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
            return unsupportedCommandResult(for: message, context: "executeTouchGesture")
        }
    }

    private func unsupportedCommandResult(for message: ClientMessage, context: String) -> ActionResult {
        var builder = ActionResultBuilder(
            method: Self.diagnosticMethod(for: message),
            screenName: stash.lastScreenName,
            screenId: stash.lastScreenId
        )
        builder.message = "Unsupported command '\(Self.commandName(for: message))' in \(context)"
        return builder.failure(errorKind: .unsupported)
    }

    private static func commandName(for message: ClientMessage) -> String {
        switch message {
        case .clientHello: return "client_hello"
        case .authenticate: return "authenticate"
        case .requestInterface: return "request_interface"
        case .subscribe: return "subscribe"
        case .unsubscribe: return "unsubscribe"
        case .ping: return "ping"
        case .status: return "status"
        case .requestScreen: return "request_screen"
        case .activate: return "activate"
        case .increment: return "increment"
        case .decrement: return "decrement"
        case .performCustomAction: return "perform_custom_action"
        case .editAction: return "edit_action"
        case .setPasteboard: return "set_pasteboard"
        case .getPasteboard: return "get_pasteboard"
        case .resignFirstResponder: return "resign_first_responder"
        case .touchTap: return "touch_tap"
        case .touchLongPress: return "touch_long_press"
        case .touchSwipe: return "touch_swipe"
        case .touchDrag: return "touch_drag"
        case .touchPinch: return "touch_pinch"
        case .touchRotate: return "touch_rotate"
        case .touchTwoFingerTap: return "touch_two_finger_tap"
        case .touchDrawPath: return "touch_draw_path"
        case .touchDrawBezier: return "touch_draw_bezier"
        case .typeText: return "type_text"
        case .scroll: return "scroll"
        case .scrollToVisible: return "scroll_to_visible"
        case .elementSearch: return "element_search"
        case .scrollToEdge: return "scroll_to_edge"
        case .waitForIdle: return "wait_for_idle"
        case .waitFor: return "wait_for"
        case .waitForChange: return "wait_for_change"
        case .explore: return "explore"
        case .startRecording: return "start_recording"
        case .stopRecording: return "stop_recording"
        case .watch: return "watch"
        }
    }

    /// Map a ClientMessage to the ActionMethod that best identifies it for diagnostic output.
    /// Handshake/control messages have no natural ActionMethod and fall back to `.activate`.
    private static func diagnosticMethod(for message: ClientMessage) -> ActionMethod {
        switch message {
        case .activate: return .activate
        case .increment: return .increment
        case .decrement: return .decrement
        case .performCustomAction: return .customAction
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

    /// Method to report when refresh fails before a command-specific executor runs.
    /// Mirrors `diagnosticMethod` for action commands; handshake/control messages
    /// (which never reach this path) fall back to `.activate`.
    private func fallbackMethod(for command: ClientMessage) -> ActionMethod {
        Self.diagnosticMethod(for: command)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
