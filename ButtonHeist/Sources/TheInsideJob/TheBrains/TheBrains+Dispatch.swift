#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

internal struct RuntimeActionExecution: Sendable, Equatable {
    internal let result: ActionResult
    internal let expectationBaseline: SettledCapture?
}

struct ActionTiming {
    enum Phase {
        case beforeObservation
        case targetResolution
        case actionDispatch
        case interaction
        case finalSemanticEvidence
        case resultAssembly
    }

    private let actionStart: RuntimeElapsed.Instant
    private var beforeObservation: ElapsedMilliseconds?
    private var targetResolution: ElapsedMilliseconds?
    private var actionDispatch: ElapsedMilliseconds?
    private var interaction: ElapsedMilliseconds?
    private var finalSemanticEvidence: ElapsedMilliseconds?
    private var resultAssembly: ElapsedMilliseconds?

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
        case .beforeObservation: Self.record(duration, in: &beforeObservation)
        case .targetResolution: Self.record(duration, in: &targetResolution)
        case .actionDispatch: Self.record(duration, in: &actionDispatch)
        case .interaction: Self.record(duration, in: &interaction)
        case .finalSemanticEvidence: Self.record(duration, in: &finalSemanticEvidence)
        case .resultAssembly: Self.record(duration, in: &resultAssembly)
        }
    }

    func freeze(endedAt: RuntimeElapsed.Instant = RuntimeElapsed.now) -> ActionPerformanceTiming {
        ActionPerformanceTiming(
            beforeObservationMs: beforeObservation,
            targetResolutionMs: targetResolution,
            actionDispatchMs: actionDispatch,
            interactionMs: interaction,
            finalSemanticEvidenceMs: finalSemanticEvidence,
            resultAssemblyMs: resultAssembly,
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
        await executeRuntimeActionWithBaseline(command).result
    }

    func executeRuntimeActionWithBaseline(
        _ command: ResolvedHeistActionCommand,
        expectationBaselineScope: SemanticObservationScope? = nil
    ) async -> RuntimeActionExecution {
        let expectationBaseline = await interactionCoordinator.settledCapture(
            scope: expectationBaselineScope
        )

        clearRotorCursorBeforeNonRotorAction(command)
        let result: ActionResult
        switch command {
        case .activate(let target):
            result = await performInteraction(payload: .activate) { timing in
                await self.actions.executeActivate(target, timing: &timing)
            }
        case .increment(let target):
            result = await performInteraction(payload: .increment) { timing in
                await self.actions.executeIncrement(target, timing: &timing)
            }
        case .decrement(let target):
            result = await performInteraction(payload: .decrement) { timing in
                await self.actions.executeDecrement(target, timing: &timing)
            }
        case .customAction(let name, let target):
            result = await performInteraction(payload: .customAction) { timing in
                await self.actions.executeCustomAction(name: name, target: target, timing: &timing)
            }
        case .dismiss:
            result = await performInteraction(payload: .dismiss) { _ in
                await self.actions.executeDismiss()
            }
        case .magicTap:
            result = await performInteraction(payload: .magicTap) { _ in
                await self.actions.executeMagicTap()
            }
        case .rotor(let selection, let target, let direction):
            result = await performInteraction(payload: .rotor(nil)) { timing in
                await self.actions.executeRotor(
                    selection: selection,
                    target: target,
                    direction: direction,
                    timing: &timing
                )
            }
        case .editAction(let target):
            result = await performInteraction(payload: .editAction) { _ in
                await self.actions.executeEditAction(target)
            }
        case .setPasteboard(let target):
            result = await performInteraction(payload: .setPasteboard(nil)) { _ in
                await self.actions.executeSetPasteboard(target)
            }
        case .takeScreenshot:
            result = await executeTakeScreenshot()
        case .dismissKeyboard:
            result = await performInteraction(payload: .dismissKeyboard) { _ in
                await self.actions.executeResignFirstResponder()
            }
        case .oneFingerTap(let target):
            result = await performInteraction(payload: .oneFingerTap) { _ in
                await self.actions.executeTap(target)
            }
        case .longPress(let target):
            result = await performInteraction(payload: .longPress) { _ in
                await self.actions.executeLongPress(target)
            }
        case .swipe(let target):
            result = await performInteraction(payload: .swipe) { _ in
                await self.actions.executeSwipe(target)
            }
        case .drag(let target):
            result = await performInteraction(payload: .drag) { _ in
                await self.actions.executeDrag(target)
            }
        case .typeText(let payload):
            result = await executeTypeText(payload)
        case .scroll(let target):
            result = await executeViewportScroll(target)
        case .scrollToVisible(let target):
            result = await executeViewportScrollToVisible(target)
        case .scrollToEdge(let target):
            result = await executeViewportScrollToEdge(target)
        }
        return RuntimeActionExecution(
            result: result,
            expectationBaseline: expectationBaseline
        )
    }

    private func executeTypeText(_ payload: ResolvedTypeTextTarget) async -> ActionResult {
        await performInteraction(
            payload: .typeText(nil),
            afterStateValue: { context in
                context.resolvedElementId.flatMap {
                    self.actions.typeTextPayload(resolvedElementId: $0, in: context.committedBaseline)
                }
            },
            interaction: { _ in
                await self.actions.executeTypeText(text: payload.text, target: payload.target)
            }
        )
    }

    private func executeViewportScroll(_ target: ResolvedScrollTarget) async -> ActionResult {
        await performInteraction(
            payload: .scroll,
            postActionCommitScope: .discovery
        ) { _ in
            await self.navigation.executeScroll(target)
        }
    }

    private func executeViewportScrollToVisible(_ target: ResolvedAccessibilityTarget) async -> ActionResult {
        await performInteraction(
            payload: .scrollToVisible,
            postActionCommitScope: .discovery
        ) { _ in
            await self.navigation.executeScrollToVisible(target: target)
        }
    }

    private func executeViewportScrollToEdge(_ target: ResolvedScrollToEdgeTarget) async -> ActionResult {
        await performInteraction(
            payload: .scrollToEdge,
            postActionCommitScope: .discovery
        ) { _ in
            await self.navigation.executeScrollToEdge(target)
        }
    }

    func executeSemanticDiscovery() async -> Navigation.InterfaceExplorationResult? {
        await navigation.exploreScreen(exitPosition: .origin)
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
    private func performInteraction(
        payload: ActionResult.Payload,
        beforeStateScope: SemanticObservationScope = .visible,
        postActionCommitScope: SemanticObservationScope = .visible,
        afterStateValue: ((ActionPayloadEvidence) -> String?)? = nil,
        interaction: (inout ActionTiming) async -> TheSafecracker.ActionDispatchResult
    ) async -> ActionResult {
        guard semanticObservationIsActive else {
            return runtimeInactiveResult(payload: payload)
        }

        var timing = ActionTiming()
        let beforeStart = RuntimeElapsed.now
        guard let before = await interactionCoordinator.admittedBaseline(scope: beforeStateScope) else {
            return treeUnavailableResult(payload: payload)
        }
        timing.record(.beforeObservation, since: beforeStart)
        let notificationWindow = vault.accessibilityNotifications.beginActionWindow()
        defer { notificationWindow.cancel() }

        let demand = vault.semanticObservationStream.beginActiveObservationDemand()
        defer { demand.cancel() }

        let interactionStart = RuntimeElapsed.now
        let result = await interaction(&timing)
        timing.record(.interaction, since: interactionStart)

        return await interactionCoordinator.settleAfterAction(
            dispatchResult: result,
            timing: timing,
            afterStateValue: afterStateValue,
            before: before,
            postActionCommitScope: postActionCommitScope,
            notificationWindow: notificationWindow
        )
    }

    func performWait(step: ResolvedWaitRuntimeInput) async -> ActionResult {
        guard semanticObservationIsActive else {
            return runtimeInactiveResult(payload: .wait)
        }
        let result = await interactionCoordinator.waitForPredicate(step)
        return result.outcome.actionResult
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
