#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

internal struct RuntimeActionExecution: Sendable, Equatable {
    internal let result: ActionResult
    internal let successfulActionBoundary: EvidenceContinuity.Boundary?
    internal let includesExpectationBaseline: Bool

    internal var expectationBaseline: SettledCapture? {
        includesExpectationBaseline ? successfulActionBoundary?.settledCapture : nil
    }
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
        clearRotorCursorBeforeNonRotorAction(command)
        let execution: RuntimeActionExecution
        switch command {
        case .activate(let target):
            execution = await performInteraction(payload: .activate) { timing in
                await self.actions.executeActivate(target, timing: &timing)
            }
        case .increment(let target):
            execution = await performInteraction(payload: .increment) { timing in
                await self.actions.executeIncrement(target, timing: &timing)
            }
        case .decrement(let target):
            execution = await performInteraction(payload: .decrement) { timing in
                await self.actions.executeDecrement(target, timing: &timing)
            }
        case .customAction(let name, let target):
            execution = await performInteraction(payload: .customAction) { timing in
                await self.actions.executeCustomAction(name: name, target: target, timing: &timing)
            }
        case .dismiss:
            execution = await performInteraction(payload: .dismiss) { _ in
                await self.actions.executeDismiss()
            }
        case .magicTap:
            execution = await performInteraction(payload: .magicTap) { _ in
                await self.actions.executeMagicTap()
            }
        case .rotor(let selection, let target, let direction):
            execution = await performInteraction(payload: .rotor(nil)) { timing in
                await self.actions.executeRotor(
                    selection: selection,
                    target: target,
                    direction: direction,
                    timing: &timing
                )
            }
        case .editAction(let target):
            execution = await performInteraction(payload: .editAction) { _ in
                await self.actions.executeEditAction(target)
            }
        case .setPasteboard(let target):
            execution = await performInteraction(payload: .setPasteboard(nil)) { _ in
                await self.actions.executeSetPasteboard(target)
            }
        case .takeScreenshot:
            execution = await executeScreenshotAction()
        case .dismissKeyboard:
            execution = await performInteraction(payload: .dismissKeyboard) { _ in
                await self.actions.executeResignFirstResponder()
            }
        case .oneFingerTap(let target):
            execution = await performInteraction(payload: .oneFingerTap) { _ in
                await self.actions.executeTap(target)
            }
        case .longPress(let target):
            execution = await performInteraction(payload: .longPress) { _ in
                await self.actions.executeLongPress(target)
            }
        case .swipe(let target):
            execution = await performInteraction(payload: .swipe) { _ in
                await self.actions.executeSwipe(target)
            }
        case .drag(let target):
            execution = await performInteraction(payload: .drag) { _ in
                await self.actions.executeDrag(target)
            }
        case .typeText(let payload):
            execution = await executeTypeText(payload)
        case .scroll(let target):
            execution = await executeViewportScroll(target)
        case .scrollToVisible(let target):
            execution = await executeViewportScrollToVisible(target)
        case .scrollToEdge(let target):
            execution = await executeViewportScrollToEdge(target)
        }
        return RuntimeActionExecution(
            result: execution.result,
            successfulActionBoundary: execution.successfulActionBoundary,
            includesExpectationBaseline: expectationBaselineScope != nil
        )
    }

    private func executeScreenshotAction() async -> RuntimeActionExecution {
        let execution = await executeTakeScreenshotWithBoundary()
        return RuntimeActionExecution(
            result: execution.result,
            successfulActionBoundary: execution.successfulActionBoundary,
            includesExpectationBaseline: false
        )
    }

    private func executeTypeText(_ payload: ResolvedTypeTextTarget) async -> RuntimeActionExecution {
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

    private func executeViewportScroll(_ target: ResolvedScrollTarget) async -> RuntimeActionExecution {
        await performInteraction(
            payload: .scroll,
            postActionCommitScope: .discovery
        ) { _ in
            await self.navigation.executeScroll(target)
        }
    }

    private func executeViewportScrollToVisible(
        _ target: ResolvedAccessibilityTarget
    ) async -> RuntimeActionExecution {
        await performInteraction(
            payload: .scrollToVisible,
            postActionCommitScope: .discovery
        ) { _ in
            await self.navigation.executeScrollToVisible(target: target)
        }
    }

    private func executeViewportScrollToEdge(
        _ target: ResolvedScrollToEdgeTarget
    ) async -> RuntimeActionExecution {
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
    ) async -> RuntimeActionExecution {
        guard semanticObservationIsActive else {
            return RuntimeActionExecution(
                result: runtimeInactiveResult(payload: payload),
                successfulActionBoundary: nil,
                includesExpectationBaseline: false
            )
        }

        var timing = ActionTiming()
        let beforeStart = RuntimeElapsed.now
        guard let before = await interactionCoordinator.admittedBaseline(scope: beforeStateScope) else {
            return RuntimeActionExecution(
                result: treeUnavailableResult(payload: payload),
                successfulActionBoundary: nil,
                includesExpectationBaseline: false
            )
        }
        timing.record(.beforeObservation, since: beforeStart)
        let notificationWindow = vault.accessibilityNotifications.beginActionWindow()
        defer { notificationWindow.cancel() }

        let actionBoundary = actionBoundary(
            from: before,
            scope: beforeStateScope,
            notificationCursor: notificationWindow.cursor
        )

        let demand = vault.semanticObservationStream.beginActiveObservationDemand()
        defer { demand.cancel() }

        let interactionStart = RuntimeElapsed.now
        let dispatchResult = await interaction(&timing)
        timing.record(.interaction, since: interactionStart)

        let actionResult = await interactionCoordinator.settleAfterAction(
            dispatchResult: dispatchResult,
            timing: timing,
            afterStateValue: afterStateValue,
            before: before,
            postActionCommitScope: postActionCommitScope,
            notificationWindow: notificationWindow
        )
        return RuntimeActionExecution(
            result: actionResult,
            successfulActionBoundary: dispatchResult.success ? actionBoundary : nil,
            includesExpectationBaseline: false
        )
    }

    private func actionBoundary(
        from baseline: ActionEvidenceProjector.Baseline,
        scope: SemanticObservationScope,
        notificationCursor: AccessibilityNotificationCursor
    ) -> EvidenceContinuity.Boundary {
        guard let settledObservationSequence = baseline.settledObservationSequence,
              let settledCapture = vault.semanticObservationStream.settledCapture(
                scope: scope,
                at: settledObservationSequence
              ) else {
            preconditionFailure("admitted action baseline must retain its settled capture")
        }
        return evidenceContinuityStore.captureBoundary(
            settledCapture: settledCapture,
            notificationCursor: notificationCursor
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
