#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
import TheScore

// MARK: - Action Execution
//
// TheBagman resolves elements and performs all accessibility actions.
// TheSafecracker is only called for raw gesture synthesis (tap, swipe, etc.)
// when accessibility activation fails or for explicit touch commands.

extension TheBagman {

    // MARK: - Accessibility Actions

    func executeActivate(_ target: ElementTarget) async -> TheSafecracker.InteractionResult {
        await ensureOnScreen(for: target)
        let resolution = resolveTarget(target)
        guard let resolved = resolution.resolved else {
            return .failure(.elementNotFound, message: resolution.diagnostics)
        }

        if let interactivityError = checkElementInteractivity(resolved.element) {
            return .failure(.elementNotFound, message: interactivityError)
        }

        let point = resolved.element.activationPoint
        guard hasInteractiveObject(resolved.screenElement) else {
            return .failure(.activate, message: "Element does not support activation")
        }

        if activate(resolved.screenElement) {
            safecracker?.fingerprints.showFingerprint(at: point)
            return TheSafecracker.InteractionResult(success: true, method: .activate, message: nil, value: nil)
        }

        // Fall back to synthetic tap via TheSafecracker
        if let safecracker, await safecracker.tap(at: point) {
            safecracker.fingerprints.showFingerprint(at: point)
            return TheSafecracker.InteractionResult(success: true, method: .syntheticTap, message: nil, value: nil)
        }

        return .failure(.activate, message: "Activation failed")
    }

    func executeIncrement(_ target: ElementTarget) async -> TheSafecracker.InteractionResult {
        await ensureOnScreen(for: target)
        let resolution = resolveTarget(target)
        guard let resolved = resolution.resolved else {
            return .failure(.elementNotFound, message: resolution.diagnostics)
        }
        guard hasInteractiveObject(resolved.screenElement) else {
            return .failure(.increment, message: "Element does not support increment")
        }

        increment(resolved.screenElement)
        safecracker?.fingerprints.showFingerprint(at: resolved.element.activationPoint)
        return TheSafecracker.InteractionResult(success: true, method: .increment, message: nil, value: nil)
    }

    func executeDecrement(_ target: ElementTarget) async -> TheSafecracker.InteractionResult {
        await ensureOnScreen(for: target)
        let resolution = resolveTarget(target)
        guard let resolved = resolution.resolved else {
            return .failure(.elementNotFound, message: resolution.diagnostics)
        }
        guard hasInteractiveObject(resolved.screenElement) else {
            return .failure(.decrement, message: "Element does not support decrement")
        }

        decrement(resolved.screenElement)
        safecracker?.fingerprints.showFingerprint(at: resolved.element.activationPoint)
        return TheSafecracker.InteractionResult(success: true, method: .decrement, message: nil, value: nil)
    }

    func executeCustomAction(_ target: CustomActionTarget) async -> TheSafecracker.InteractionResult {
        await ensureOnScreen(for: target.elementTarget)
        let resolution = resolveTarget(target.elementTarget)
        guard let resolved = resolution.resolved else {
            return .failure(.elementNotFound, message: resolution.diagnostics)
        }
        guard hasInteractiveObject(resolved.screenElement) else {
            return .failure(.customAction, message: "Element does not support custom actions")
        }

        let success = performCustomAction(named: target.actionName, on: resolved.screenElement)
        return TheSafecracker.InteractionResult(
            success: success, method: .customAction,
            message: success ? nil : "Action '\(target.actionName)' not found",
            value: nil
        )
    }

    // MARK: - Edit / Pasteboard / Responder

    func executeEditAction(_ target: EditActionTarget) async -> TheSafecracker.InteractionResult {
        await ensureFirstResponderOnScreen()
        guard let safecracker else {
            return .failure(.editAction, message: "No gesture engine available")
        }
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
        guard let safecracker else {
            return .failure(.resignFirstResponder, message: "No gesture engine available")
        }
        let success = safecracker.resignFirstResponder()
        return TheSafecracker.InteractionResult(
            success: success, method: .resignFirstResponder,
            message: success ? nil : "No first responder found",
            value: nil
        )
    }

    // MARK: - Touch Gestures (element resolution → TheSafecracker)

