#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

// MARK: - Action Execution
//
// Internal component of TheBrains. Two generic pipelines handle all element
// and point interactions. Each executeXxx method is a thin wrapper that feeds
// the pipeline a closure for the actual gesture or accessibility action.

protocol CustomActionExecutionInput {
    var actionElementTarget: ElementTarget? { get }
    var actionContainerTarget: ContainerMatcher? { get }
    var actionContainerOrdinal: Int? { get }
    var actionName: String { get }
}

protocol RotorExecutionInput {
    var rotorElementTarget: ElementTarget { get }
    var rotor: String? { get }
    var rotorIndex: Int? { get }
    var direction: RotorDirection? { get }
    var currentHeistId: HeistId? { get }
    var currentTextRange: TextRangeReference? { get }
}

protocol TapExecutionInput {
    var tapElementTarget: ElementTarget? { get }
    var pointX: Double? { get }
    var pointY: Double? { get }
}

protocol LongPressExecutionInput: TapExecutionInput {
    var duration: Double { get }
}

protocol SwipeExecutionInput {
    var swipeElementTarget: ElementTarget? { get }
    var startX: Double? { get }
    var startY: Double? { get }
    var endX: Double? { get }
    var endY: Double? { get }
    var direction: SwipeDirection? { get }
    var duration: Double? { get }
    var start: UnitPoint? { get }
    var end: UnitPoint? { get }
}

protocol DragExecutionInput {
    var dragElementTarget: ElementTarget? { get }
    var startX: Double? { get }
    var startY: Double? { get }
    var endX: Double { get }
    var endY: Double { get }
    var duration: Double? { get }
}

protocol PinchExecutionInput {
    var pinchElementTarget: ElementTarget? { get }
    var centerX: Double? { get }
    var centerY: Double? { get }
    var scale: Double { get }
    var spread: Double? { get }
    var duration: Double? { get }
}

protocol RotateExecutionInput {
    var rotateElementTarget: ElementTarget? { get }
    var centerX: Double? { get }
    var centerY: Double? { get }
    var angle: Double { get }
    var radius: Double? { get }
    var duration: Double? { get }
}

protocol TwoFingerTapExecutionInput {
    var twoFingerTapElementTarget: ElementTarget? { get }
    var centerX: Double? { get }
    var centerY: Double? { get }
    var spread: Double? { get }
}

protocol TypeTextExecutionInput {
    var text: String { get }
    var typeTextElementTarget: ElementTarget? { get }
}

/// Actions — element and point action execution.
///
/// Internal component of TheBrains. Calls into Navigation for
/// pre-action positioning (`ensureOnScreen`, `ensureFirstResponderOnScreen`).
@MainActor
final class Actions {

    // MARK: - Properties

    let stash: TheStash
    let safecracker: TheSafecracker
    let tripwire: TheTripwire
    let navigation: Navigation

    // MARK: - Init

    init(
        stash: TheStash,
        safecracker: TheSafecracker,
        tripwire: TheTripwire,
        navigation: Navigation
    ) {
        self.stash = stash
        self.safecracker = safecracker
        self.tripwire = tripwire
        self.navigation = navigation
    }

    // MARK: - Element Action Pipeline

    struct LiveElementActionContext {
        let normalizedTarget: TheStash.NormalizedTarget
        let resolvedTarget: TheStash.ResolvedTarget
        let liveTarget: TheStash.LiveActionTarget

        var screenElement: TheStash.ScreenElement { resolvedTarget.screenElement }
        var element: AccessibilityElement { resolvedTarget.element }
    }

    /// Unified pipeline for actions that target an element:
    /// ensureOnScreen → resolve → check interactivity → perform action.
    func performElementAction(
        target: ElementTarget,
        method: ActionMethod,
        recordedScreen: Screen? = nil,
        requireInteractive: Bool = true,
        deallocatedBoundary: String = "element action",
        preflight: (@MainActor (TheStash.ResolvedTarget) -> TheSafecracker.InteractionResult?)? = nil,
        action: @MainActor (LiveElementActionContext) async -> TheSafecracker.InteractionResult?
    ) async -> TheSafecracker.InteractionResult {
        let normalizedTarget = stash.normalizeTarget(target, in: recordedScreen ?? stash.currentScreen)
        let positioning = await navigation.ensureOnScreen(for: normalizedTarget)
        if let failure = positioning.failure {
            return .failure(failure.method ?? method, message: failure.message)
        }
        switch await resolveLiveElementActionContext(
            normalizedTarget: normalizedTarget,
            method: method,
            requireInteractive: requireInteractive,
            deallocatedBoundary: deallocatedBoundary,
            preflight: preflight
        ) {
        case .success(let context):
            return await action(context) ?? .failure(method, message: "\(method.rawValue) failed")
        case .failure(let result):
            return result
        case .retryableFailure(let result):
            return result
        }
    }

    private enum LiveElementActionContextResolution {
        case success(LiveElementActionContext)
        case failure(TheSafecracker.InteractionResult)
        case retryableFailure(TheSafecracker.InteractionResult)
    }

    private func resolveActivateTarget(
        _ target: ElementTarget,
        recordedScreen: Screen?
    ) async -> LiveElementActionContextResolution {
        let normalizedTarget = stash.normalizeTarget(target, in: recordedScreen ?? stash.currentScreen)
        let positioning = await navigation.ensureOnScreen(for: normalizedTarget)
        if let failure = positioning.failure {
            return .failure(.failure(failure.method ?? .activate, message: failure.message))
        }
        return await resolveLiveElementActionContext(
            normalizedTarget: normalizedTarget,
            method: .activate,
            requireInteractive: true,
            deallocatedBoundary: "element action",
            preflight: nil
        )
    }

