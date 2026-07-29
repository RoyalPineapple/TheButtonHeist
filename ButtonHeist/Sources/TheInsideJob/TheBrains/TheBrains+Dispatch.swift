#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

struct ActionTiming {
    enum Phase {
        case targetResolution
        case actionDispatch
        case interaction
    }

    private let actionStart: RuntimeElapsed.Instant
    private var targetResolution: ElapsedMilliseconds?
    private var actionDispatch: ElapsedMilliseconds?
    private var interaction: ElapsedMilliseconds?

    init(startedAt: RuntimeElapsed.Instant = RuntimeElapsed.now) {
        actionStart = startedAt
    }

    mutating func record(
        _ phase: Phase,
        since start: RuntimeElapsed.Instant,
        endedAt: RuntimeElapsed.Instant = RuntimeElapsed.now
    ) {
        let duration = RuntimeElapsed.milliseconds(since: start, endedAt: endedAt)
        switch phase {
        case .targetResolution: Self.record(duration, in: &targetResolution)
        case .actionDispatch: Self.record(duration, in: &actionDispatch)
        case .interaction: Self.record(duration, in: &interaction)
        }
    }

    func freeze(endedAt: RuntimeElapsed.Instant = RuntimeElapsed.now) -> ActionPerformanceTiming {
        ActionPerformanceTiming(
            targetResolutionMs: targetResolution,
            actionDispatchMs: actionDispatch,
            interactionMs: interaction,
            totalMs: RuntimeElapsed.milliseconds(since: actionStart, endedAt: endedAt)
        )
    }

    private static func record(_ duration: ElapsedMilliseconds, in slot: inout ElapsedMilliseconds?) {
        precondition(slot == nil, "action timing phase may only be recorded once")
        slot = duration
    }
}

extension TheBrains {
    func executeRuntimeAction(_ command: ResolvedHeistActionCommand) async -> ActionResult {
        guard semanticObservationIsActive else {
            return runtimeInactiveResult(payload: command.actionResultPayload)
        }
        let observationBoundary = await vault.semanticObservationStream.stateOwner
            .observationBoundary(scope: .visible)
        let dispatch = await dispatchRuntimeAction(command)
        let observation: ActionResultObservationEvidence
        switch await vault.semanticObservationStream.refreshVisibleObservation() {
        case .committed:
            observation = .observed(
                await vault.semanticObservationStream.stateOwner
                    .evidence(after: observationBoundary)
            )
        case .unavailable:
            observation = .none
        }
        let outcome: ActionResultOutcome = switch dispatch.outcome {
        case .success:
            .success
        case .failure(let failure):
            .failure(Self.actionFailureKind(for: failure))
        }
        return ActionResult(
            outcome: outcome,
            payload: dispatch.payload,
            message: dispatch.message,
            observation: observation,
            subjectEvidence: dispatch.subjectEvidence,
            activationTrace: dispatch.activationTrace,
            screenActionHandler: dispatch.screenActionHandler,
            timing: dispatch.timing
        )
    }

    func dispatchRuntimeAction(
        _ command: ResolvedHeistActionCommand
    ) async -> TheSafecracker.ActionDispatchResult {
        clearRotorCursorBeforeNonRotorAction(command)
        let startedAt = RuntimeElapsed.now
        var timing = ActionTiming(startedAt: startedAt)
        let result = await dispatchRawRuntimeAction(command, timing: &timing)
        timing.record(.interaction, since: startedAt)
        return result.withTiming(timing.freeze())
    }

    private func dispatchRawRuntimeAction(
        _ command: ResolvedHeistActionCommand,
        timing: inout ActionTiming
    ) async -> TheSafecracker.ActionDispatchResult {
        switch command {
        case .activate(let target):
            return await actions.executeActivate(target, timing: &timing)
        case .increment(let target):
            return await actions.executeIncrement(target, timing: &timing)
        case .decrement(let target):
            return await actions.executeDecrement(target, timing: &timing)
        case .customAction(let name, let target):
            return await actions.executeCustomAction(name: name, target: target, timing: &timing)
        case .dismiss:
            return await actions.executeDismiss()
        case .magicTap:
            return await actions.executeMagicTap()
        case .rotor(let selection, let target, let direction):
            return await actions.executeRotor(
                selection: selection,
                target: target,
                direction: direction,
                timing: &timing
            )
        case .editAction(let target):
            return await actions.executeEditAction(target)
        case .setPasteboard(let target):
            return await actions.executeSetPasteboard(target)
        case .takeScreenshot:
            return await dispatchTakeScreenshot()
        case .dismissKeyboard:
            return await actions.executeResignFirstResponder()
        case .oneFingerTap(let target):
            return await actions.executeTap(target)
        case .longPress(let target):
            return await actions.executeLongPress(target)
        case .swipe(let target):
            return await actions.executeSwipe(target)
        case .drag(let target):
            return await actions.executeDrag(target)
        case .typeText(let payload):
            return await actions.executeTypeText(text: payload.text, target: payload.target)
        case .scroll(let target):
            return await navigation.executeScroll(target)
        case .scrollToVisible(let target):
            return await navigation.executeScrollToVisible(target: target)
        case .scrollToEdge(let target):
            return await navigation.executeScrollToEdge(target)
        }
    }

    func executeSemanticDiscovery() async -> Navigation.InterfaceExplorationResult? {
        await navigation.fullGraph()
    }

    private func clearRotorCursorBeforeNonRotorAction(_ command: ResolvedHeistActionCommand) {
        if case .rotor = command {} else {
            vault.clearRotorCursor()
        }
    }

    func executePasteboardRead() -> ActionResult {
        let result = actions.executeGetPasteboard()
        switch result.outcome {
        case .success:
            return .success(payload: result.payload, message: result.message)
        case .failure(let failureKind):
            return .failure(
                payload: result.payload,
                failureKind: Self.actionFailureKind(for: failureKind),
                message: result.message
            )
        }
    }
    func performWait(step: WaitStep) async -> ActionResult {
        guard semanticObservationIsActive else {
            return runtimeInactiveResult(payload: .wait)
        }
        do {
            let plan = try HeistPlan(body: [.wait(step)])
            return await executeSingleStepPlan(plan, fallbackPayload: .wait)
        } catch {
            return .failure(
                payload: .wait,
                failureKind: .validationError,
                message: "could not resolve wait predicate: \(error)"
            )
        }
    }

    func executeSingleStepPlan(
        _ plan: HeistPlan,
        fallbackPayload: ActionResult.Payload
    ) async -> ActionResult {
        let execution = await executeHeistPlan(plan)
        guard case .heist(let result?) = execution.payload,
              let actionResult = result.steps.first?.reportActionResult else {
            return .failure(
                payload: fallbackPayload,
                failureKind: execution.outcome.failureKind ?? .actionFailed,
                message: execution.message ?? "single-step heist produced no action result"
            )
        }
        return actionResult
    }

    nonisolated static func actionFailureKind(
        for failureKind: TheSafecracker.FailureKind
    ) -> ActionFailure.Kind {
        switch failureKind {
        case .actionFailed:
            return .actionFailed
        case .treeUnavailable:
            return .accessibilityTreeUnavailable
        case .timeout:
            return .timeout
        case .inputValidation:
            return .validationError
        case .targetUnavailable:
            return .elementNotFound
        }
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
