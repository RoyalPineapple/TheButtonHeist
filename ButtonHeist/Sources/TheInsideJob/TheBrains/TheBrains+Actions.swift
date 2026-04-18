#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

// MARK: - Action Execution
//
// Two generic pipelines handle all element and point interactions.
// Each executeXxx method is a thin wrapper that feeds the pipeline
// a closure for the actual gesture or accessibility action.

extension TheBrains {

    // MARK: - Element Action Pipeline

    /// Unified pipeline for actions that target an element:
    /// ensureOnScreen → resolve → check interactivity → perform action.
    func performElementAction(
        target: ElementTarget,
        method: ActionMethod,
        requireInteractive: Bool = true,
        action: @MainActor (TheStash.ResolvedTarget) async -> TheSafecracker.InteractionResult?
    ) async -> TheSafecracker.InteractionResult {
        await ensureOnScreen(for: target)
        let resolution = stash.resolveTarget(target)
        guard let resolved = resolution.resolved else {
            return .failure(.elementNotFound, message: resolution.diagnostics)
        }
        if requireInteractive {
            switch stash.checkElementInteractivity(resolved.element) {
            case .blocked(let reason):
                return .failure(method, message: reason)
            case .interactive(let warning):
                if let warning { insideJobLogger.warning("\(warning)") }
            }
            guard stash.hasInteractiveObject(resolved.screenElement) else {
                return .failure(method, message: "Element does not support \(method.rawValue)")
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
            await ensureOnScreen(for: elementTarget)
        }
        switch stash.resolvePoint(from: elementTarget, pointX: pointX, pointY: pointY) {
        case .failure(let result):
            return result
        case .success(let point):
            let success = await action(point)
            if success { safecracker.showFingerprint(at: point) }
            return TheSafecracker.InteractionResult(success: success, method: method, message: nil, value: nil)
        }
    }

    // MARK: - Accessibility Actions

    func executeActivate(_ target: ElementTarget) async -> TheSafecracker.InteractionResult {
        await performElementAction(target: target, method: .activate) { resolved in
            let point = resolved.element.activationPoint
            if stash.activate(resolved.screenElement) {
                self.safecracker.showFingerprint(at: point)
                return TheSafecracker.InteractionResult(success: true, method: .activate, message: nil, value: nil)
            }
            if await self.safecracker.tap(at: point) {
                self.safecracker.showFingerprint(at: point)
                return TheSafecracker.InteractionResult(success: true, method: .syntheticTap, message: nil, value: nil)
            }
            return nil
        }
    }

    func executeIncrement(_ target: ElementTarget) async -> TheSafecracker.InteractionResult {
        await performElementAction(target: target, method: .increment) { resolved in
            guard stash.increment(resolved.screenElement) else {
                return .failure(.elementDeallocated, message: "Element deallocated before increment")
            }
            self.safecracker.showFingerprint(at: resolved.element.activationPoint)
            return TheSafecracker.InteractionResult(success: true, method: .increment, message: nil, value: nil)
        }
    }

    func executeDecrement(_ target: ElementTarget) async -> TheSafecracker.InteractionResult {
        await performElementAction(target: target, method: .decrement) { resolved in
            guard stash.decrement(resolved.screenElement) else {
                return .failure(.elementDeallocated, message: "Element deallocated before decrement")
            }
            self.safecracker.showFingerprint(at: resolved.element.activationPoint)
            return TheSafecracker.InteractionResult(success: true, method: .decrement, message: nil, value: nil)
        }
    }

    func executeCustomAction(_ target: CustomActionTarget) async -> TheSafecracker.InteractionResult {
        await performElementAction(target: target.elementTarget, method: .customAction) { resolved in
            guard resolved.screenElement.object != nil else {
                return .failure(.elementDeallocated, message: "Element deallocated before custom action")
            }
            let success = stash.performCustomAction(named: target.actionName, on: resolved.screenElement)
            return TheSafecracker.InteractionResult(
                success: success, method: .customAction,
                message: success ? nil : "Action '\(target.actionName)' not found",
                value: nil
            )
        }
    }

    // MARK: - Edit / Pasteboard / Responder

    func executeEditAction(_ target: EditActionTarget) async -> TheSafecracker.InteractionResult {
        await ensureFirstResponderOnScreen()
        let success = safecracker.performEditAction(target.action)
        return TheSafecracker.InteractionResult(success: success, method: .editAction, message: nil, value: nil)
    }

    func executeSetPasteboard(_ target: SetPasteboardTarget) async -> TheSafecracker.InteractionResult {
        await ensureFirstResponderOnScreen()
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
        await ensureFirstResponderOnScreen()
        let success = safecracker.resignFirstResponder()
        return TheSafecracker.InteractionResult(
            success: success, method: .resignFirstResponder,
            message: success ? nil : "No first responder found",
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
                return .failure(.syntheticSwipe, message: "Unit-point swipe requires an element target")
            }
            await ensureOnScreen(for: elementTarget)
            guard let frame = stash.resolveFrame(for: elementTarget) else {
                return .failure(.elementNotFound, message: "Element not found")
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
            return TheSafecracker.InteractionResult(success: success, method: .syntheticSwipe, message: nil, value: nil)
        }

        // Absolute-point swipe: resolve start point, compute end from direction or explicit coords
        if let elementTarget = target.elementTarget {
            await ensureOnScreen(for: elementTarget)
        }
        switch stash.resolvePoint(from: target.elementTarget, pointX: target.startX, pointY: target.startY) {
        case .failure(let result):
            return result
        case .success(let startPoint):
            let endPoint: CGPoint
            if let endX = target.endX, let endY = target.endY {
                endPoint = CGPoint(x: endX, y: endY)
            } else if let direction = target.direction {
                let dist = 200.0
                switch direction {
                case .up:    endPoint = CGPoint(x: startPoint.x, y: startPoint.y - dist)
                case .down:  endPoint = CGPoint(x: startPoint.x, y: startPoint.y + dist)
                case .left:  endPoint = CGPoint(x: startPoint.x - dist, y: startPoint.y)
                case .right: endPoint = CGPoint(x: startPoint.x + dist, y: startPoint.y)
                }
            } else {
                return .failure(.syntheticSwipe, message: "No end point or direction")
            }
            let duration = clampDuration(target.duration ?? 0.15)
            let success = await safecracker.swipe(from: startPoint, to: endPoint, duration: duration)
            return TheSafecracker.InteractionResult(success: success, method: .syntheticSwipe, message: nil, value: nil)
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
        return TheSafecracker.InteractionResult(success: success, method: .syntheticDrawPath, message: nil, value: nil)
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
        return TheSafecracker.InteractionResult(success: success, method: .syntheticDrawPath, message: nil, value: nil)
    }

    // MARK: - Text Entry

    func executeTypeText(_ target: TypeTextTarget) async -> TheSafecracker.InteractionResult {
        if let elementTarget = target.elementTarget {
            await ensureOnScreen(for: elementTarget)
            let resolution = stash.resolveTarget(elementTarget)
            guard let resolved = resolution.resolved else {
                return .failure(.elementNotFound, message: resolution.diagnostics)
            }

            let point = resolved.element.activationPoint
            guard await safecracker.tap(at: point) else {
                return .failure(.typeText, message: "Failed to tap target element to bring up keyboard")
            }
            safecracker.showFingerprint(at: point)

            var inputReady = false
            for _ in 0..<TheSafecracker.keyboardPollMaxAttempts {
                guard await Task.cancellableSleep(for: TheSafecracker.keyboardPollInterval) else { break }
                if safecracker.hasActiveTextInput() {
                    inputReady = true
                    break
                }
            }

            if !inputReady {
                return .failure(.typeText, message: "No active text input after tapping element. The element may not be a text field.")
            }
        } else {
            guard safecracker.hasActiveTextInput() else {
                let message = "No active text input. Provide an elementTarget to focus a text field, "
                    + "or ensure a text field is already focused."
                return .failure(.typeText, message: message)
            }
        }

        let interKeyDelay = min(TheSafecracker.defaultInterKeyDelay, TheSafecracker.maxInterKeyDelay)
        if target.clearFirst == true {
            guard await safecracker.clearText() else {
                return .failure(.typeText, message: "Failed to clear existing text.")
            }
        }

        if let deleteCount = target.deleteCount, deleteCount > 0 {
            guard await safecracker.deleteText(count: deleteCount, interKeyDelay: interKeyDelay) else {
                return .failure(.typeText, message: "No keyboard or focused text input available for delete.")
            }
        }

        if let text = target.text, !text.isEmpty {
            guard await safecracker.typeText(text, interKeyDelay: interKeyDelay) else {
                return .failure(.typeText, message: "No keyboard or focused text input available for typing.")
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

    // MARK: - Duration Helpers

    private static let defaultGestureDuration: Double = 0.5
    private static let minGestureDuration: Double = 0.01
    private static let maxGestureDuration: Double = 60.0

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