    private func resolveLiveElementActionContext(
        normalizedTarget: TheStash.NormalizedTarget,
        method: ActionMethod,
        requireInteractive: Bool,
        deallocatedBoundary: String,
        preflight: (@MainActor (TheStash.ResolvedTarget) -> TheSafecracker.InteractionResult?)?
    ) async -> LiveElementActionContextResolution {
        let target = normalizedTarget.executableTarget
        let firstResolution = stash.resolveTarget(target)
        guard let firstResolved = firstResolution.resolved else {
            return .failure(.failure(
                .elementNotFound,
                message: normalizedTarget.diagnostics(firstResolution.diagnostics)
            ))
        }
        switch makeLiveElementActionContext(
            normalizedTarget: normalizedTarget,
            resolved: firstResolved,
            method: method,
            requireInteractive: requireInteractive,
            deallocatedBoundary: deallocatedBoundary,
            preflight: preflight
        ) {
        case .success(let context):
            return .success(context)
        case .failure(let result):
            return .failure(result)
        case .retryableFailure(let initialFailure):
            // Re-parse once to recover from cell reuse or a stale live ref, but
            // preserve the first-class live-target diagnostic if retry
            // positioning cannot recover the target.
            navigation.refresh()
            let retryPositioning = await navigation.ensureOnScreen(for: normalizedTarget)
            if retryPositioning.failure != nil {
                return .failure(initialFailure)
            }
            let retryResolution = stash.resolveTarget(target)
            guard let retryResolved = retryResolution.resolved else {
                return .failure(initialFailure)
            }
            return makeLiveElementActionContext(
                normalizedTarget: normalizedTarget,
                resolved: retryResolved,
                method: method,
                requireInteractive: requireInteractive,
                deallocatedBoundary: deallocatedBoundary,
                preflight: preflight
            )
        }
    }

    private func makeLiveElementActionContext(
        normalizedTarget: TheStash.NormalizedTarget,
        resolved: TheStash.ResolvedTarget,
        method: ActionMethod,
        requireInteractive: Bool,
        deallocatedBoundary: String,
        preflight: (@MainActor (TheStash.ResolvedTarget) -> TheSafecracker.InteractionResult?)?
    ) -> LiveElementActionContextResolution {
        if let failure = preflight?(resolved) {
            return .failure(failure)
        }
        let liveTargetResolution = stash.resolveLiveActionTarget(for: resolved)
        let liveTarget: TheStash.LiveActionTarget
        switch liveTargetResolution {
        case .resolved(let resolvedLiveTarget):
            liveTarget = resolvedLiveTarget
        case .objectUnavailable:
            guard let failure = liveActionTargetFailure(
                for: liveTargetResolution,
                method: method,
                resolved: resolved,
                deallocatedBoundary: deallocatedBoundary
            ) else {
                return .failure(.failure(method, message: "\(method.rawValue) failed"))
            }
            return .retryableFailure(annotateFailure(failure, with: normalizedTarget))
        case .geometryUnavailable:
            guard let failure = liveActionTargetFailure(
                for: liveTargetResolution,
                method: method,
                resolved: resolved,
                deallocatedBoundary: deallocatedBoundary
            ) else {
                return .failure(.failure(method, message: "\(method.rawValue) failed"))
            }
            return .failure(annotateFailure(failure, with: normalizedTarget))
        }
        if requireInteractive {
            switch TheStash.Interactivity.checkInteractivity(resolved.element, object: liveTarget.object) {
            case .blocked(let reason):
                return .failure(.failure(method, message: reason))
            case .interactive(let warning):
                if let warning { insideJobLogger.warning("\(warning)") }
            }
            guard TheStash.Interactivity.isInteractive(element: resolved.element, object: liveTarget.object) else {
                return .failure(.failure(
                    method,
                    message: ActionCapabilityDiagnostic.unsupportedElementAction(method, element: resolved.screenElement)
                ))
            }
        }
        return .success(LiveElementActionContext(
            normalizedTarget: normalizedTarget,
            resolvedTarget: resolved,
            liveTarget: liveTarget
        ))
    }

    /// Unified pipeline for gestures that target a screen point:
    /// ensureOnScreen (if element target) → resolve point → perform gesture.
    func performPointAction(
        elementTarget: ElementTarget?,
        pointX: Double?,
        pointY: Double?,
        method: ActionMethod,
        recordedScreen: Screen? = nil,
        action: (CGPoint) async -> Bool
    ) async -> TheSafecracker.InteractionResult {
        let normalizedTarget = elementTarget.map {
            stash.normalizeTarget($0, in: recordedScreen ?? stash.currentScreen)
        }
        if let normalizedTarget {
            let positioning = await navigation.ensureOnScreen(for: normalizedTarget)
            if let failure = positioning.failure {
                return .failure(failure.method ?? method, message: failure.message)
            }
        }
        switch resolveGesturePoint(from: normalizedTarget, pointX: pointX, pointY: pointY, method: method) {
        case .failure(let result):
            return result
        case .success(let point):
            if let failure = geometryFailure(method: method, field: "point", point: point) {
                return failure
            }
            let success = await action(point)
            if success { safecracker.showFingerprint(at: point) }
            let message = success ? nil : ActionCapabilityDiagnostic.gestureDispatchFailed(
                method: method,
                point: point,
                receiver: safecracker.tapReceiverDiagnostic(at: point)
            )
            return success
                ? .success(method: method)
                : .failure(method, message: message ?? "\(method.rawValue) failed")
        }
    }

    private func resolveGesturePoint(
        from normalizedTarget: TheStash.NormalizedTarget?,
        pointX: Double?,
        pointY: Double?,
        method: ActionMethod
    ) -> PointResolution {
        guard let normalizedTarget else {
            guard let xCoord = pointX, let yCoord = pointY else {
                return .failure(.failure(.elementNotFound, message: "No target specified"))
            }
            let point = CGPoint(x: xCoord, y: yCoord)
            if let failure = geometryFailure(method: method, field: "point", point: point) {
                return .failure(failure)
            }
            return .success(point)
        }
        let resolution = stash.resolveTarget(normalizedTarget.executableTarget)
        guard let resolved = resolution.resolved else {
            return .failure(.failure(.elementNotFound, message: normalizedTarget.diagnostics(resolution.diagnostics)))
        }
        guard case .resolved(let liveTarget) = stash.resolveLiveActionTarget(for: resolved) else {
            return .failure(.failure(
                method,
                message: normalizedTarget.diagnostics(
                    ActionCapabilityDiagnostic.gestureTargetUnavailable(
                        method: method,
                        element: resolved.screenElement,
                        isVisible: stash.visibleIds.contains(resolved.screenElement.heistId)
                    )
                )
            ))
        }
        let point = liveTarget.activationPoint
        if let failure = geometryFailure(method: method, field: "activationPoint", point: point) {
            return .failure(failure)
        }
        return .success(point)
    }

    private enum GestureFrameResolution {
        case success(CGRect)
        case failure(TheSafecracker.InteractionResult)
    }

