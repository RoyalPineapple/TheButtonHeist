#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
import TheScore

extension TheSafecracker {

    // MARK: - Accessibility Actions

    func executeActivate(_ target: ActionTarget) -> InteractionResult {
        guard let bagman else {
            return .failure(.elementNotFound, message: "No element store available")
        }
        guard let element = bagman.findElement(for: target) else {
            return .failure(.elementNotFound, message: "Element not found for target")
        }

        if let interactivityError = bagman.checkElementInteractivity(element) {
            return .failure(.elementNotFound, message: interactivityError)
        }

        let point = element.activationPoint

        guard let index = bagman.resolveTraversalIndex(for: target),
              bagman.hasInteractiveObject(at: index) else {
            return .failure(.activate, message: "Element does not support activation")
        }

        // Try accessibilityActivate via the live object reference
        if bagman.activate(elementAt: index) {
            fingerprints.showFingerprint(at: point)
            return InteractionResult(success: true, method: .activate, message: nil, value: nil)
        }

        // Fall back to synthetic touch injection
        if tap(at: point) {
            fingerprints.showFingerprint(at: point)
            return InteractionResult(success: true, method: .syntheticTap, message: nil, value: nil)
        }

        return .failure(.activate, message: "Activation failed")
    }

    func executeIncrement(_ target: ActionTarget) -> InteractionResult {
        guard let bagman else {
            return .failure(.elementNotFound, message: "No element store available")
        }
        guard let element = bagman.findElement(for: target) else {
            return .failure(.elementNotFound, message: "Element not found")
        }

        guard let index = bagman.resolveTraversalIndex(for: target),
              bagman.hasInteractiveObject(at: index) else {
            return .failure(.increment, message: "Element does not support increment")
        }

        bagman.increment(elementAt: index)
        fingerprints.showFingerprint(at: element.activationPoint)
        return InteractionResult(success: true, method: .increment, message: nil, value: nil)
    }

    func executeDecrement(_ target: ActionTarget) -> InteractionResult {
        guard let bagman else {
            return .failure(.elementNotFound, message: "No element store available")
        }
        guard let element = bagman.findElement(for: target) else {
            return .failure(.elementNotFound, message: "Element not found")
        }

        guard let index = bagman.resolveTraversalIndex(for: target),
              bagman.hasInteractiveObject(at: index) else {
            return .failure(.decrement, message: "Element does not support decrement")
        }

        bagman.decrement(elementAt: index)
        fingerprints.showFingerprint(at: element.activationPoint)
        return InteractionResult(success: true, method: .decrement, message: nil, value: nil)
    }

    func executeCustomAction(_ target: CustomActionTarget) -> InteractionResult {
        guard let bagman else {
            return .failure(.elementNotFound, message: "No element store available")
        }
        guard bagman.findElement(for: target.elementTarget) != nil else {
            return .failure(.elementNotFound, message: "Element not found")
        }

        guard let index = bagman.resolveTraversalIndex(for: target.elementTarget),
              bagman.hasInteractiveObject(at: index) else {
            return .failure(.customAction, message: "Element does not support custom actions")
        }

        let success = bagman.performCustomAction(named: target.actionName, elementAt: index)
        return InteractionResult(
            success: success, method: .customAction,
            message: success ? nil : "Action '\(target.actionName)' not found",
            value: nil
        )
    }

    func executeEditAction(_ target: EditActionTarget) -> InteractionResult {
        guard let action = EditAction(rawValue: target.action) else {
            let valid = EditAction.allCases.map(\.rawValue).joined(separator: ", ")
            return .failure(.editAction, message: "Unknown edit action '\(target.action)'. Valid: \(valid)")
        }

        let success = performEditAction(action)
        return InteractionResult(success: success, method: .editAction, message: nil, value: nil)
    }

    func executeResignFirstResponder() -> InteractionResult {
        let success = resignFirstResponder()
        return InteractionResult(
            success: success, method: .resignFirstResponder,
            message: success ? nil : "No first responder found",
            value: nil
        )
    }

    // MARK: - Touch Gestures

    func executeTap(_ target: TouchTapTarget) -> InteractionResult {
        guard let bagman else {
            return .failure(.elementNotFound, message: "No element store available")
        }
        switch bagman.resolvePoint(from: target.elementTarget, pointX: target.pointX, pointY: target.pointY) {
        case .failure(let result):
            return result
        case .success(let point):
            // If we have an element target, try activation via live object first
            if let elementTarget = target.elementTarget,
               let index = bagman.resolveTraversalIndex(for: elementTarget),
               bagman.activate(elementAt: index) {
                fingerprints.showFingerprint(at: point)
                return InteractionResult(success: true, method: .activate, message: nil, value: nil)
            }

            // Fall back to synthetic tap
            if tap(at: point) {
                fingerprints.showFingerprint(at: point)
                return InteractionResult(success: true, method: .syntheticTap, message: nil, value: nil)
            }

            return .failure(.syntheticTap, message: "Touch tap failed")
        }
    }

