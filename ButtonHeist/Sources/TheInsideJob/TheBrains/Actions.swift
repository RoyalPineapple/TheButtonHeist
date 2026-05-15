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
            await navigation.ensureOnScreen(for: elementTarget)
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
            // First attempt — accessibilityActivate on the live UIKit object.
            let firstOutcome = self.stash.activate(resolved.screenElement)
            if firstOutcome == .success {
                self.safecracker.showFingerprint(at: resolved.element.activationPoint)
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
                self.safecracker.showFingerprint(at: retryResolved.element.activationPoint)
                return TheSafecracker.InteractionResult(success: true, method: .activate, message: nil, value: nil)
            }

            // Synthetic tap fallback at the post-retry activation point.
            let tapPoint = retryResolved.element.activationPoint
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
                return .failure(.increment, message: "Element is not adjustable")
            }
            guard self.stash.increment(resolved.screenElement) else {
                return .failure(.elementDeallocated, message: "Element deallocated before increment")
            }
            self.safecracker.showFingerprint(at: resolved.element.activationPoint)
            return TheSafecracker.InteractionResult(success: true, method: .increment, message: nil, value: nil)
        }
    }

    func executeDecrement(_ target: ElementTarget) async -> TheSafecracker.InteractionResult {
        await performElementAction(target: target, method: .decrement) { resolved in
            guard resolved.element.traits.contains(.adjustable) else {
                return .failure(.decrement, message: "Element is not adjustable")
            }
            guard self.stash.decrement(resolved.screenElement) else {
                return .failure(.elementDeallocated, message: "Element deallocated before decrement")
            }
            self.safecracker.showFingerprint(at: resolved.element.activationPoint)
            return TheSafecracker.InteractionResult(success: true, method: .decrement, message: nil, value: nil)
        }
    }

    func executeCustomAction(_ target: CustomActionTarget) async -> TheSafecracker.InteractionResult {
        await performElementAction(target: target.elementTarget, method: .customAction) { resolved in
            switch self.stash.performCustomAction(named: target.actionName, on: resolved.screenElement) {
            case .deallocated:
                return .failure(.elementDeallocated, message: "Element deallocated before custom action")
            case .noSuchAction:
                return .failure(.customAction, message: "Action '\(target.actionName)' not found")
            case .declined:
                return .failure(.customAction, message: "Action '\(target.actionName)' declined by handler")
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
            switch self.stash.performRotor(target, direction: direction, on: resolved.screenElement) {
            case .deallocated:
                return .failure(.elementDeallocated, message: "Element deallocated before rotor step")
            case .noRotors:
                return .failure(method, message: "Element has no custom rotors")
            case .noSuchRotor(let available):
                return .failure(
                    method,
                    message: "Rotor not found. Available: \(available.joined(separator: ", "))"
                )
            case .ambiguousRotor(let available):
                return .failure(
                    method,
                    message: "Multiple rotors available: \(available.joined(separator: ", ")). Specify rotor or rotorIndex."
                )
            case .currentItemUnavailable(let heistId):
                return .failure(.elementNotFound, message: "Current rotor item '\(heistId)' is not available")
            case .currentTextRangeUnavailable:
                return .failure(method, message: "Current rotor text range is not available")
            case .noResult(let rotorName):
                return .failure(
                    method,
                    message: "Rotor '\(rotorName)' returned no \(direction.rawValue) result"
                )
            case .resultTargetUnavailable(let rotorName):
                return .failure(
                    method,
                    message: "Rotor '\(rotorName)' returned a result without an accessibility target"
                )
            case .resultTargetNotParsed(let rotorName):
                return .failure(
                    method,
                    message: "Rotor '\(rotorName)' returned a target outside the parsed accessibility hierarchy"
                )
            case .succeeded(let hit):
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
                    method: method,
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
        }
    }

    // MARK: - Edit / Pasteboard / Responder

    func executeEditAction(_ target: EditActionTarget) async -> TheSafecracker.InteractionResult {
        await navigation.ensureFirstResponderOnScreen()
        let success = safecracker.performEditAction(target.action)
        return TheSafecracker.InteractionResult(success: success, method: .editAction, message: nil, value: nil)
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
            await navigation.ensureOnScreen(for: elementTarget)
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
            await navigation.ensureOnScreen(for: elementTarget)
        }
        switch stash.resolvePoint(from: target.elementTarget, pointX: target.startX, pointY: target.startY) {
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
            await navigation.ensureOnScreen(for: elementTarget)
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