    private func resolveGestureFrame(
        for normalizedTarget: TheStash.NormalizedTarget,
        method: ActionMethod
    ) -> GestureFrameResolution {
        let resolution = stash.resolveTarget(normalizedTarget.executableTarget)
        guard let resolved = resolution.resolved else {
            return .failure(.failure(.elementNotFound, message: normalizedTarget.diagnostics(resolution.diagnostics)))
        }
        guard case .resolved(let liveTarget) = stash.resolveLiveActionTarget(for: resolved) else {
            return .failure(.failure(
                method,
                message: normalizedTarget.diagnostics(
                    ActionCapabilityDiagnostic.gestureTargetUnavailable(
                        method: method,
                        element: resolved.screenElement,
                        isVisible: stash.visibleIds.contains(resolved.screenElement.heistId)
                    )
                )
            ))
        }
        let frame = liveTarget.frame
        if let message = GeometryValidation.validateRect(frame, field: "frame") {
            return .failure(.failure(
                method,
                message: "\(method.rawValue) failed: \(message)",
                failureKind: .inputValidation
            ))
        }
        return .success(frame)
    }

    private func geometryFailure(
        method: ActionMethod,
        field: String,
        point: CGPoint
    ) -> TheSafecracker.InteractionResult? {
        guard let message = GeometryValidation.validateScreenPoint(point, field: field) else { return nil }
        return .failure(
            method,
            message: "\(method.rawValue) failed: \(message)",
            failureKind: .inputValidation
        )
    }

    private func liveActionTargetFailure(
        for resolution: TheStash.LiveActionTargetResolution,
        method: ActionMethod,
        resolved: TheStash.ResolvedTarget,
        deallocatedBoundary: String
    ) -> TheSafecracker.InteractionResult? {
        switch resolution {
        case .resolved:
            return nil
        case .objectUnavailable:
            return .failure(
                .elementDeallocated,
                message: ActionCapabilityDiagnostic.elementDeallocated(
                    boundary: deallocatedBoundary,
                    element: resolved.screenElement,
                    isInflated: stash.visibleIds.contains(resolved.screenElement.heistId)
                )
            )
        case .geometryUnavailable:
            return .failure(
                method,
                message: ActionCapabilityDiagnostic.gestureTargetUnavailable(
                    method: method,
                    element: resolved.screenElement,
                    isVisible: stash.visibleIds.contains(resolved.screenElement.heistId)
                )
            )
        }
    }

    private func annotateFailure(
        _ result: TheSafecracker.InteractionResult,
        with normalizedTarget: TheStash.NormalizedTarget
    ) -> TheSafecracker.InteractionResult {
        guard let message = result.message else { return result }
        return .failure(
            result.method,
            message: normalizedTarget.diagnostics(message),
            payload: result.payload,
            failureKind: result.failureKind
        )
    }

    private func geometryFailure(
        method: ActionMethod,
        field: String,
        points: [CGPoint]
    ) -> TheSafecracker.InteractionResult? {
        guard let message = GeometryValidation.validateScreenPoints(points, field: field) else { return nil }
        return .failure(
            method,
            message: "\(method.rawValue) failed: \(message)",
            failureKind: .inputValidation
        )
    }

    // MARK: - Accessibility Actions

    func executeActivate(_ target: ElementTarget, recordedScreen: Screen? = nil) async -> TheSafecracker.InteractionResult {
        switch await resolveActivateTarget(target, recordedScreen: recordedScreen) {
        case .success(let context):
            return await ActivationPolicy(
                activate: stash.activate,
                refreshAndResolve: { await self.refreshAndResolveActivationTarget(context.normalizedTarget) },
                syntheticTap: safecracker.tap,
                showFingerprint: safecracker.showFingerprint,
                tapReceiverDiagnostic: safecracker.tapReceiverDiagnostic,
                screenBounds: { ScreenMetrics.current.bounds }
            ).apply(to: context.liveTarget)
        case .failure(let result), .retryableFailure(let result):
            return result
        }
    }

    private func refreshAndResolveActivationTarget(
        _ normalizedTarget: TheStash.NormalizedTarget
    ) async -> ActivationPolicy.RefreshResult {
        navigation.refresh()
        let retryPositioning = await navigation.ensureOnScreen(for: normalizedTarget)
        if let failure = retryPositioning.failure {
            return .failure(.failure(failure.method ?? .activate, message: failure.message))
        }
        let retryResolution = stash.resolveTarget(normalizedTarget.executableTarget)
        guard let retryResolved = retryResolution.resolved else {
            return .failure(.failure(
                .elementNotFound,
                message: normalizedTarget.diagnostics(retryResolution.diagnostics)
            ))
        }
        let retryLiveTargetResolution = stash.resolveLiveActionTarget(for: retryResolved)
        guard case .resolved(let retryLiveTarget) = retryLiveTargetResolution else {
            return activationRefreshFailure(
                for: retryLiveTargetResolution,
                resolved: retryResolved
            )
        }
        return .resolved(resolvedTarget: retryResolved, liveTarget: retryLiveTarget)
    }

    private func activationRefreshFailure(
        for resolution: TheStash.LiveActionTargetResolution,
        resolved: TheStash.ResolvedTarget
    ) -> ActivationPolicy.RefreshResult {
        switch resolution {
        case .objectUnavailable:
            let traitNames = ActionCapabilityDiagnostic.traitNames(resolved.element.traits)
            let message = ActivateFailureDiagnostic.build(
                element: resolved.element,
                traitNames: traitNames,
                activateOutcome: .objectDeallocated,
                tapAttempted: false,
                tapReceiver: nil,
                screenBounds: ScreenMetrics.current.bounds
            )
            return .failure(.failure(.activate, message: message))
        case .geometryUnavailable:
            return .failure(.failure(
                .activate,
                message: ActionCapabilityDiagnostic.gestureTargetUnavailable(
                    method: .activate,
                    element: resolved.screenElement,
                    isVisible: stash.visibleIds.contains(resolved.screenElement.heistId)
                )
            ))
        case .resolved:
            return .failure(.failure(.activate, message: "activate failed"))
        }
    }

    func executeIncrement(_ target: ElementTarget, recordedScreen: Screen? = nil) async -> TheSafecracker.InteractionResult {
        return await performElementAction(
            target: target,
            method: .increment,
            recordedScreen: recordedScreen,
            deallocatedBoundary: "adjustable action",
            preflight: { resolved in
                guard resolved.element.traits.contains(.adjustable) else {
                    return .failure(
                        .increment,
                        message: ActionCapabilityDiagnostic.nonAdjustableAction(
                            .increment,
                            element: resolved.screenElement
                        )
                    )
                }
                return nil
            },
            action: { context in
                let liveTarget = context.liveTarget
                _ = self.stash.increment(liveTarget)
                self.safecracker.showFingerprint(at: liveTarget.activationPoint)
                return .success(method: .increment)
            }
        )
    }

