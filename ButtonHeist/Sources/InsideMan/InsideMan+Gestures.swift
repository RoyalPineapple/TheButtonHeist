#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
import TheGoods

extension InsideMan {

    // MARK: - Touch Gesture Handlers

    func handleTouchTap(_ target: TouchTapTarget, respond: @escaping (Data) -> Void) async {
        guard let point = resolvePoint(from: target.elementTarget, pointX: target.pointX, pointY: target.pointY, respond: respond) else { return }
        if target.elementTarget == nil { refreshAccessibilityData() }
        let beforeElements = snapshotElements()

        // If we have an element target, try activation via live object first
        if let elementTarget = target.elementTarget,
           let index = resolveTraversalIndex(for: elementTarget),
           activate(elementAt: index) {
            TapVisualizerView.showTap(at: point)
            let result = await actionResultWithDelta(success: true, method: .activate, beforeElements: beforeElements)
            sendMessage(.actionResult(result), respond: respond)
            return
        }

        // Fall back to synthetic tap
        if theSafecracker.tap(at: point) {
            TapVisualizerView.showTap(at: point)
            let result = await actionResultWithDelta(success: true, method: .syntheticTap, beforeElements: beforeElements)
            sendMessage(.actionResult(result), respond: respond)
            return
        }

        sendMessage(.actionResult(ActionResult(success: false, method: .syntheticTap, message: "Touch tap failed")), respond: respond)
    }

    func handleTouchLongPress(_ target: LongPressTarget, respond: @escaping (Data) -> Void) async {
        guard let point = resolvePoint(from: target.elementTarget, pointX: target.pointX, pointY: target.pointY, respond: respond) else { return }
        if target.elementTarget == nil { refreshAccessibilityData() }
        let beforeElements = snapshotElements()

        let success = await theSafecracker.longPress(at: point, duration: clampDuration(target.duration))
        if success { TapVisualizerView.showTap(at: point) }
        let result = await actionResultWithDelta(success: success, method: .syntheticLongPress, beforeElements: beforeElements)
        sendMessage(.actionResult(result), respond: respond)
    }

    func handleTouchSwipe(_ target: SwipeTarget, respond: @escaping (Data) -> Void) async {
        guard let startPoint = resolvePoint(from: target.elementTarget, pointX: target.startX, pointY: target.startY, respond: respond) else { return }

        // Resolve end point from explicit coordinates or direction
        let endPoint: CGPoint
        if let endX = target.endX, let endY = target.endY {
            endPoint = CGPoint(x: endX, y: endY)
        } else if let direction = target.direction {
            let dist = target.distance ?? 200.0
            switch direction {
            case .up:    endPoint = CGPoint(x: startPoint.x, y: startPoint.y - dist)
            case .down:  endPoint = CGPoint(x: startPoint.x, y: startPoint.y + dist)
            case .left:  endPoint = CGPoint(x: startPoint.x - dist, y: startPoint.y)
            case .right: endPoint = CGPoint(x: startPoint.x + dist, y: startPoint.y)
            }
        } else {
            sendMessage(.actionResult(ActionResult(success: false, method: .syntheticSwipe, message: "No end point or direction")), respond: respond)
            return
        }

        if target.elementTarget == nil { refreshAccessibilityData() }
        let beforeElements = snapshotElements()
        let duration = clampDuration(target.duration ?? 0.15)

        let success = await theSafecracker.swipe(from: startPoint, to: endPoint, duration: duration)
        let result = await actionResultWithDelta(success: success, method: .syntheticSwipe, beforeElements: beforeElements)
        sendMessage(.actionResult(result), respond: respond)
    }

    func handleTouchDrag(_ target: DragTarget, respond: @escaping (Data) -> Void) async {
        guard let startPoint = resolvePoint(from: target.elementTarget, pointX: target.startX, pointY: target.startY, respond: respond) else { return }
        if target.elementTarget == nil { refreshAccessibilityData() }
        let beforeElements = snapshotElements()

        let duration = clampDuration(target.duration ?? 0.5)
        let success = await theSafecracker.drag(from: startPoint, to: target.endPoint, duration: duration)
        let result = await actionResultWithDelta(success: success, method: .syntheticDrag, beforeElements: beforeElements)
        sendMessage(.actionResult(result), respond: respond)
    }

    func handleTouchPinch(_ target: PinchTarget, respond: @escaping (Data) -> Void) async {
        guard let center = resolvePoint(from: target.elementTarget, pointX: target.centerX, pointY: target.centerY, respond: respond) else { return }
        if target.elementTarget == nil { refreshAccessibilityData() }
        let beforeElements = snapshotElements()

        let spread = target.spread ?? 100.0
        let duration = clampDuration(target.duration ?? 0.5)
        let success = await theSafecracker.pinch(center: center, scale: CGFloat(target.scale), spread: CGFloat(spread), duration: duration)
        let result = await actionResultWithDelta(success: success, method: .syntheticPinch, beforeElements: beforeElements)
        sendMessage(.actionResult(result), respond: respond)
    }

