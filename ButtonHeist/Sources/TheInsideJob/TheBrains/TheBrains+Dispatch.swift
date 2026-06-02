#if canImport(UIKit)
#if DEBUG
import Foundation
import TheScore

extension TheBrains {

    // MARK: - Command Dispatch

    /// Execute a command through the full interaction pipeline:
    /// refresh → snapshot → execute → settle → explore semantic state → delta → result.
    /// Returns the ActionResult for TheInsideJob to send.
    func executeCommand(_ message: ClientMessage) async -> ActionResult {
        // Rotor mode holds a single cursor only while consecutive rotor steps
        // run on the same host. Any other interaction exits rotor mode and drops
        // the held cursor.
        if case .rotor = message {} else {
            stash.clearRotorCursor()
        }
        switch message {
        case .activate(let target):
            return await performInteraction(method: .activate) { await self.actions.executeActivate(target) }
        case .increment(let target):
            return await performInteraction(method: .increment) { await self.actions.executeIncrement(target) }
        case .decrement(let target):
            return await performInteraction(method: .decrement) { await self.actions.executeDecrement(target) }
        case .performCustomAction(let target):
            return await performInteraction(method: .customAction) { await self.actions.executeCustomAction(target) }
        case .rotor(let target):
            return await performRotor(target)
        case .editAction(let target):
            return await performInteraction(method: .editAction) { await self.actions.executeEditAction(target) }
        case .setPasteboard(let target):
            return await performInteraction(method: .setPasteboard) { await self.actions.executeSetPasteboard(target) }
        case .resignFirstResponder:
            return await performInteraction(method: .resignFirstResponder) { await self.actions.executeResignFirstResponder() }
        case .oneFingerTap(let target):
            return await performInteraction(method: .syntheticTap) { await self.actions.executeTap(target) }
        case .longPress(let target):
            return await performInteraction(method: .syntheticLongPress) { await self.actions.executeLongPress(target) }
        case .swipe(let target):
            return await performInteraction(method: .syntheticSwipe) { await self.actions.executeSwipe(target) }
        case .drag(let target):
            return await performInteraction(method: .syntheticDrag) { await self.actions.executeDrag(target) }
        case .typeText(let target):
            return await performInteraction(method: .typeText) { await self.actions.executeTypeText(target) }
        case .scroll(let target):
            return await performInteraction(method: .scroll) { await self.navigation.executeScroll(target) }
        case .scrollToVisible(let target):
            return await performInteraction(method: .scrollToVisible) { await self.navigation.executeScrollToVisible(target) }
        case .elementSearch(let target):
            return await performElementSearch(target: target, method: .elementSearch)
        case .scrollToEdge(let target):
            return await performInteraction(method: .scrollToEdge) { await self.navigation.executeScrollToEdge(target) }
        case .wait(let target):
            return await performWait(target: target)
        case .heistPlan(let plan):
            return await executeHeistPlan(plan)
        case .clientHello, .authenticate, .requestInterface,
             .ping, .status, .requestScreen, .getPasteboard:
            preconditionFailure("Non-executable client message reached action execution: \(message.wireType.rawValue)")
        }
    }

    func executePasteboardRead() -> ActionResult {
        let result = actions.executeGetPasteboard()
        return ActionResult(
            success: result.success,
            method: result.method,
            message: result.message,
            errorKind: result.success ? nil : Self.actionErrorKind(for: result),
            payload: result.payload
        )
    }

    // MARK: - Interaction Pipeline

    func performInteraction(
        method: ActionMethod,
        interaction: () async -> TheSafecracker.InteractionResult
    ) async -> ActionResult {
        guard stash.commitVisibleObservation() != nil else {
            return treeUnavailableResult(method: method)
        }
        let before = postActionObservation.captureSemanticState()
        let result = await interaction()

        return await postActionObservation.actionResultWithDelta(
            success: result.success,
            method: result.method,
            message: result.message,
            payload: result.payload,
            errorKind: Self.actionErrorKind(for: result),
            before: before
        )
    }