    func executeDecrement(_ target: ElementTarget, recordedScreen: Screen? = nil) async -> TheSafecracker.InteractionResult {
        return await performElementAction(
            target: target,
            method: .decrement,
            recordedScreen: recordedScreen,
            deallocatedBoundary: "adjustable action",
            preflight: { resolved in
                guard resolved.element.traits.contains(.adjustable) else {
                    return .failure(
                        .decrement,
                        message: ActionCapabilityDiagnostic.nonAdjustableAction(
                            .decrement,
                            element: resolved.screenElement
                        )
                    )
                }
                return nil
            },
            action: { context in
                let liveTarget = context.liveTarget
                _ = self.stash.decrement(liveTarget)
                self.safecracker.showFingerprint(at: liveTarget.activationPoint)
                return .success(method: .decrement)
            }
        )
    }

    func executeCustomAction(
        _ target: some CustomActionExecutionInput,
        recordedScreen: Screen? = nil
    ) async -> TheSafecracker.InteractionResult {
        if let containerTarget = target.actionContainerTarget {
            return executeContainerCustomAction(
                containerTarget,
                ordinal: target.actionContainerOrdinal,
                actionName: target.actionName
            )
        }
        guard let elementTarget = target.actionElementTarget else {
            return .failure(.customAction, message: "custom action failed: missing element or container target")
        }
        return await performElementAction(
            target: elementTarget,
            method: .customAction,
            recordedScreen: recordedScreen,
            deallocatedBoundary: "custom action"
        ) { context in
            let resolved = context.resolvedTarget
            let liveTarget = context.liveTarget
            switch self.stash.performCustomAction(named: target.actionName, on: liveTarget) {
            case .deallocated:
                return .failure(.customAction, message: "custom action failed")
            case .noSuchAction:
                return .failure(
                    .customAction,
                    message: ActionCapabilityDiagnostic.missingCustomAction(
                        target.actionName,
                        element: resolved.screenElement
                    )
                )
            case .declined:
                return .failure(
                    .customAction,
                    message: ActionCapabilityDiagnostic.declinedCustomAction(
                        target.actionName,
                        element: resolved.screenElement
                    )
                )
            case .succeeded:
                return .success(method: .customAction)
            }
        }
    }

