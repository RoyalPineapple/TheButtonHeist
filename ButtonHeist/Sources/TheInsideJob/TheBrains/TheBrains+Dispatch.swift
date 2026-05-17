#if canImport(UIKit)
#if DEBUG
import Foundation
import TheScore

extension TheBrains {

    // MARK: - Command Dispatch

    /// Execute a command through the full interaction pipeline:
    /// refresh → snapshot → execute → settle → delta → result.
    /// Returns the ActionResult for TheInsideJob to send.
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

    /// Scroll-to-visible can use an off-screen entry from the most recent
    /// exploration. Preserve that union across the dispatch refresh that
    /// otherwise narrows `currentScreen` back to the latest parsed page.
    func performScrollToVisible(
        target: ScrollToVisibleTarget,
        command: ClientMessage
    ) async -> ActionResult {
        let screenBeforeRefresh = stash.currentScreen
        guard refresh() != nil else {
            return treeUnavailableResult(method: Self.diagnosticMethod(for: command))
        }
        let recordedScreen = recordedScreenIfFreshParseStillMatches(screenBeforeRefresh)
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
        guard refresh() != nil else {
            return treeUnavailableResult(method: Self.diagnosticMethod(for: command))
        }
        let before = captureBeforeState()
        let result = await navigation.executeElementSearch(target)

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

    private func recordedScreenIfFreshParseStillMatches(_ screenBeforeRefresh: Screen) -> Screen? {
        let currentVisibleIds = stash.currentScreen.interactionSnapshot.heistIds
        guard !screenBeforeRefresh.elements.isEmpty,
              currentVisibleIds.isSubset(of: screenBeforeRefresh.knownInterface.heistIds) else {
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
            return Self.waitForErrorKind(for: result.failureKind)
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

        guard await refreshSemanticStateForWait(target: elementTarget) else {
            return .failure(.waitFor, message: TheBrains.treeUnavailableMessage, failureKind: .treeUnavailable)
        }
        var resolution = stash.resolveTarget(elementTarget)
        if let result = waitForResult(resolution: resolution, absent: target.resolvedAbsent, elapsed: nil) {
            return result
        }

        while ContinuousClock.now < deadline {
            _ = await tripwire.waitForAllClear(timeout: 1.0)
            guard await refreshSemanticStateForWait(target: elementTarget) else {
                return .failure(.waitFor, message: TheBrains.treeUnavailableMessage, failureKind: .treeUnavailable)
            }
            let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
            resolution = stash.resolveTarget(elementTarget)
            if let result = waitForResult(resolution: resolution, absent: target.resolvedAbsent, elapsed: elapsed) {
                return result
            }
        }

        let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
        let message = waitForTimeoutMessage(
            absent: target.resolvedAbsent,
            elapsed: elapsed,
            target: elementTarget,
            resolution: resolution
        )
        return .failure(.waitFor, message: message, failureKind: .timeout)
    }

    private func waitForResult(
        resolution: TheStash.TargetResolution,
        absent: Bool,
        elapsed: String?
    ) -> TheSafecracker.InteractionResult? {
        switch (absent, resolution) {
        case (true, .notFound):
            return .init(
                success: true,
                method: .waitFor,
                message: "absent confirmed after \(elapsed ?? "0.0")s",
                value: nil
            )
        case (true, .ambiguous(_, let diagnostics)):
            return .failure(.waitFor, message: diagnostics)
        case (true, .resolved):
            return nil
        case (false, .resolved):
            let message = elapsed.map { "matched after \($0)s" } ?? "matched immediately"
            return .init(success: true, method: .waitFor, message: message, value: nil)
        case (false, .ambiguous(_, let diagnostics)):
            return .failure(.waitFor, message: diagnostics)
        case (false, .notFound):
            return nil
        }
    }

    private func waitForTimeoutMessage(
        absent: Bool,
        elapsed: String,
        target: ElementTarget,
        resolution: TheStash.TargetResolution
    ) -> String {
        let expected = absent ? "element to disappear" : "element to appear"
        let reason = absent ? "element still present" : "element not found"
        let diagnostics = resolution.diagnostics
        var parts = [
            "timed out after \(elapsed)s waiting for \(expected)",
            "expected: \(waitForTargetDescription(target))",
            "known: \(stash.currentScreen.elements.count) elements",
        ]
        if let screenId = stash.lastScreenId {
            parts.append("screen: \(screenId)")
        }
        if diagnostics.isEmpty {
            parts.append("last result: \(reason)")
        } else {
            parts.append("last result: \(reason): \(diagnostics)")
        }
        parts.append(
            "Next: get_interface(scope: \"full\") to inspect current elements, " +
                "then retry wait_for with a heistId or exact matcher."
        )
        return parts.joined(separator: "; ")
    }

    private func waitForTargetDescription(_ target: ElementTarget) -> String {
        switch target {
        case .heistId(let heistId):
            return "heistId=\"\(heistId)\""
        case .matcher(let matcher, let ordinal):
            var description = stash.formatMatcher(matcher)
            if let ordinal {
                description += " ordinal=\(ordinal)"
            }
            return description.isEmpty ? "<empty matcher>" : description
        }
    }

    static func waitForErrorKind(for failureKind: TheSafecracker.FailureKind?) -> ErrorKind {
        switch failureKind {
        case .treeUnavailable:
            return .actionFailed
        case .timeout:
            return .timeout
        case .none:
            return .elementNotFound
        }
    }

    /// `wait_for` predicates observe the fresh semantic hierarchy, not just the
    /// latest parsed page. Exploration may stop as soon as the target is found;
    /// if it is not found, all reachable scroll containers are scanned.
    private func refreshSemanticStateForWait(target: ElementTarget) async -> Bool {
        guard stash.refresh() != nil else { return false }
        _ = await navigation.exploreAndPrune(target: target)
        return true
    }

    /// Full screen exploration.
    func performExplore() async -> ActionResult {
        guard refresh() != nil else {
            return treeUnavailableResult(method: .explore)
        }
        let before = captureBeforeState()

        let manifest = await navigation.exploreAndPrune()
        let afterSnapshot = stash.selectElements()
        let afterTree = stash.wireTree()
        let accessibilityTrace = makeAccessibilityTrace(afterTree: afterTree, parentCapture: before.capture)

        let delta = deriveDelta(
            from: accessibilityTrace,
            before: before,
            isScreenChange: false
        )

        let exploreElements = TheStash.WireConversion.toWire(afterSnapshot)

        var builder = ActionResultBuilder(method: .explore, snapshot: afterSnapshot)
        builder.accessibilityDelta = delta
        builder.accessibilityTrace = accessibilityTrace
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
    static func diagnosticMethod(for message: ClientMessage) -> ActionMethod {
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
        case .clientHello, .authenticate, .requestInterface,
             .subscribe, .unsubscribe, .ping, .status, .requestScreen,
             .startRecording, .stopRecording, .watch:
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
