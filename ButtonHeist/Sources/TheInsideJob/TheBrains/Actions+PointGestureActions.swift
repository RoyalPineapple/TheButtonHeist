#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

extension Actions {

    /// Unified pipeline for gestures that target a screen point:
    /// semantic selector → actionable target (if element target) → point → gesture.
    func performPointAction(
        selection: GesturePointSelection,
        method: ActionMethod,
        action: (CGPoint) async -> Bool
    ) async -> TheSafecracker.InteractionResult {
        let elementTarget: ElementTarget?
        switch selection {
        case .element(let target):
            elementTarget = target
        case .coordinate:
            elementTarget = nil
        }
        let actionableTarget: SemanticActionability.SemanticActionableTarget?
        if let elementTarget {
            switch await navigation.actionability.makeActionable(
                for: elementTarget,
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
        switch resolveGesturePoint(from: actionableTarget, selection: selection, method: method) {
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

    // MARK: - Synthetic Gesture Dispatch

    func executeTap(_ target: TapTarget) async -> TheSafecracker.InteractionResult {
        let selection = target.gesturePointSelection()
        return await performPointAction(
            selection: selection,
            method: .syntheticTap
        ) { point in
            await self.safecracker.tap(at: point)
        }
    }

    func executeLongPress(_ target: LongPressTarget) async -> TheSafecracker.InteractionResult {
        let selection = target.gesturePointSelection()
        let duration = clampDuration(target.duration)
        return await performPointAction(
            selection: selection,
            method: .syntheticLongPress
        ) { point in
            await self.safecracker.longPress(at: point, duration: duration)
        }
    }

    func executeSwipe(_ target: SwipeTarget) async -> TheSafecracker.InteractionResult {
        let selection = target.gestureSelection()
        switch selection {
        case .unitElement(let elementTarget, let start, let end, _):
            let actionableTarget: SemanticActionability.SemanticActionableTarget
            switch await navigation.actionability.makeActionable(
                for: elementTarget,
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
                x: frame.origin.x + start.x * frame.width,
                y: frame.origin.y + start.y * frame.height
            )
            let endPoint = CGPoint(
                x: frame.origin.x + end.x * frame.width,
                y: frame.origin.y + end.y * frame.height
            )
            if let failure = geometryFailure(method: .syntheticSwipe, field: "swipe point", points: [startPoint, endPoint]) {
                return failure
            }
            let duration = clampDuration(target.resolvedDuration)
            return await performResolvedSwipe(from: startPoint, to: endPoint, duration: duration)
        case .point(let startSelection, let destination):
            let startPoint: CGPoint
            switch await resolveGesturePoint(selection: startSelection, method: .syntheticSwipe) {
            case .failure(let result):
                return result
            case .success(let point):
                startPoint = point
            }
            let endPoint: CGPoint
            switch destination {
            case .coordinate(let point):
                endPoint = point.cgPoint
            case .direction(let direction):
                let dist = Self.defaultSwipeDistance
                switch direction {
                case .up:    endPoint = CGPoint(x: startPoint.x, y: startPoint.y - dist)
                case .down:  endPoint = CGPoint(x: startPoint.x, y: startPoint.y + dist)
                case .left:  endPoint = CGPoint(x: startPoint.x - dist, y: startPoint.y)
                case .right: endPoint = CGPoint(x: startPoint.x + dist, y: startPoint.y)
                }
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

    func executeDrag(_ target: DragTarget) async -> TheSafecracker.InteractionResult {
        let selection = target.startSelection()
        let endPoint = target.end.cgPoint
        if let failure = geometryFailure(method: .syntheticDrag, field: "endPoint", point: endPoint) {
            return failure
        }
        let duration = clampDuration(target.resolvedDuration)
        return await performPointAction(
            selection: selection,
            method: .syntheticDrag
        ) { startPoint in
            await self.safecracker.drag(from: startPoint, to: endPoint, duration: duration)
        }
    }

    func executePinch(_ target: PinchTarget) async -> TheSafecracker.InteractionResult {
        let selection = target.centerSelection()
        let spread = target.resolvedSpread
        let duration = clampDuration(target.resolvedDuration)
        return await performPointAction(
            selection: selection,
            method: .syntheticPinch
        ) { center in
            await self.safecracker.pinch(
                center: center, scale: CGFloat(target.scale),
                spread: CGFloat(spread), duration: duration
            )
        }
    }

    func executeRotate(_ target: RotateTarget) async -> TheSafecracker.InteractionResult {
        let selection = target.centerSelection()
        let radius = target.resolvedRadius
        let duration = clampDuration(target.resolvedDuration)
        return await performPointAction(
            selection: selection,
            method: .syntheticRotate
        ) { center in
            await self.safecracker.rotate(
                center: center, angle: CGFloat(target.angle),
                radius: CGFloat(radius), duration: duration
            )
        }
    }

    func executeTwoFingerTap(_ target: TwoFingerTapTarget) async -> TheSafecracker.InteractionResult {
        let selection = target.centerSelection()
        let spread = target.resolvedSpread
        return await performPointAction(
            selection: selection,
            method: .syntheticTwoFingerTap
        ) { center in
            await self.safecracker.twoFingerTap(at: center, spread: CGFloat(spread))
        }
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