    func performRotor(_ target: RotorTarget) async -> ActionResult {
        return await performInteraction(method: .rotor) { await self.actions.executeRotor(target) }
    }

    /// Element search: dedicated path because the scroll loop manages its own refresh/settle.
    func performElementSearch(
        target: ElementSearchTarget,
        method: ActionMethod
    ) async -> ActionResult {
        await performElementSearch(
            elementTarget: target.elementTarget,
            direction: target.direction,
            method: method
        )
    }

    func performElementSearch(
        elementTarget: ElementTarget?,
        direction: ScrollDirection,
        method: ActionMethod
    ) async -> ActionResult {
        guard stash.commitVisibleObservation() != nil else {
            return treeUnavailableResult(method: method)
        }
        let before = postActionObservation.captureSemanticState()
        let result = await navigation.executeElementSearch(elementTarget: elementTarget, direction: direction)

        return await postActionObservation.actionResultWithDelta(
            success: result.success,
            method: result.method,
            message: result.message,
            payload: result.payload,
            errorKind: result.success ? nil : .elementNotFound,
            before: before
        )
    }

    /// Wait until an accessibility predicate is satisfied.
    ///
    /// `present`/`absent` poll the current interface for an element matching the
    /// predicate; `changed` rides the settle loop until the change predicate is
    /// met (or any tree change, for `screen`/`elements`).
    func performWait(target: WaitTarget) async -> ActionResult {
        switch target.predicate {
        case .state(.present(let predicate)):
            return await performPresenceWait(predicate: predicate, absent: false, timeout: target.timeout)
        case .state(.absent(let predicate)):
            return await performPresenceWait(predicate: predicate, absent: true, timeout: target.timeout)
        case .state(let stateClause):
            return await performStateWait(state: stateClause, timeout: target.timeout)
        case .changed:
            return await executeWaitForChange(
                timeout: target.resolvedTimeout,
                expectation: target.predicate
            )
        }
    }

    /// Poll the current interface until a composite state predicate (e.g. `.all`)
    /// holds, or the timeout expires. Single `present`/`absent` states use
    /// `performPresenceWait` so they keep ambiguity diagnostics; this path
    /// evaluates the whole `State` against each fresh observation.
    func performStateWait(state: AccessibilityPredicate.State, timeout: Double?) async -> ActionResult {
        guard stash.commitVisibleObservation() != nil else {
            return treeUnavailableResult(method: .wait)
        }
        let before = postActionObservation.captureSemanticState()
        let deadline = ContinuousClock.now + .seconds(min(timeout ?? 10, 30))
        let start = CFAbsoluteTimeGetCurrent()

        var met = state.evaluatePresence(in: before.interface.projectedElements)
        while !met, ContinuousClock.now < deadline {
            _ = await tripwire.waitForAllClear(timeout: 1.0)
            guard stash.commitVisibleObservation() != nil else {
                return treeUnavailableResult(method: .wait)
            }
            _ = await navigation.exploreAndPrune()
            met = state.evaluatePresence(in: stash.semanticInterfaceWithHash().interface.projectedElements)
        }

        let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
        return await postActionObservation.actionResultWithDelta(
            success: met,
            method: .wait,
            message: met ? "conditions met after \(elapsed)s" : "timed out after \(elapsed)s waiting for: \(state)",
            payload: nil,
            errorKind: met ? nil : .timeout,
            before: before
        )
    }

    func performPresenceWait(
        predicate: ElementPredicate,
        absent: Bool,
        timeout: Double?
    ) async -> ActionResult {
        guard stash.commitVisibleObservation() != nil else {
            return treeUnavailableResult(method: .wait)
        }
        let before = postActionObservation.captureSemanticState()
        let result = await executeWaitFor(
            elementTarget: .predicate(predicate, ordinal: 0),
            absent: absent,
            timeout: min(timeout ?? 10, 30)
        )
        let errorKind: ErrorKind? = {
            guard !result.success else { return nil }
            return Self.waitForErrorKind(for: result.failureKind)
        }()

        return await postActionObservation.actionResultWithDelta(
            success: result.success,
            method: .wait,
            message: result.message,
            payload: result.payload,
            errorKind: errorKind,
            before: before
        )
    }