    func executeTap(_ target: TouchTapTarget) async -> TheSafecracker.InteractionResult {
        if let elementTarget = target.elementTarget {
            await ensureOnScreen(for: elementTarget)
        }
        switch resolvePoint(from: target.elementTarget, pointX: target.pointX, pointY: target.pointY) {
        case .failure(let result): return result
        case .success(let point):
            guard let safecracker, await safecracker.tap(at: point) else {
                return .failure(.syntheticTap, message: "Touch tap failed")
            }
            safecracker.fingerprints.showFingerprint(at: point)
            return TheSafecracker.InteractionResult(success: true, method: .syntheticTap, message: nil, value: nil)
        }
    }

    func executeLongPress(_ target: LongPressTarget) async -> TheSafecracker.InteractionResult {
        if let elementTarget = target.elementTarget {
            await ensureOnScreen(for: elementTarget)
        }
        switch resolvePoint(from: target.elementTarget, pointX: target.pointX, pointY: target.pointY) {
        case .failure(let result): return result
        case .success(let point):
            let duration = clampDuration(target.duration)
            let success = await safecracker?.longPress(at: point, duration: duration) ?? false
            if success { safecracker?.fingerprints.showFingerprint(at: point) }
            return TheSafecracker.InteractionResult(success: success, method: .syntheticLongPress, message: nil, value: nil)
        }
    }

    func executeSwipe(_ target: SwipeTarget) async -> TheSafecracker.InteractionResult {
        if let elementTarget = target.elementTarget {
            await ensureOnScreen(for: elementTarget)
        }

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
            guard let frame = resolveFrame(for: elementTarget) else {
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
            let success = await safecracker?.swipe(from: startPoint, to: endPoint, duration: duration) ?? false
            return TheSafecracker.InteractionResult(success: success, method: .syntheticSwipe, message: nil, value: nil)
        }

        switch resolvePoint(from: target.elementTarget, pointX: target.startX, pointY: target.startY) {
        case .failure(let result): return result
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
            let success = await safecracker?.swipe(from: startPoint, to: endPoint, duration: duration) ?? false
            return TheSafecracker.InteractionResult(success: success, method: .syntheticSwipe, message: nil, value: nil)
        }
    }

    func executeDrag(_ target: DragTarget) async -> TheSafecracker.InteractionResult {
        if let elementTarget = target.elementTarget {
            await ensureOnScreen(for: elementTarget)
        }
        switch resolvePoint(from: target.elementTarget, pointX: target.startX, pointY: target.startY) {
        case .failure(let result): return result
        case .success(let startPoint):
            let duration = clampDuration(target.duration ?? 0.5)
            let success = await safecracker?.drag(from: startPoint, to: target.endPoint, duration: duration) ?? false
            return TheSafecracker.InteractionResult(success: success, method: .syntheticDrag, message: nil, value: nil)
        }
    }

    func executePinch(_ target: PinchTarget) async -> TheSafecracker.InteractionResult {
        if let elementTarget = target.elementTarget {
            await ensureOnScreen(for: elementTarget)
        }
        switch resolvePoint(from: target.elementTarget, pointX: target.centerX, pointY: target.centerY) {
        case .failure(let result): return result
        case .success(let center):
            let spread = target.spread ?? 100.0
            let duration = clampDuration(target.duration ?? 0.5)
            let success = await safecracker?.pinch(center: center, scale: CGFloat(target.scale), spread: CGFloat(spread), duration: duration) ?? false
            return TheSafecracker.InteractionResult(success: success, method: .syntheticPinch, message: nil, value: nil)
        }
    }

    func executeRotate(_ target: RotateTarget) async -> TheSafecracker.InteractionResult {
        if let elementTarget = target.elementTarget {
            await ensureOnScreen(for: elementTarget)
        }
        switch resolvePoint(from: target.elementTarget, pointX: target.centerX, pointY: target.centerY) {
        case .failure(let result): return result
        case .success(let center):
            let radius = target.radius ?? 100.0
            let duration = clampDuration(target.duration ?? 0.5)
            let success = await safecracker?.rotate(center: center, angle: CGFloat(target.angle), radius: CGFloat(radius), duration: duration) ?? false
            return TheSafecracker.InteractionResult(success: success, method: .syntheticRotate, message: nil, value: nil)
        }
    }