    private func executeContainerCustomAction(
        _ matcher: ContainerMatcher,
        ordinal: Int?,
        actionName: String
    ) -> TheSafecracker.InteractionResult {
        let resolution = stash.resolveContainerTarget(matcher, ordinal: ordinal)
        guard case .resolved(let containerTarget) = resolution else {
            return .failure(
                .customAction,
                message: "custom action failed: \(resolution.diagnostics); try get_interface to inspect container stableIds."
            )
        }
        switch stash.performCustomAction(named: actionName, on: containerTarget) {
        case .deallocated:
            return .failure(.customAction, message: "custom action failed: container object deallocated")
        case .noSuchAction:
            let available = containerTarget.container.customActions.map(\.name).filter { !$0.isEmpty }
            let suffix = available.isEmpty ? "" : "; available custom actions: \(available.map { "\"\($0)\"" }.joined(separator: ", "))"
            return .failure(
                .customAction,
                message: "custom action failed: requestedAction=\"\(actionName)\" not found on container\(suffix)"
            )
        case .declined:
            return .failure(
                .customAction,
                message: "custom action failed: requestedAction=\"\(actionName)\" declined by container handler"
            )
        case .succeeded:
            safecracker.showFingerprint(at: CGPoint(
                x: containerTarget.container.frame.origin.x + containerTarget.container.frame.size.width / 2,
                y: containerTarget.container.frame.origin.y + containerTarget.container.frame.size.height / 2
            ))
            return .success(method: .customAction)
        }
    }

    func executeRotor(
        _ target: some RotorExecutionInput,
        recordedScreen: Screen? = nil
    ) async -> TheSafecracker.InteractionResult {
        let direction = target.direction ?? .next
        let method: ActionMethod = .rotor
        return await performElementAction(
            target: target.rotorElementTarget,
            method: method,
            recordedScreen: recordedScreen,
            requireInteractive: false
        ) { context in
            let outcome = self.stash.performRotor(
                rotor: target.rotor,
                rotorIndex: target.rotorIndex,
                currentHeistId: target.currentHeistId,
                currentTextRange: target.currentTextRange,
                direction: direction,
                on: context.liveTarget
            )
            return Self.rotorInteractionResult(
                outcome: outcome,
                rotor: target.rotor,
                rotorIndex: target.rotorIndex,
                direction: direction,
                liveTarget: context.liveTarget
            )
        }
    }

    // MARK: - Edit / Pasteboard / Responder

    func executeEditAction(_ target: EditActionTarget) async -> TheSafecracker.InteractionResult {
        await navigation.ensureFirstResponderOnScreen()
        let success = safecracker.performEditAction(target.action)
        let message = success ? nil : ActionCapabilityDiagnostic.editActionFailed(
            target.action,
            stash: stash,
            safecracker: safecracker
        )
        return success
            ? .success(method: .editAction)
            : .failure(.editAction, message: message ?? "edit action failed")
    }

    func executeSetPasteboard(_ target: SetPasteboardTarget) async -> TheSafecracker.InteractionResult {
        await navigation.ensureFirstResponderOnScreen()
        UIPasteboard.general.string = target.text
        return .success(method: .setPasteboard, payload: .value(target.text))
    }

    func executeGetPasteboard() -> TheSafecracker.InteractionResult {
        let text = UIPasteboard.general.string
        return .success(
            method: .getPasteboard,
            message: text == nil ? "Pasteboard is empty or contains non-text data" : nil,
            payload: text.map(ResultPayload.value)
        )
    }

    func executeResignFirstResponder() async -> TheSafecracker.InteractionResult {
        await navigation.ensureFirstResponderOnScreen()
        let success = safecracker.resignFirstResponder()
        if success { return .success(method: .resignFirstResponder) }
        return .failure(
            .resignFirstResponder,
            message: ActionCapabilityDiagnostic.resignFirstResponderFailed(
                stash: stash,
                safecracker: safecracker
            )
        )
    }

    // MARK: - Touch Gestures

    func executeTap(
        _ target: some TapExecutionInput,
        recordedScreen: Screen? = nil
    ) async -> TheSafecracker.InteractionResult {
        await performPointAction(
            elementTarget: target.tapElementTarget, pointX: target.pointX, pointY: target.pointY,
            method: .syntheticTap,
            recordedScreen: recordedScreen
        ) { point in
            await self.safecracker.tap(at: point)
        }
    }

    func executeLongPress(
        _ target: some LongPressExecutionInput,
        recordedScreen: Screen? = nil
    ) async -> TheSafecracker.InteractionResult {
        let duration = clampDuration(target.duration)
        return await performPointAction(
            elementTarget: target.tapElementTarget, pointX: target.pointX, pointY: target.pointY,
            method: .syntheticLongPress,
            recordedScreen: recordedScreen
        ) { point in
            await self.safecracker.longPress(at: point, duration: duration)
        }
    }

    func executeSwipe(
        _ target: some SwipeExecutionInput,
        recordedScreen: Screen? = nil
    ) async -> TheSafecracker.InteractionResult {
        // Unit-point swipe: resolve element frame, compute start/end from unit coordinates
        if let unitPoints = unitSwipePoints(
            elementTarget: target.swipeElementTarget,
            direction: target.direction,
            start: target.start,
            end: target.end
        ) {
            guard let elementTarget = target.swipeElementTarget else {
                return .failure(
                    .syntheticSwipe,
                    message: "synthetic swipe failed: observed unit start/end points without elementTarget; "
                        + "try providing elementTarget or use absolute startX/startY/endX/endY."
                )
            }
            let normalizedTarget = stash.normalizeTarget(elementTarget, in: recordedScreen ?? stash.currentScreen)
            let positioning = await navigation.ensureOnScreen(for: normalizedTarget)
            if let failure = positioning.failure {
                return .failure(failure.method ?? .syntheticSwipe, message: failure.message)
            }
            let frame: CGRect
            switch resolveGestureFrame(for: normalizedTarget, method: .syntheticSwipe) {
            case .success(let liveFrame):
                frame = liveFrame
            case .failure(let result):
                return result
            }
            let startPoint = CGPoint(
                x: frame.origin.x + unitPoints.start.x * frame.width,
                y: frame.origin.y + unitPoints.start.y * frame.height
            )
            let endPoint = CGPoint(
                x: frame.origin.x + unitPoints.end.x * frame.width,
                y: frame.origin.y + unitPoints.end.y * frame.height
            )
            if let failure = geometryFailure(method: .syntheticSwipe, field: "swipe point", points: [startPoint, endPoint]) {
                return failure
            }
            let duration = clampDuration(target.duration ?? 0.15)
            let success = await safecracker.swipe(from: startPoint, to: endPoint, duration: duration)
            let message = success ? nil : ActionCapabilityDiagnostic.gestureDispatchFailed(
                method: .syntheticSwipe,
                point: startPoint,
                receiver: safecracker.tapReceiverDiagnostic(at: startPoint)
            )
            return success
                ? .success(method: .syntheticSwipe)
                : .failure(.syntheticSwipe, message: message ?? "synthetic swipe failed")
        }

        // Absolute-point swipe: resolve start point, compute end from direction or explicit coords
        let normalizedTarget = target.swipeElementTarget.map {
            stash.normalizeTarget($0, in: recordedScreen ?? stash.currentScreen)
        }
        if let normalizedTarget {
            let positioning = await navigation.ensureOnScreen(for: normalizedTarget)
            if let failure = positioning.failure {
                return .failure(failure.method ?? .syntheticSwipe, message: failure.message)
            }
        }
        switch resolveGesturePoint(
            from: normalizedTarget,
            pointX: target.startX,
            pointY: target.startY,
            method: .syntheticSwipe
        ) {
        case .failure(let result):
            return result
        case .success(let startPoint):
            let endPoint: CGPoint
            if let endX = target.endX, let endY = target.endY {
                endPoint = CGPoint(x: endX, y: endY)
            } else if let direction = target.direction {
                let dist = Self.defaultSwipeDistance
                switch direction {
                case .up:    endPoint = CGPoint(x: startPoint.x, y: startPoint.y - dist)
                case .down:  endPoint = CGPoint(x: startPoint.x, y: startPoint.y + dist)
                case .left:  endPoint = CGPoint(x: startPoint.x - dist, y: startPoint.y)
                case .right: endPoint = CGPoint(x: startPoint.x + dist, y: startPoint.y)
                }
            } else {
                return .failure(
                    .syntheticSwipe,
                    message: "synthetic swipe failed: observed missing end point and direction; "
                        + "try providing endX/endY or direction."
                )
            }
            if let failure = geometryFailure(method: .syntheticSwipe, field: "swipe point", points: [startPoint, endPoint]) {
                return failure
            }
            let duration = clampDuration(target.duration ?? 0.15)
            let success = await safecracker.swipe(from: startPoint, to: endPoint, duration: duration)
            let message = success ? nil : ActionCapabilityDiagnostic.gestureDispatchFailed(
                method: .syntheticSwipe,
                point: startPoint,
                receiver: safecracker.tapReceiverDiagnostic(at: startPoint)
            )
            return success
                ? .success(method: .syntheticSwipe)
                : .failure(.syntheticSwipe, message: message ?? "synthetic swipe failed")
        }
    }

    private func unitSwipePoints(
        elementTarget: ElementTarget?,
        direction: SwipeDirection?,
        start: UnitPoint?,
        end: UnitPoint?
    ) -> (start: UnitPoint, end: UnitPoint)? {
        if let start, let end {
            return (start, end)
        }
        guard let direction, elementTarget != nil else {
            return nil
        }
        return (direction.defaultStart, direction.defaultEnd)
    }

    func executeDrag(
        _ target: some DragExecutionInput,
        recordedScreen: Screen? = nil
    ) async -> TheSafecracker.InteractionResult {
        let endPoint = CGPoint(x: target.endX, y: target.endY)
        if let failure = geometryFailure(method: .syntheticDrag, field: "endPoint", point: endPoint) {
            return failure
        }
        let duration = clampDuration(target.duration ?? 0.5)
        return await performPointAction(
            elementTarget: target.dragElementTarget, pointX: target.startX, pointY: target.startY,
            method: .syntheticDrag,
            recordedScreen: recordedScreen
        ) { startPoint in
            await self.safecracker.drag(from: startPoint, to: endPoint, duration: duration)
        }
    }

    func executePinch(
        _ target: some PinchExecutionInput,
        recordedScreen: Screen? = nil
    ) async -> TheSafecracker.InteractionResult {
        let spread = target.spread ?? 100.0
        let duration = clampDuration(target.duration ?? 0.5)
        return await performPointAction(
            elementTarget: target.pinchElementTarget, pointX: target.centerX, pointY: target.centerY,
            method: .syntheticPinch,
            recordedScreen: recordedScreen
        ) { center in
            await self.safecracker.pinch(
                center: center, scale: CGFloat(target.scale),
                spread: CGFloat(spread), duration: duration
            )
        }
    }

    func executeRotate(
        _ target: some RotateExecutionInput,
        recordedScreen: Screen? = nil
    ) async -> TheSafecracker.InteractionResult {
        let radius = target.radius ?? 100.0
        let duration = clampDuration(target.duration ?? 0.5)
        return await performPointAction(
            elementTarget: target.rotateElementTarget, pointX: target.centerX, pointY: target.centerY,
            method: .syntheticRotate,
            recordedScreen: recordedScreen
        ) { center in
            await self.safecracker.rotate(
                center: center, angle: CGFloat(target.angle),
                radius: CGFloat(radius), duration: duration
            )
        }
    }

    func executeTwoFingerTap(
        _ target: some TwoFingerTapExecutionInput,
        recordedScreen: Screen? = nil
    ) async -> TheSafecracker.InteractionResult {
        let spread = target.spread ?? 40.0
        return await performPointAction(
            elementTarget: target.twoFingerTapElementTarget, pointX: target.centerX, pointY: target.centerY,
            method: .syntheticTwoFingerTap,
            recordedScreen: recordedScreen
        ) { center in
            await self.safecracker.twoFingerTap(at: center, spread: CGFloat(spread))
        }
    }

    func executeDrawPath(_ target: DrawPathTarget) async -> TheSafecracker.InteractionResult {
        guard target.points.count <= 10_000 else {
            return .failure(.syntheticDrawPath, message: "Too many points (max 10,000)")
        }
        let cgPoints = target.points.map { $0.cgPoint }
        guard cgPoints.count >= 2 else {
            return .failure(.syntheticDrawPath, message: "Path requires at least 2 points")
        }
        if let failure = geometryFailure(method: .syntheticDrawPath, field: "path point", points: cgPoints) {
            return failure
        }
        let duration = resolveDuration(target.duration, velocity: target.velocity, points: cgPoints)
        let success = await safecracker.drawPath(points: cgPoints, duration: duration)
        let message = success ? nil : ActionCapabilityDiagnostic.gestureDispatchFailed(
            method: .syntheticDrawPath,
            point: cgPoints[0],
            receiver: safecracker.tapReceiverDiagnostic(at: cgPoints[0])
        )
        return success
            ? .success(method: .syntheticDrawPath)
            : .failure(.syntheticDrawPath, message: message ?? "synthetic draw path failed")
    }

    func executeDrawBezier(_ target: DrawBezierTarget) async -> TheSafecracker.InteractionResult {
        guard target.segments.count <= 1_000 else {
            return .failure(.syntheticDrawPath, message: "Too many segments (max 1,000)")
        }
        guard !target.segments.isEmpty else {
            return .failure(.syntheticDrawPath, message: "Bezier path requires at least 1 segment")
        }
        let samplesPerSegment = min(target.samplesPerSegment ?? 20, 1000)
        let pathPoints = TheSafecracker.BezierSampler.sampleBezierPath(
            startPoint: target.startPoint,
            segments: target.segments,
            samplesPerSegment: samplesPerSegment
        )
        let cgPoints = pathPoints.map { $0.cgPoint }
        guard cgPoints.count >= 2 else {
            return .failure(.syntheticDrawPath, message: "Sampled bezier produced fewer than 2 points")
        }
        if let failure = geometryFailure(method: .syntheticDrawPath, field: "bezier point", points: cgPoints) {
            return failure
        }
        let duration = resolveDuration(target.duration, velocity: target.velocity, points: cgPoints)
        let success = await safecracker.drawPath(points: cgPoints, duration: duration)
        let message = success ? nil : ActionCapabilityDiagnostic.gestureDispatchFailed(
            method: .syntheticDrawPath,
            point: cgPoints[0],
            receiver: safecracker.tapReceiverDiagnostic(at: cgPoints[0])
        )
        return success
            ? .success(method: .syntheticDrawPath)
            : .failure(.syntheticDrawPath, message: message ?? "synthetic draw path failed")
    }

    // MARK: - Text Entry

    func executeTypeText(
        _ target: some TypeTextExecutionInput,
        recordedScreen: Screen? = nil
    ) async -> TheSafecracker.InteractionResult {
        guard !target.text.isEmpty else {
            return .failure(.typeText, message: "type_text requires non-empty text")
        }
        let normalizedTarget = target.typeTextElementTarget.map {
            stash.normalizeTarget($0, in: recordedScreen ?? stash.currentScreen)
        }
        if let failure = await focusTextInput(normalizedTarget) { return failure }

        let interKeyDelay = min(TheSafecracker.defaultInterKeyDelay, TheSafecracker.maxInterKeyDelay)
        let typingResult = await safecracker.typeText(target.text, interKeyDelay: interKeyDelay)
        if let diagnostic = typingResult.diagnostic {
            return .failure(.typeText, message: typeTextInjectionFailureMessage(for: diagnostic))
        }

        guard await Task.cancellableSleep(for: TheSafecracker.keyboardPollInterval) else { return .failure(.typeText, message: "Cancelled") }
        stash.refresh()

        var fieldValue: String?
        if let normalizedTarget {
            if let resolved = stash.resolveTarget(normalizedTarget.executableTarget).resolved {
                fieldValue = resolved.element.value
            }
        }

        return .success(method: .typeText, payload: fieldValue.map(ResultPayload.value))
    }

    private func typeTextInjectionFailureMessage(for diagnostic: KeyboardTextInjectionDiagnostic) -> String {
        guard diagnostic.reason == .noActiveInput else { return diagnostic.message }
        return "\(diagnostic.message); " + ActionCapabilityDiagnostic.textEntryFailed(
            operation: "typing",
            stash: stash,
            safecracker: safecracker,
            suggestion: "focus an editable text field before typing"
        )
    }

    private func focusTextInput(
        _ normalizedTarget: TheStash.NormalizedTarget?
    ) async -> TheSafecracker.InteractionResult? {
        guard let normalizedTarget else {
            guard safecracker.hasActiveTextInput() else {
                return .failure(
                    .typeText,
                    message: ActionCapabilityDiagnostic.textEntryFailed(
                        operation: "initial focus check",
                        stash: stash,
                        safecracker: safecracker,
                        suggestion: "provide elementTarget for a text field or focus an editable field before typing"
                    )
                )
            }
            return nil
        }

        let positioning = await navigation.ensureOnScreen(for: normalizedTarget)
        if let failure = positioning.failure {
            return .failure(failure.method ?? .typeText, message: failure.message)
        }
        let resolution = stash.resolveTarget(normalizedTarget.executableTarget)
        guard let resolved = resolution.resolved else {
            return .failure(.elementNotFound, message: normalizedTarget.diagnostics(resolution.diagnostics))
        }

        guard case .resolved(let liveTarget) = stash.resolveLiveActionTarget(for: resolved) else {
            return .failure(
                .typeText,
                message: normalizedTarget.diagnostics(
                    ActionCapabilityDiagnostic.gestureTargetUnavailable(
                        method: .syntheticTap,
                        element: resolved.screenElement,
                        isVisible: stash.visibleIds.contains(resolved.screenElement.heistId)
                    )
                )
            )
        }
        let point = liveTarget.activationPoint
        guard await safecracker.tap(at: point) else {
            return .failure(
                .typeText,
                message: ActionCapabilityDiagnostic.gestureDispatchFailed(
                    method: .syntheticTap,
                    point: point,
                    receiver: safecracker.tapReceiverDiagnostic(at: point)
                )
            )
        }
        safecracker.showFingerprint(at: point)

        guard await waitForActiveTextInput() else {
            return .failure(
                .typeText,
                message: ActionCapabilityDiagnostic.textEntryFailed(
                    operation: "post-tap keyboard readiness",
                    stash: stash,
                    safecracker: safecracker,
                    suggestion: "target an editable text field"
                )
            )
        }
        return nil
    }

    private func waitForActiveTextInput() async -> Bool {
        for _ in 0..<TheSafecracker.keyboardPollMaxAttempts {
            guard await Task.cancellableSleep(for: TheSafecracker.keyboardPollInterval) else { return false }
            if safecracker.hasActiveTextInput() { return true }
        }
        return false
    }

    // MARK: - Diagnostic Helpers

    private static func rotorInteractionResult(
        outcome: TheStash.RotorOutcome,
        rotor: String?,
        rotorIndex: Int?,
        direction: RotorDirection,
        liveTarget: TheStash.LiveActionTarget
    ) -> TheSafecracker.InteractionResult {
        let element = liveTarget.screenElement
        let liveObject = liveTarget.object
        switch outcome {
        case .succeeded(let hit):
            return rotorSuccessResult(hit, direction: direction)
        case .deallocated:
            return rotorFailure(
                .elementDeallocated,
                observed: "liveObject=deallocated before rotor step",
                rotor: rotor,
                rotorIndex: rotorIndex,
                direction: direction,
                element: element,
                liveObject: liveObject,
                suggestion: "refresh with get_interface and retarget the refreshed element"
            )
        case .noRotors:
            return rotorFailure(.rotor, observed: "customRotors=[]",
                                rotor: rotor, rotorIndex: rotorIndex, direction: direction,
                                element: element, liveObject: liveObject,
                                suggestion: "target an element exposing custom rotors")
        case .noSuchRotor(let available):
            return rotorFailure(.rotor, observed: "requestedRotor=\(ActionCapabilityDiagnostic.quote(rotor ?? "")) "
                                + "availableRotors=\(ActionCapabilityDiagnostic.formatQuotedList(available))",
                                rotor: rotor, rotorIndex: rotorIndex, direction: direction,
                                element: element, liveObject: liveObject,
                                suggestion: "use one of available rotors \(ActionCapabilityDiagnostic.formatQuotedList(available))")
        case .ambiguousRotor(let available):
            return rotorFailure(.rotor, observed: "ambiguousRotor=\(ActionCapabilityDiagnostic.quote(rotor ?? "")) "
                                + "availableRotors=\(ActionCapabilityDiagnostic.formatQuotedList(available))",
                                rotor: rotor, rotorIndex: rotorIndex, direction: direction,
                                element: element, liveObject: liveObject,
                                suggestion: "specify rotorIndex or an exact rotor name")
        case .currentItemUnavailable(let heistId):
            return rotorFailure(
                .elementNotFound,
                observed: "currentHeistId=\(ActionCapabilityDiagnostic.quote(heistId)) is not available",
                rotor: rotor,
                rotorIndex: rotorIndex,
                direction: direction,
                element: element,
                liveObject: liveObject,
                suggestion: "use the heistId returned by the previous rotor result after refetching"
            )
        case .currentTextRangeUnavailable:
            return rotorFailure(.rotor, observed: "currentTextRange is not available",
                                rotor: rotor, rotorIndex: rotorIndex, direction: direction,
                                element: element, liveObject: liveObject,
                                suggestion: "use the text range returned by the previous rotor result after refetching")
        case .noResult(let rotorName):
            return rotorFailure(
                .rotor,
                observed: "rotor=\(ActionCapabilityDiagnostic.quote(rotorName)) returned no \(direction.rawValue) result",
                rotor: rotor,
                rotorIndex: rotorIndex,
                direction: direction,
                element: element,
                liveObject: liveObject,
                suggestion: "try the opposite rotor direction or stop at the current item"
            )
        case .resultTargetUnavailable(let rotorName):
            return rotorFailure(
                .rotor,
                observed: "rotor=\(ActionCapabilityDiagnostic.quote(rotorName)) returned a result without an accessibility target",
                rotor: rotor,
                rotorIndex: rotorIndex,
                direction: direction,
                element: element,
                liveObject: liveObject,
                suggestion: "refetch with get_interface and retry the rotor from a visible target"
            )
        case .resultTargetNotParsed(let rotorName):
            return rotorFailure(
                .rotor,
                observed: "rotor=\(ActionCapabilityDiagnostic.quote(rotorName)) returned a target outside the parsed hierarchy",
                rotor: rotor,
                rotorIndex: rotorIndex,
                direction: direction,
                element: element,
                liveObject: liveObject,
                suggestion: "refetch with get_interface before acting on the rotor result"
            )
        }
    }

    private static func rotorSuccessResult(
        _ hit: TheStash.RotorHit,
        direction: RotorDirection
    ) -> TheSafecracker.InteractionResult {
        let found = hit.screenElement.map(TheStash.WireConversion.toWire)
        var message = "Rotor '\(hit.rotor)' found"
        if let found {
            message += " \(found.heistId)"
        }
        if let textRange = hit.textRange {
            message += " text range \(textRange.rangeDescription)"
        }
        return .success(
            method: .rotor,
            message: message,
            payload: .rotor(RotorResult(
                rotor: hit.rotor,
                direction: direction,
                foundElement: found,
                textRange: hit.textRange
            ))
        )
    }

    private static func rotorFailure(
        _ method: ActionMethod,
        observed: String,
        rotor: String?,
        rotorIndex: Int?,
        direction: RotorDirection,
        element: TheStash.ScreenElement,
        liveObject: NSObject,
        suggestion: String
    ) -> TheSafecracker.InteractionResult {
        .failure(
            method,
            message: rotorDiagnostic(
                observed: observed,
                rotor: rotor,
                rotorIndex: rotorIndex,
                direction: direction,
                element: element,
                liveObject: liveObject,
                suggestion: suggestion
            )
        )
    }

    private static func rotorDiagnostic(
        observed: String,
        rotor: String?,
        rotorIndex: Int?,
        direction: RotorDirection,
        element: TheStash.ScreenElement,
        liveObject: NSObject,
        suggestion: String
    ) -> String {
        var attempted: [String] = []
        if let rotor {
            attempted.append("rotor=\(ActionCapabilityDiagnostic.quote(rotor))")
        } else {
            attempted.append("rotor")
        }
        if let rotorIndex {
            attempted.append("rotorIndex=\(rotorIndex)")
        }
        attempted.append("direction=\(direction.rawValue)")

        let availableRotors = ActionCapabilityDiagnostic.availableRotors(for: element, liveObject: liveObject)
        return "rotor failed: attempted \(attempted.joined(separator: " ")) "
            + "on \(ActionCapabilityDiagnostic.formatElement(element, liveObject: liveObject)) "
            + "availableRotors=\(ActionCapabilityDiagnostic.formatQuotedList(availableRotors)); "
            + "observed \(observed); try \(suggestion)."
    }

    // MARK: - Duration Helpers

    private static let defaultGestureDuration: Double = 0.5
    private static let minGestureDuration: Double = 0.01
    private static let maxGestureDuration: Double = 60.0

    /// Default swipe travel distance in points when the caller specifies a
    /// direction without explicit end coordinates.
    ///
    /// 200pt is a deliberate, screen-relative-ish choice: ~25% of the short
    /// dimension on iPhone and ~25% of the long dimension on the smallest
    /// iPad, which is large enough to cross a typical paginated cell or
    /// trigger a UIKit scroll-view paging snap, but small enough to stay on
    /// screen from any activation point. Treating it as a named constant
    /// keeps direction-only swipes behaviourally stable across releases.
    static let defaultSwipeDistance: CGFloat = 200

    func clampDuration(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return Self.defaultGestureDuration }
        return min(max(value, Self.minGestureDuration), Self.maxGestureDuration)
    }

    func resolveDuration(_ duration: Double?, velocity: Double?, points: [CGPoint]) -> TimeInterval {
        let result: Double
        if let resolvedDuration = duration, resolvedDuration.isFinite, resolvedDuration > 0 {
            result = resolvedDuration
        } else if let velocity = velocity, velocity.isFinite, velocity > 0 {
            let totalLength = zip(points, points.dropFirst()).reduce(0.0) { runningTotal, pair in
                runningTotal + hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y)
            }
            result = totalLength / velocity
        } else {
            result = Self.defaultGestureDuration
        }
        return clampDuration(result)
    }
}