    /// Execute the presence polling loop.
    private func executeWaitFor(
        elementTarget: ElementTarget,
        absent: Bool,
        timeout: Double
    ) async -> TheSafecracker.InteractionResult {
        let deadline = ContinuousClock.now + .seconds(timeout)
        let start = CFAbsoluteTimeGetCurrent()

        guard await refreshSemanticStateForWait(target: elementTarget) else {
            return .failure(.wait, message: TheBrains.treeUnavailableMessage, failureKind: .treeUnavailable)
        }
        var resolution = stash.resolveTarget(elementTarget)
        if let result = waitForResult(resolution: resolution, absent: absent, elapsed: nil) {
            return result
        }

        while ContinuousClock.now < deadline {
            _ = await tripwire.waitForAllClear(timeout: 1.0)
            guard await refreshSemanticStateForWait(target: elementTarget) else {
                return .failure(.wait, message: TheBrains.treeUnavailableMessage, failureKind: .treeUnavailable)
            }
            let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
            resolution = stash.resolveTarget(elementTarget)
            if let result = waitForResult(resolution: resolution, absent: absent, elapsed: elapsed) {
                return result
            }
        }

        let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
        let message = waitForTimeoutMessage(
            absent: absent,
            elapsed: elapsed,
            target: elementTarget,
            resolution: resolution
        )
        return .failure(.wait, message: message, failureKind: .timeout)
    }

    private func waitForResult(
        resolution: TheStash.TargetResolution,
        absent: Bool,
        elapsed: String?
    ) -> TheSafecracker.InteractionResult? {
        switch (absent, resolution) {
        case (true, .notFound):
            return .success(method: .wait, message: "absent confirmed after \(elapsed ?? "0.0")s")
        case (true, .ambiguous(_, let diagnostics)):
            return .failure(.wait, message: diagnostics)
        case (true, .resolved):
            return nil
        case (false, .resolved):
            let message = elapsed.map { "matched after \($0)s" } ?? "matched immediately"
            return .success(method: .wait, message: message)
        case (false, .ambiguous(_, let diagnostics)):
            return .failure(.wait, message: diagnostics)
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
            "known: \(stash.knownElementCount) elements",
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
            "Next: get_interface() to inspect current elements, " +
                "then retry wait with an exact predicate."
        )
        return parts.joined(separator: "; ")
    }

    private func waitForTargetDescription(_ target: ElementTarget) -> String {
        switch target {
        case .predicate(let predicate, let ordinal):
            var description = TheStash.Diagnostics.formatMatcher(predicate)
            if let ordinal {
                description += " ordinal=\(ordinal)"
            }
            return description
        }
    }

    static func waitForErrorKind(for failureKind: TheSafecracker.FailureKind?) -> ErrorKind {
        switch failureKind {
        case .treeUnavailable:
            return .actionFailed
        case .timeout:
            return .timeout
        case .inputValidation:
            return .validationError
        case .targetUnavailable:
            return .elementNotFound
        case .none:
            return .elementNotFound
        }
    }

    static func actionErrorKind(for result: TheSafecracker.InteractionResult) -> ErrorKind? {
        guard !result.success else { return nil }
        switch result.failureKind {
        case .treeUnavailable:
            return .actionFailed
        case .timeout:
            return .timeout
        case .inputValidation:
            return .validationError
        case .targetUnavailable:
            return .elementNotFound
        case .none:
            return .actionFailed
        }
    }

    /// `wait_for` predicates observe the fresh semantic hierarchy, not just the
    /// latest parsed page. Exploration may stop as soon as the target is found;
    /// if it is not found, all reachable scroll containers are scanned.
    private func refreshSemanticStateForWait(target: ElementTarget) async -> Bool {
        guard stash.commitVisibleObservation() != nil else { return false }
        _ = await navigation.exploreAndPrune(target: target)
        return true
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