    func handleTouchRotate(_ target: RotateTarget, respond: @escaping (Data) -> Void) async {
        guard let center = resolvePoint(from: target.elementTarget, pointX: target.centerX, pointY: target.centerY, respond: respond) else { return }
        if target.elementTarget == nil { refreshAccessibilityData() }
        let beforeElements = snapshotElements()

        let radius = target.radius ?? 100.0
        let duration = clampDuration(target.duration ?? 0.5)
        let success = await theSafecracker.rotate(center: center, angle: CGFloat(target.angle), radius: CGFloat(radius), duration: duration)
        let result = await actionResultWithDelta(success: success, method: .syntheticRotate, beforeElements: beforeElements)
        sendMessage(.actionResult(result), respond: respond)
    }

    func handleTouchTwoFingerTap(_ target: TwoFingerTapTarget, respond: @escaping (Data) -> Void) async {
        guard let center = resolvePoint(from: target.elementTarget, pointX: target.centerX, pointY: target.centerY, respond: respond) else { return }
        if target.elementTarget == nil { refreshAccessibilityData() }
        let beforeElements = snapshotElements()

        let spread = target.spread ?? 40.0
        let success = theSafecracker.twoFingerTap(at: center, spread: CGFloat(spread))
        let result = await actionResultWithDelta(success: success, method: .syntheticTwoFingerTap, beforeElements: beforeElements)
        sendMessage(.actionResult(result), respond: respond)
    }

    func handleTouchDrawPath(_ target: DrawPathTarget, respond: @escaping (Data) -> Void) async {
        let cgPoints = target.points.map { $0.cgPoint }

        guard cgPoints.count >= 2 else {
            sendMessage(.actionResult(ActionResult(
                success: false,
                method: .syntheticDrawPath,
                message: "Path requires at least 2 points"
            )), respond: respond)
            return
        }

        refreshAccessibilityData()
        let beforeElements = snapshotElements()
        let duration = resolveDuration(target.duration, velocity: target.velocity, points: cgPoints)

        let success = await theSafecracker.drawPath(points: cgPoints, duration: duration)
        let result = await actionResultWithDelta(success: success, method: .syntheticDrawPath, beforeElements: beforeElements)
        sendMessage(.actionResult(result), respond: respond)
    }

    func handleTouchDrawBezier(_ target: DrawBezierTarget, respond: @escaping (Data) -> Void) async {
        guard !target.segments.isEmpty else {
            sendMessage(.actionResult(ActionResult(
                success: false,
                method: .syntheticDrawPath,
                message: "Bezier path requires at least 1 segment"
            )), respond: respond)
            return
        }

        let samplesPerSegment = min(target.samplesPerSegment ?? 20, 1000)
        let pathPoints = BezierSampler.sampleBezierPath(
            startPoint: target.startPoint,
            segments: target.segments,
            samplesPerSegment: samplesPerSegment
        )
        let cgPoints = pathPoints.map { $0.cgPoint }

        guard cgPoints.count >= 2 else {
            sendMessage(.actionResult(ActionResult(
                success: false,
                method: .syntheticDrawPath,
                message: "Sampled bezier produced fewer than 2 points"
            )), respond: respond)
            return
        }

        refreshAccessibilityData()
        let beforeElements = snapshotElements()
        let duration = resolveDuration(target.duration, velocity: target.velocity, points: cgPoints)

        let success = await theSafecracker.drawPath(points: cgPoints, duration: duration)
        let result = await actionResultWithDelta(success: success, method: .syntheticDrawPath, beforeElements: beforeElements)
        sendMessage(.actionResult(result), respond: respond)
    }

    // MARK: - Input Validation

    private func clampDuration(_ value: Double?) -> Double {
        min(max(value ?? 0.5, 0.01), 60.0)
    }

    // MARK: - Shared Helpers

    private func resolveDuration(_ duration: Double?, velocity: Double?, points: [CGPoint]) -> TimeInterval {
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
            result = 0.5
        }
        return clampDuration(result)
    }

    /// Resolve a screen point from an element target or explicit coordinates.
    /// Sends an error response and returns nil if resolution fails.
    private func resolvePoint(
        from elementTarget: ActionTarget?,
        pointX: Double?,
        pointY: Double?,
        respond: @escaping (Data) -> Void
    ) -> CGPoint? {
        if let elementTarget {
            refreshAccessibilityData()
            guard let element = findElement(for: elementTarget) else {
                sendMessage(.actionResult(ActionResult(success: false, method: .elementNotFound)), respond: respond)
                return nil
            }
            return element.activationPoint
        } else if let x = pointX, let y = pointY {
            return CGPoint(x: x, y: y)
        } else {
            sendMessage(.actionResult(ActionResult(success: false, method: .elementNotFound, message: "No target specified")), respond: respond)
            return nil
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