    func executeLongPress(_ target: LongPressTarget) async -> InteractionResult {
        guard let bagman else {
            return .failure(.elementNotFound, message: "No element store available")
        }
        switch bagman.resolvePoint(from: target.elementTarget, pointX: target.pointX, pointY: target.pointY) {
        case .failure(let result):
            return result
        case .success(let point):
            let success = await longPress(at: point, duration: clampDuration(target.duration))
            if success { fingerprints.showFingerprint(at: point) }
            return InteractionResult(success: success, method: .syntheticLongPress, message: nil, value: nil)
        }
    }

    func executeSwipe(_ target: SwipeTarget) async -> InteractionResult {
        guard let bagman else {
            return .failure(.elementNotFound, message: "No element store available")
        }
        switch bagman.resolvePoint(from: target.elementTarget, pointX: target.startX, pointY: target.startY) {
        case .failure(let result):
            return result
        case .success(let startPoint):
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
                return .failure(.syntheticSwipe, message: "No end point or direction")
            }

            let duration = clampDuration(target.duration ?? 0.15)
            let success = await swipe(from: startPoint, to: endPoint, duration: duration)
            return InteractionResult(success: success, method: .syntheticSwipe, message: nil, value: nil)
        }
    }

    func executeDrag(_ target: DragTarget) async -> InteractionResult {
        guard let bagman else {
            return .failure(.elementNotFound, message: "No element store available")
        }
        switch bagman.resolvePoint(from: target.elementTarget, pointX: target.startX, pointY: target.startY) {
        case .failure(let result):
            return result
        case .success(let startPoint):
            let duration = clampDuration(target.duration ?? 0.5)
            let success = await drag(from: startPoint, to: target.endPoint, duration: duration)
            return InteractionResult(success: success, method: .syntheticDrag, message: nil, value: nil)
        }
    }

    func executePinch(_ target: PinchTarget) async -> InteractionResult {
        guard let bagman else {
            return .failure(.elementNotFound, message: "No element store available")
        }
        switch bagman.resolvePoint(from: target.elementTarget, pointX: target.centerX, pointY: target.centerY) {
        case .failure(let result):
            return result
        case .success(let center):
            let spread = target.spread ?? 100.0
            let duration = clampDuration(target.duration ?? 0.5)
            let success = await pinch(center: center, scale: CGFloat(target.scale), spread: CGFloat(spread), duration: duration)
            return InteractionResult(success: success, method: .syntheticPinch, message: nil, value: nil)
        }
    }

    func executeRotate(_ target: RotateTarget) async -> InteractionResult {
        guard let bagman else {
            return .failure(.elementNotFound, message: "No element store available")
        }
        switch bagman.resolvePoint(from: target.elementTarget, pointX: target.centerX, pointY: target.centerY) {
        case .failure(let result):
            return result
        case .success(let center):
            let radius = target.radius ?? 100.0
            let duration = clampDuration(target.duration ?? 0.5)
            let success = await rotate(center: center, angle: CGFloat(target.angle), radius: CGFloat(radius), duration: duration)
            return InteractionResult(success: success, method: .syntheticRotate, message: nil, value: nil)
        }
    }

    func executeTwoFingerTap(_ target: TwoFingerTapTarget) -> InteractionResult {
        guard let bagman else {
            return .failure(.elementNotFound, message: "No element store available")
        }
        switch bagman.resolvePoint(from: target.elementTarget, pointX: target.centerX, pointY: target.centerY) {
        case .failure(let result):
            return result
        case .success(let center):
            let spread = target.spread ?? 40.0
            let success = twoFingerTap(at: center, spread: CGFloat(spread))
            if success { fingerprints.showFingerprint(at: center) }
            return InteractionResult(success: success, method: .syntheticTwoFingerTap, message: nil, value: nil)
        }
    }

    func executeDrawPath(_ target: DrawPathTarget) async -> InteractionResult {
        let cgPoints = target.points.map { $0.cgPoint }

        guard cgPoints.count >= 2 else {
            return .failure(.syntheticDrawPath, message: "Path requires at least 2 points")
        }

        let duration = resolveDuration(target.duration, velocity: target.velocity, points: cgPoints)
        let success = await drawPath(points: cgPoints, duration: duration)
        return InteractionResult(success: success, method: .syntheticDrawPath, message: nil, value: nil)
    }

    func executeDrawBezier(_ target: DrawBezierTarget) async -> InteractionResult {
        guard !target.segments.isEmpty else {
            return .failure(.syntheticDrawPath, message: "Bezier path requires at least 1 segment")
        }

        let samplesPerSegment = min(target.samplesPerSegment ?? 20, 1000)
        let pathPoints = BezierSampler.sampleBezierPath(
            startPoint: target.startPoint,
            segments: target.segments,
            samplesPerSegment: samplesPerSegment
        )
        let cgPoints = pathPoints.map { $0.cgPoint }

        guard cgPoints.count >= 2 else {
            return .failure(.syntheticDrawPath, message: "Sampled bezier produced fewer than 2 points")
        }

        let duration = resolveDuration(target.duration, velocity: target.velocity, points: cgPoints)
        let success = await drawPath(points: cgPoints, duration: duration)
        return InteractionResult(success: success, method: .syntheticDrawPath, message: nil, value: nil)
    }

    // MARK: - Duration Helpers

    func clampDuration(_ value: Double?) -> Double {
        min(max(value ?? 0.5, 0.01), 60.0)
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
            result = 0.5
        }
        return clampDuration(result)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
