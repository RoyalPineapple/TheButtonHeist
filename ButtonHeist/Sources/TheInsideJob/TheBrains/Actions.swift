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

    /// Unified pipeline for actions that target an element:
    /// ensureOnScreen → resolve → check interactivity → perform action.
    func performElementAction(
        target: ElementTarget,
        method: ActionMethod,
        requireInteractive: Bool = true,
        action: @MainActor (TheStash.ResolvedTarget) async -> TheSafecracker.InteractionResult?
    ) async -> TheSafecracker.InteractionResult {
        await navigation.ensureOnScreen(for: target)
        let resolution = stash.resolveTarget(target)
        guard let resolved = resolution.resolved else {
            return .failure(.elementNotFound, message: resolution.diagnostics)
        }
        if requireInteractive {
            switch stash.checkElementInteractivity(resolved.screenElement) {
            case .blocked(let reason):
                return .failure(method, message: reason)
            case .interactive(let warning):
                if let warning { insideJobLogger.warning("\(warning)") }
            }
            guard stash.hasInteractiveObject(resolved.screenElement) else {
                return .failure(
                    method,
                    message: ActionCapabilityDiagnostic.unsupportedElementAction(method, element: resolved.screenElement)
                )
            }
        }
        return await action(resolved) ?? .failure(method, message: "\(method.rawValue) failed")
    }

    /// Unified pipeline for gestures that target a screen point:
    /// ensureOnScreen (if element target) → resolve point → perform gesture.
    func performPointAction(
        elementTarget: ElementTarget?,
        pointX: Double?,
        pointY: Double?,
        method: ActionMethod,
        action: (CGPoint) async -> Bool
    ) async -> TheSafecracker.InteractionResult {
        if let elementTarget {
            await navigation.ensureOnScreen(for: elementTarget)
        }
        switch resolveGesturePoint(from: elementTarget, pointX: pointX, pointY: pointY, method: method) {
        case .failure(let result):
            return result
        case .success(let point):
            let success = await action(point)
            if success { safecracker.showFingerprint(at: point) }
            let message = success ? nil : ActionCapabilityDiagnostic.gestureDispatchFailed(
                method: method,
                point: point,
                receiver: safecracker.tapReceiverDiagnostic(at: point)
            )
            return TheSafecracker.InteractionResult(success: success, method: method, message: message, value: nil)
        }
    }

    private func resolveGesturePoint(
        from elementTarget: ElementTarget?,
        pointX: Double?,
        pointY: Double?,
        method: ActionMethod
    ) -> PointResolution {
        guard let elementTarget else {
            guard let xCoord = pointX, let yCoord = pointY else {
                return .failure(.failure(.elementNotFound, message: "No target specified"))
            }
            return .success(CGPoint(x: xCoord, y: yCoord))
        }
        let resolution = stash.resolveTarget(elementTarget)
        guard let resolved = resolution.resolved else {
            return .failure(.failure(.elementNotFound, message: resolution.diagnostics))
        }
        guard let point = stash.liveActivationPoint(for: resolved.screenElement) else {
            return .failure(.failure(
                method,
                message: ActionCapabilityDiagnostic.gestureTargetUnavailable(
                    method: method,
                    element: resolved.screenElement,
                    isVisible: stash.visibleIds.contains(resolved.screenElement.heistId)
                )
            ))
        }
        return .success(point)
    }

    private enum GestureFrameResolution {
        case success(CGRect)
        case failure(TheSafecracker.InteractionResult)
    }

    private func resolveGestureFrame(
        for elementTarget: ElementTarget,
        method: ActionMethod
    ) -> GestureFrameResolution {
        let resolution = stash.resolveTarget(elementTarget)
        guard let resolved = resolution.resolved else {
            return .failure(.failure(.elementNotFound, message: resolution.diagnostics))
        }
        guard let frame = stash.liveFrame(for: resolved.screenElement) else {
            return .failure(.failure(
                method,
                message: ActionCapabilityDiagnostic.gestureTargetUnavailable(
                    method: method,
                    element: resolved.screenElement,
                    isVisible: stash.visibleIds.contains(resolved.screenElement.heistId)
                )
            ))
        }
        return .success(frame)
    }

    // MARK: - Accessibility Actions

    func executeActivate(_ target: ElementTarget) async -> TheSafecracker.InteractionResult {
        await performElementAction(target: target, method: .activate) { resolved in
            // First attempt — accessibilityActivate on the live UIKit object.
            let firstOutcome = self.stash.activate(resolved.screenElement)
            if firstOutcome == .success {
                self.safecracker.showFingerprint(at: resolved.element.activationPoint.cgPoint)
                return TheSafecracker.InteractionResult(success: true, method: .activate, message: nil, value: nil)
            }

            // Retry once after a refresh + ensureOnScreen cycle. Cell reuse during
            // a scroll can deallocate the weak object ref between resolution and
            // dispatch; re-resolving against a freshly-parsed tree gives us a new
            // live object at the (possibly updated) activation point.
            self.navigation.refresh()
            await self.navigation.ensureOnScreen(for: target)
            let retryResolution = self.stash.resolveTarget(target)
            let retryResolved = retryResolution.resolved ?? resolved
            let retryOutcome = self.stash.activate(retryResolved.screenElement)
            if retryOutcome == .success {
                self.safecracker.showFingerprint(at: retryResolved.element.activationPoint.cgPoint)
                return TheSafecracker.InteractionResult(success: true, method: .activate, message: nil, value: nil)
            }

            // Synthetic tap fallback at the post-retry activation point.
            guard let tapPoint = self.stash.liveActivationPoint(for: retryResolved.screenElement) else {
                return .failure(
                    .activate,
                    message: ActionCapabilityDiagnostic.gestureTargetUnavailable(
                        method: .syntheticTap,
                        element: retryResolved.screenElement,
                        isVisible: self.stash.visibleIds.contains(retryResolved.screenElement.heistId)
                    )
                )
            }
            if await self.safecracker.tap(at: tapPoint) {
                self.safecracker.showFingerprint(at: tapPoint)
                return TheSafecracker.InteractionResult(success: true, method: .syntheticTap, message: nil, value: nil)
            }

            // All paths exhausted — build a fact-only diagnostic from what we
            // observed. The tap receiver is captured by re-running the same
            // hit-test the (failed) tap would have used; the result is
            // observation-only and does not claim element-level obstruction.
            let receiver = self.safecracker.tapReceiverDiagnostic(at: tapPoint)
            let traitNames = TheStash.WireConversion.traitNames(retryResolved.element.traits).map(\.rawValue)
            let message = ActivateFailureDiagnostic.build(
                element: retryResolved.element,
                traitNames: traitNames,
                activateOutcome: retryOutcome,
                tapAttempted: true,
                tapReceiver: receiver,
                screenBounds: ScreenMetrics.current.bounds
            )
            return .failure(.activate, message: message)
        }
    }

    func executeIncrement(_ target: ElementTarget) async -> TheSafecracker.InteractionResult {
        await performElementAction(target: target, method: .increment) { resolved in
            guard resolved.element.traits.contains(.adjustable) else {
                return .failure(
                    .increment,
                    message: ActionCapabilityDiagnostic.nonAdjustableAction(
                        .increment,
                        element: resolved.screenElement
                    )
                )
            }
            guard self.stash.increment(resolved.screenElement) else {
                return .failure(
                    .elementDeallocated,
                    message: ActionCapabilityDiagnostic.elementDeallocated(
                        boundary: "adjustable action",
                        element: resolved.screenElement
                    )
                )
            }
            self.safecracker.showFingerprint(at: resolved.element.activationPoint.cgPoint)
            return TheSafecracker.InteractionResult(success: true, method: .increment, message: nil, value: nil)
        }
    }

    func executeDecrement(_ target: ElementTarget) async -> TheSafecracker.InteractionResult {
        await performElementAction(target: target, method: .decrement) { resolved in
            guard resolved.element.traits.contains(.adjustable) else {
                return .failure(
                    .decrement,
                    message: ActionCapabilityDiagnostic.nonAdjustableAction(
                        .decrement,
                        element: resolved.screenElement
                    )
                )
            }
            guard self.stash.decrement(resolved.screenElement) else {
                return .failure(
                    .elementDeallocated,
                    message: ActionCapabilityDiagnostic.elementDeallocated(
                        boundary: "adjustable action",
                        element: resolved.screenElement
                    )
                )
            }
            self.safecracker.showFingerprint(at: resolved.element.activationPoint.cgPoint)
            return TheSafecracker.InteractionResult(success: true, method: .decrement, message: nil, value: nil)
        }
    }

    func executeCustomAction(_ target: CustomActionTarget) async -> TheSafecracker.InteractionResult {
        await performElementAction(target: target.elementTarget, method: .customAction) { resolved in
            switch self.stash.performCustomAction(named: target.actionName, on: resolved.screenElement) {
            case .deallocated:
                return .failure(
                    .elementDeallocated,
                    message: ActionCapabilityDiagnostic.elementDeallocated(
                        boundary: "custom action",
                        element: resolved.screenElement
                    )
                )
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
                return TheSafecracker.InteractionResult(
                    success: true, method: .customAction, message: nil, value: nil
                )
            }
        }
    }

    func executeRotor(_ target: RotorTarget) async -> TheSafecracker.InteractionResult {
        let direction = target.resolvedDirection
        let method: ActionMethod = .rotor
        return await performElementAction(
            target: target.elementTarget,
            method: method,
            requireInteractive: false
        ) { resolved in
            let outcome = self.stash.performRotor(target, direction: direction, on: resolved.screenElement)
            return Self.rotorInteractionResult(
                outcome: outcome,
                target: target,
                direction: direction,
                element: resolved.screenElement
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
        return TheSafecracker.InteractionResult(success: success, method: .editAction, message: message, value: nil)
    }

    func executeSetPasteboard(_ target: SetPasteboardTarget) async -> TheSafecracker.InteractionResult {
        await navigation.ensureFirstResponderOnScreen()
        UIPasteboard.general.string = target.text
        return TheSafecracker.InteractionResult(
            success: true, method: .setPasteboard, message: nil, value: target.text
        )
    }

    func executeGetPasteboard() -> TheSafecracker.InteractionResult {
        let text = UIPasteboard.general.string
        return TheSafecracker.InteractionResult(
            success: true, method: .getPasteboard,
            message: text == nil ? "Pasteboard is empty or contains non-text data" : nil,
            value: text
        )
    }

    func executeResignFirstResponder() async -> TheSafecracker.InteractionResult {
        await navigation.ensureFirstResponderOnScreen()
        let success = safecracker.resignFirstResponder()
        return TheSafecracker.InteractionResult(
            success: success, method: .resignFirstResponder,
            message: success ? nil : ActionCapabilityDiagnostic.resignFirstResponderFailed(
                stash: stash,
                safecracker: safecracker
            ),
            value: nil
        )
    }

    // MARK: - Touch Gestures

    func executeTap(_ target: TouchTapTarget) async -> TheSafecracker.InteractionResult {
        await performPointAction(
            elementTarget: target.elementTarget, pointX: target.pointX, pointY: target.pointY,
            method: .syntheticTap
        ) { point in
            await self.safecracker.tap(at: point)
        }
    }

    func executeLongPress(_ target: LongPressTarget) async -> TheSafecracker.InteractionResult {
        let duration = clampDuration(target.duration)
        return await performPointAction(
            elementTarget: target.elementTarget, pointX: target.pointX, pointY: target.pointY,
            method: .syntheticLongPress
        ) { point in
            await self.safecracker.longPress(at: point, duration: duration)
        }
    }

    func executeSwipe(_ target: SwipeTarget) async -> TheSafecracker.InteractionResult {
        // Unit-point swipe: resolve element frame, compute start/end from unit coordinates
        let unitStart: UnitPoint?
        let unitEnd: UnitPoint?
        if let start = target.start, let end = target.end {
            unitStart = start
            unitEnd = end
        } else if let direction = target.direction, target.elementTarget != nil {
            unitStart = direction.defaultStart
            unitEnd = direction.defaultEnd
        } else {
            unitStart = nil
            unitEnd = nil
        }

        if let unitStart, let unitEnd {
            guard let elementTarget = target.elementTarget else {
                return .failure(
                    .syntheticSwipe,
                    message: "synthetic swipe failed: observed unit start/end points without elementTarget; "
                        + "try providing elementTarget or use absolute startX/startY/endX/endY."
                )
            }
            await navigation.ensureOnScreen(for: elementTarget)
            let frame: CGRect
            switch resolveGestureFrame(for: elementTarget, method: .syntheticSwipe) {
            case .success(let liveFrame):
                frame = liveFrame
            case .failure(let result):
                return result
            }
            let startPoint = CGPoint(
                x: frame.origin.x + unitStart.x * frame.width,
                y: frame.origin.y + unitStart.y * frame.height
            )
            let endPoint = CGPoint(
                x: frame.origin.x + unitEnd.x * frame.width,
                y: frame.origin.y + unitEnd.y * frame.height
            )
            let duration = clampDuration(target.duration ?? 0.15)
            let success = await safecracker.swipe(from: startPoint, to: endPoint, duration: duration)
            let message = success ? nil : ActionCapabilityDiagnostic.gestureDispatchFailed(
                method: .syntheticSwipe,
                point: startPoint,
                receiver: safecracker.tapReceiverDiagnostic(at: startPoint)
            )
            return TheSafecracker.InteractionResult(
                success: success,
                method: .syntheticSwipe,
                message: message,
                value: nil
            )
        }

        // Absolute-point swipe: resolve start point, compute end from direction or explicit coords
        if let elementTarget = target.elementTarget {
            await navigation.ensureOnScreen(for: elementTarget)
        }
        switch resolveGesturePoint(
            from: target.elementTarget,
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
            let duration = clampDuration(target.duration ?? 0.15)
            let success = await safecracker.swipe(from: startPoint, to: endPoint, duration: duration)
            let message = success ? nil : ActionCapabilityDiagnostic.gestureDispatchFailed(
                method: .syntheticSwipe,
                point: startPoint,
                receiver: safecracker.tapReceiverDiagnostic(at: startPoint)
            )
            return TheSafecracker.InteractionResult(
                success: success,
                method: .syntheticSwipe,
                message: message,
                value: nil
            )
        }
    }

    func executeDrag(_ target: DragTarget) async -> TheSafecracker.InteractionResult {
        let duration = clampDuration(target.duration ?? 0.5)
        return await performPointAction(
            elementTarget: target.elementTarget, pointX: target.startX, pointY: target.startY,
            method: .syntheticDrag
        ) { startPoint in
            await self.safecracker.drag(from: startPoint, to: target.endPoint, duration: duration)
        }
    }

    func executePinch(_ target: PinchTarget) async -> TheSafecracker.InteractionResult {
        let spread = target.spread ?? 100.0
        let duration = clampDuration(target.duration ?? 0.5)
        return await performPointAction(
            elementTarget: target.elementTarget, pointX: target.centerX, pointY: target.centerY,
            method: .syntheticPinch
        ) { center in
            await self.safecracker.pinch(
                center: center, scale: CGFloat(target.scale),
                spread: CGFloat(spread), duration: duration
            )
        }
    }

    func executeRotate(_ target: RotateTarget) async -> TheSafecracker.InteractionResult {
        let radius = target.radius ?? 100.0
        let duration = clampDuration(target.duration ?? 0.5)
        return await performPointAction(
            elementTarget: target.elementTarget, pointX: target.centerX, pointY: target.centerY,
            method: .syntheticRotate
        ) { center in
            await self.safecracker.rotate(
                center: center, angle: CGFloat(target.angle),
                radius: CGFloat(radius), duration: duration
            )
        }
    }

    func executeTwoFingerTap(_ target: TwoFingerTapTarget) async -> TheSafecracker.InteractionResult {
        let spread = target.spread ?? 40.0
        return await performPointAction(
            elementTarget: target.elementTarget, pointX: target.centerX, pointY: target.centerY,
            method: .syntheticTwoFingerTap
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
        let duration = resolveDuration(target.duration, velocity: target.velocity, points: cgPoints)
        let success = await safecracker.drawPath(points: cgPoints, duration: duration)
        let message = success ? nil : ActionCapabilityDiagnostic.gestureDispatchFailed(
            method: .syntheticDrawPath,
            point: cgPoints[0],
            receiver: safecracker.tapReceiverDiagnostic(at: cgPoints[0])
        )
        return TheSafecracker.InteractionResult(
            success: success,
            method: .syntheticDrawPath,
            message: message,
            value: nil
        )
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
        let duration = resolveDuration(target.duration, velocity: target.velocity, points: cgPoints)
        let success = await safecracker.drawPath(points: cgPoints, duration: duration)
        let message = success ? nil : ActionCapabilityDiagnostic.gestureDispatchFailed(
            method: .syntheticDrawPath,
            point: cgPoints[0],
            receiver: safecracker.tapReceiverDiagnostic(at: cgPoints[0])
        )
        return TheSafecracker.InteractionResult(
            success: success,
            method: .syntheticDrawPath,
            message: message,
            value: nil
        )
    }

    // MARK: - Text Entry

    func executeTypeText(_ target: TypeTextTarget) async -> TheSafecracker.InteractionResult {
        if let failure = await focusTextInput(target.elementTarget) { return failure }

        let interKeyDelay = min(TheSafecracker.defaultInterKeyDelay, TheSafecracker.maxInterKeyDelay)
        if target.clearFirst == true {
            guard await safecracker.clearText() else {
                return .failure(
                    .typeText,
                    message: ActionCapabilityDiagnostic.textEntryFailed(
                        operation: "clearFirst",
                        stash: stash,
                        safecracker: safecracker,
                        suggestion: "focus an editable text field before clearing text"
                    )
                )
            }
        }

        if let deleteCount = target.deleteCount, deleteCount > 0 {
            guard await safecracker.deleteText(count: deleteCount, interKeyDelay: interKeyDelay) else {
                return .failure(
                    .typeText,
                    message: ActionCapabilityDiagnostic.textEntryFailed(
                        operation: "delete",
                        stash: stash,
                        safecracker: safecracker,
                        suggestion: "focus an editable text field before deleting text"
                    )
                )
            }
        }

        if let text = target.text, !text.isEmpty {
            guard await safecracker.typeText(text, interKeyDelay: interKeyDelay) else {
                return .failure(
                    .typeText,
                    message: ActionCapabilityDiagnostic.textEntryFailed(
                        operation: "typing",
                        stash: stash,
                        safecracker: safecracker,
                        suggestion: "focus an editable text field before typing"
                    )
                )
            }
        }

        guard await Task.cancellableSleep(for: TheSafecracker.keyboardPollInterval) else { return .failure(.typeText, message: "Cancelled") }
        stash.refresh()

        var fieldValue: String?
        if let elementTarget = target.elementTarget {
            if let resolved = stash.resolveTarget(elementTarget).resolved {
                fieldValue = resolved.element.value
            }
        }

        return TheSafecracker.InteractionResult(success: true, method: .typeText, message: nil, value: fieldValue)
    }

    private func focusTextInput(_ elementTarget: ElementTarget?) async -> TheSafecracker.InteractionResult? {
        guard let elementTarget else {
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

        await navigation.ensureOnScreen(for: elementTarget)
        let resolution = stash.resolveTarget(elementTarget)
        guard let resolved = resolution.resolved else {
            return .failure(.elementNotFound, message: resolution.diagnostics)
        }

        guard let point = stash.liveActivationPoint(for: resolved.screenElement) else {
            return .failure(
                .typeText,
                message: ActionCapabilityDiagnostic.gestureTargetUnavailable(
                    method: .syntheticTap,
                    element: resolved.screenElement,
                    isVisible: stash.visibleIds.contains(resolved.screenElement.heistId)
                )
            )
        }
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
        target: RotorTarget,
        direction: RotorDirection,
        element: TheStash.ScreenElement
    ) -> TheSafecracker.InteractionResult {
        switch outcome {
        case .succeeded(let hit):
            return rotorSuccessResult(hit, direction: direction)
        case .deallocated:
            return rotorFailure(
                .elementDeallocated,
                observed: "liveObject=deallocated before rotor step",
                target: target,
                element: element,
                suggestion: "refresh with get_interface and retarget the refreshed element"
            )
        case .noRotors:
            return rotorFailure(.rotor, observed: "customRotors=[]", target: target, element: element,
                                suggestion: "target an element exposing custom rotors")
        case .noSuchRotor(let available):
            return rotorFailure(.rotor, observed: "requestedRotor=\(ActionCapabilityDiagnostic.quote(target.rotor ?? "")) "
                                + "availableRotors=\(ActionCapabilityDiagnostic.formatQuotedList(available))",
                                target: target, element: element,
                                suggestion: "use one of available rotors \(ActionCapabilityDiagnostic.formatQuotedList(available))")
        case .ambiguousRotor(let available):
            return rotorFailure(.rotor, observed: "ambiguousRotor=\(ActionCapabilityDiagnostic.quote(target.rotor ?? "")) "
                                + "availableRotors=\(ActionCapabilityDiagnostic.formatQuotedList(available))",
                                target: target, element: element,
                                suggestion: "specify rotorIndex or an exact rotor name")
        case .currentItemUnavailable(let heistId):
            return rotorFailure(
                .elementNotFound,
                observed: "currentHeistId=\(ActionCapabilityDiagnostic.quote(heistId)) is not available",
                                target: target, element: element,
                                suggestion: "use the heistId returned by the previous rotor result after refetching")
        case .currentTextRangeUnavailable:
            return rotorFailure(.rotor, observed: "currentTextRange is not available", target: target, element: element,
                                suggestion: "use the text range returned by the previous rotor result after refetching")
        case .noResult(let rotorName):
            return rotorFailure(
                .rotor,
                observed: "rotor=\(ActionCapabilityDiagnostic.quote(rotorName)) returned no \(direction.rawValue) result",
                                target: target, element: element,
                                suggestion: "try the opposite rotor direction or stop at the current item")
        case .resultTargetUnavailable(let rotorName):
            return rotorFailure(
                .rotor,
                observed: "rotor=\(ActionCapabilityDiagnostic.quote(rotorName)) returned a result without an accessibility target",
                                target: target, element: element,
                                suggestion: "refetch with get_interface and retry the rotor from a visible target")
        case .resultTargetNotParsed(let rotorName):
            return rotorFailure(
                .rotor,
                observed: "rotor=\(ActionCapabilityDiagnostic.quote(rotorName)) returned a target outside the parsed hierarchy",
                                target: target, element: element,
                                suggestion: "refetch with get_interface before acting on the rotor result")
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
        return TheSafecracker.InteractionResult(
            success: true,
            method: .rotor,
            message: message,
            value: nil,
            rotorResult: RotorResult(
                rotor: hit.rotor,
                direction: direction,
                foundElement: found,
                textRange: hit.textRange
            )
        )
    }

    private static func rotorFailure(
        _ method: ActionMethod,
        observed: String,
        target: RotorTarget,
        element: TheStash.ScreenElement,
        suggestion: String
    ) -> TheSafecracker.InteractionResult {
        .failure(
            method,
            message: rotorDiagnostic(
                observed: observed,
                target: target,
                element: element,
                suggestion: suggestion
            )
        )
    }

    private static func rotorDiagnostic(
        observed: String,
        target: RotorTarget,
        element: TheStash.ScreenElement,
        suggestion: String
    ) -> String {
        var attempted: [String] = []
        if let rotor = target.rotor {
            attempted.append("rotor=\(ActionCapabilityDiagnostic.quote(rotor))")
        } else {
            attempted.append("rotor")
        }
        if let rotorIndex = target.rotorIndex {
            attempted.append("rotorIndex=\(rotorIndex)")
        }
        attempted.append("direction=\(target.resolvedDirection.rawValue)")

        let availableRotors = ActionCapabilityDiagnostic.availableRotors(for: element)
        return "rotor failed: attempted \(attempted.joined(separator: " ")) "
            + "on \(ActionCapabilityDiagnostic.formatElement(element)) "
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
        min(max(value ?? Self.defaultGestureDuration, Self.minGestureDuration), Self.maxGestureDuration)
    }

    func resolveDuration(_ duration: Double?, velocity: Double?, points: [CGPoint]) -> TimeInterval {
        let result: Double
        if let resolvedDuration = duration {
            result = resolvedDuration
        } else if let velocity = velocity, velocity > 0 {
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

#endif // DEBUG
#endif // canImport(UIKit)
