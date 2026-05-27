#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

extension Actions {

    /// Unified pipeline for gestures that target a screen point:
    /// semantic selector → actionable target (if element target) → point → gesture.
    func performPointAction(
        elementTarget: (any SemanticElementTarget)?,
        pointX: Double?,
        pointY: Double?,
        method: ActionMethod,
        recordedScreen: Screen? = nil,
        action: (CGPoint) async -> Bool
    ) async -> TheSafecracker.InteractionResult {
        let normalizedTarget = elementTarget.map {
            normalizePointGestureTarget($0, recordedScreen: recordedScreen)
        }
        let actionableTarget: SemanticActionability.SemanticActionableTarget?
        if let normalizedTarget {
            switch await actionability.makeActionable(
                for: normalizedTarget,
                method: method,
                deallocatedBoundary: "gesture action"
            ) {
            case .actionable(let target):
                actionableTarget = target
            case .failed(let failure):
                return failure.interactionResult(commandMethod: method)
            }
        } else {
            actionableTarget = nil
        }
        switch resolveGesturePoint(from: actionableTarget, pointX: pointX, pointY: pointY, method: method) {
        case .failure(let result):
            return result
        case .success(let point):
            if let failure = geometryFailure(method: method, field: "point", point: point) {
                return failure
            }
            let success = await action(point)
            if success { safecracker.showFingerprint(at: point) }
            return gestureDispatchResult(method: method, diagnosticPoint: point, success: success)
        }
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
            let normalizedTarget = normalizePointGestureTarget(elementTarget, recordedScreen: recordedScreen)
            let actionableTarget: SemanticActionability.SemanticActionableTarget
            switch await actionability.makeActionable(
                for: normalizedTarget,
                method: .syntheticSwipe,
                deallocatedBoundary: "gesture action"
            ) {
            case .actionable(let target):
                actionableTarget = target
            case .failed(let failure):
                return failure.interactionResult(commandMethod: .syntheticSwipe)
            }
            let frame: CGRect
            switch resolveGestureFrame(for: actionableTarget, method: .syntheticSwipe) {
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
            let duration = clampDuration(target.resolvedDuration)
            return await performResolvedSwipe(from: startPoint, to: endPoint, duration: duration)
        }

        // Absolute-point swipe: resolve start point, compute end from direction or explicit coords
        let normalizedTarget = target.swipeElementTarget.map {
            normalizePointGestureTarget($0, recordedScreen: recordedScreen)
        }
        let actionableTarget: SemanticActionability.SemanticActionableTarget?
        if let normalizedTarget {
            switch await actionability.makeActionable(
                for: normalizedTarget,
                method: .syntheticSwipe,
                deallocatedBoundary: "gesture action"
            ) {
            case .actionable(let target):
                actionableTarget = target
            case .failed(let failure):
                return failure.interactionResult(commandMethod: .syntheticSwipe)
            }
        } else {
            actionableTarget = nil
        }
        switch resolveGesturePoint(
            from: actionableTarget,
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
            let duration = clampDuration(target.resolvedDuration)
            return await performResolvedSwipe(from: startPoint, to: endPoint, duration: duration)
        }
    }

    private func performResolvedSwipe(
        from startPoint: CGPoint,
        to endPoint: CGPoint,
        duration: TimeInterval
    ) async -> TheSafecracker.InteractionResult {
        let success = await safecracker.swipe(from: startPoint, to: endPoint, duration: duration)
        return gestureDispatchResult(method: .syntheticSwipe, diagnosticPoint: startPoint, success: success)
    }

    private func unitSwipePoints(
        elementTarget: (any SemanticElementTarget)?,
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
        let duration = clampDuration(target.resolvedDuration)
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
        let spread = target.resolvedSpread
        let duration = clampDuration(target.resolvedDuration)
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
        let radius = target.resolvedRadius
        let duration = clampDuration(target.resolvedDuration)
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
        let spread = target.resolvedSpread
        return await performPointAction(
            elementTarget: target.twoFingerTapElementTarget, pointX: target.centerX, pointY: target.centerY,
            method: .syntheticTwoFingerTap,
            recordedScreen: recordedScreen
        ) { center in
            await self.safecracker.twoFingerTap(at: center, spread: CGFloat(spread))
        }
    }

    private func normalizePointGestureTarget(
        _ target: any SemanticElementTarget,
        recordedScreen: Screen?
    ) -> TheStash.NormalizedTarget {
        stash.normalizeTarget(target, in: pointGestureSourceScreen(recordedScreen))
    }

    private func pointGestureSourceScreen(_ recordedScreen: Screen?) -> Screen {
        if let recordedScreen {
            return recordedScreen
        }
        return stash.currentScreen
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
        return await performResolvedDrawPath(points: cgPoints, duration: duration)
    }

    func executeDrawBezier(_ target: DrawBezierTarget) async -> TheSafecracker.InteractionResult {
        guard target.segments.count <= 1_000 else {
            return .failure(.syntheticDrawPath, message: "Too many segments (max 1,000)")
        }
        guard !target.segments.isEmpty else {
            return .failure(.syntheticDrawPath, message: "Bezier path requires at least 1 segment")
        }
        let samplesPerSegment = target.resolvedSamplesPerSegment
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
        return await performResolvedDrawPath(points: cgPoints, duration: duration)
    }

    private func performResolvedDrawPath(
        points: [CGPoint],
        duration: TimeInterval
    ) async -> TheSafecracker.InteractionResult {
        let success = await safecracker.drawPath(points: points, duration: duration)
        return gestureDispatchResult(
            method: .syntheticDrawPath,
            diagnosticPoint: points[0],
            success: success
        )
    }

    private func gestureDispatchResult(
        method: ActionMethod,
        diagnosticPoint: CGPoint,
        success: Bool
    ) -> TheSafecracker.InteractionResult {
        guard !success else {
            return .success(method: method)
        }
        return .failure(
            method,
            message: ActionCapabilityDiagnostic.gestureDispatchFailed(
                method: method,
                point: diagnosticPoint,
                receiver: safecracker.tapReceiverDiagnostic(at: diagnosticPoint)
            )
        )
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