extension CustomActionTarget: CustomActionExecutionInput {
    var actionElementTarget: ElementTarget? { elementTarget }
    var actionContainerTarget: ContainerMatcher? { containerTarget }
    var actionContainerOrdinal: Int? { containerOrdinal }
}

extension BatchCustomActionTarget: CustomActionExecutionInput {
    var actionElementTarget: ElementTarget? { target?.executableTarget }
    var actionContainerTarget: ContainerMatcher? { containerTarget }
    var actionContainerOrdinal: Int? { containerOrdinal }
}

extension RotorTarget: RotorExecutionInput {
    var rotorElementTarget: ElementTarget { elementTarget }
}

extension BatchRotorTarget: RotorExecutionInput {
    var rotorElementTarget: ElementTarget { target.executableTarget }
    var currentHeistId: HeistId? { currentSourceHeistId }
}

extension TouchTapTarget: TapExecutionInput {
    var tapElementTarget: ElementTarget? { elementTarget }
}

extension BatchTouchTapTarget: TapExecutionInput {
    var tapElementTarget: ElementTarget? { target?.executableTarget }
}

extension LongPressTarget: LongPressExecutionInput {
    var tapElementTarget: ElementTarget? { elementTarget }
}

extension BatchLongPressTarget: LongPressExecutionInput {
    var tapElementTarget: ElementTarget? { target?.executableTarget }
}