    func executeTwoFingerTap(_ target: TwoFingerTapTarget) async -> TheSafecracker.InteractionResult {
        if let elementTarget = target.elementTarget {
            await ensureOnScreen(for: elementTarget)
        }
        switch resolvePoint(from: target.elementTarget, pointX: target.centerX, pointY: target.centerY) {
        case .failure(let result): return result
        case .success(let center):
            let spread = target.spread ?? 40.0
            let success = await safecracker?.twoFingerTap(at: center, spread: CGFloat(spread)) ?? false
            if success { safecracker?.fingerprints.showFingerprint(at: center) }
            return TheSafecracker.InteractionResult(success: success, method: .syntheticTwoFingerTap, message: nil, value: nil)
        }
    }

    func executeDrawPath(_ target: DrawPathTarget) async -> TheSafecracker.InteractionResult {
        let cgPoints = target.points.map { $0.cgPoint }
        guard cgPoints.count >= 2 else {
            return .failure(.syntheticDrawPath, message: "Path requires at least 2 points")
        }
        let duration = resolveDuration(target.duration, velocity: target.velocity, points: cgPoints)
        let success = await safecracker?.drawPath(points: cgPoints, duration: duration) ?? false
        return TheSafecracker.InteractionResult(success: success, method: .syntheticDrawPath, message: nil, value: nil)
    }

    func executeDrawBezier(_ target: DrawBezierTarget) async -> TheSafecracker.InteractionResult {
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
        let success = await safecracker?.drawPath(points: cgPoints, duration: duration) ?? false
        return TheSafecracker.InteractionResult(success: success, method: .syntheticDrawPath, message: nil, value: nil)
    }

    // MARK: - Text Entry

    func executeTypeText(_ target: TypeTextTarget) async -> TheSafecracker.InteractionResult {
        guard let safecracker else {
            return .failure(.typeText, message: "No gesture engine available")
        }

        // Step 0: If element target provided, resolve and tap to focus
        if let elementTarget = target.elementTarget {
            await ensureOnScreen(for: elementTarget)
            let resolution = resolveTarget(elementTarget)
            guard let resolved = resolution.resolved else {
                return .failure(.elementNotFound, message: resolution.diagnostics)
            }

            let point = resolved.element.activationPoint
            guard await safecracker.tap(at: point) else {
                return .failure(.typeText, message: "Failed to tap target element to bring up keyboard")
            }
            safecracker.fingerprints.showFingerprint(at: point)

            // Wait for keyboard
            var inputReady = false
            for _ in 0..<TheSafecracker.keyboardPollMaxAttempts {
                try? await Task.sleep(nanoseconds: TheSafecracker.keyboardPollInterval)
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
                let msg = "No active text input. Provide an elementTarget to focus a text field, " +
                    "or ensure a text field is already focused."
                return .failure(.typeText, message: msg)
            }
        }

        // Step 1: Clear existing text if requested
        let interKeyDelay = min(TheSafecracker.defaultInterKeyDelay, TheSafecracker.maxInterKeyDelay)
        if target.clearFirst == true {
            guard await safecracker.clearText() else {
                return .failure(.typeText, message: "Failed to clear existing text.")
            }
        }

        // Step 2: Delete characters if requested
        if let deleteCount = target.deleteCount, deleteCount > 0 {
            guard await safecracker.deleteText(count: deleteCount, interKeyDelay: interKeyDelay) else {
                return .failure(.typeText, message: "No keyboard or focused text input available for delete.")
            }
        }

        // Step 3: Type text if provided
        if let text = target.text, !text.isEmpty {
            guard await safecracker.typeText(text, interKeyDelay: interKeyDelay) else {
                return .failure(.typeText, message: "No keyboard or focused text input available for typing.")
            }
        }

        // Step 4: Refresh and read back value
        try? await Task.sleep(nanoseconds: TheSafecracker.keyboardPollInterval)
        refreshElements()

        var fieldValue: String?
        if let elementTarget = target.elementTarget {
            if let resolved = resolveTarget(elementTarget).resolved {
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
        if let d = duration {
            result = d
        } else if let velocity = velocity, velocity > 0 {
            var totalLength: Double = 0
            for i in 1..<points.count {
                let dx = points[i].x - points[i-1].x
                let dy = points[i].y - points[i-1].y
                totalLength += sqrt(dx * dx + dy * dy)
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