extension SwipeTarget: SwipeExecutionInput {
    var swipeElementTarget: ElementTarget? { elementTarget }
}

extension BatchSwipeTarget: SwipeExecutionInput {
    var swipeElementTarget: ElementTarget? { target?.executableTarget }
}

extension DragTarget: DragExecutionInput {
    var dragElementTarget: ElementTarget? { elementTarget }
}

extension BatchDragTarget: DragExecutionInput {
    var dragElementTarget: ElementTarget? { target?.executableTarget }
}

extension PinchTarget: PinchExecutionInput {
    var pinchElementTarget: ElementTarget? { elementTarget }
}

extension BatchPinchTarget: PinchExecutionInput {
    var pinchElementTarget: ElementTarget? { target?.executableTarget }
}

extension RotateTarget: RotateExecutionInput {
    var rotateElementTarget: ElementTarget? { elementTarget }
}

extension BatchRotateTarget: RotateExecutionInput {
    var rotateElementTarget: ElementTarget? { target?.executableTarget }
}

extension TwoFingerTapTarget: TwoFingerTapExecutionInput {
    var twoFingerTapElementTarget: ElementTarget? { elementTarget }
}

extension BatchTwoFingerTapTarget: TwoFingerTapExecutionInput {
    var twoFingerTapElementTarget: ElementTarget? { target?.executableTarget }
}

extension TypeTextTarget: TypeTextExecutionInput {
    var typeTextElementTarget: ElementTarget? { elementTarget }
}

extension BatchTypeTextTarget: TypeTextExecutionInput {
    var typeTextElementTarget: ElementTarget? { target?.executableTarget }
}

#endif // DEBUG
#endif // canImport(UIKit)
