#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore
import ThePlans

extension Actions {

    /// Unified pipeline for gestures that target a screen point:
    /// semantic selector → inflated target (if element target) → point → gesture.
    func performPointAction(
        selection: GesturePointSelection,
        method: ActionMethod,
        action: (CGPoint) async -> Bool
    ) async -> TheSafecracker.InteractionResult {
        switch await resolveGesturePoint(selection: selection, method: method) {
        case .failure(let result):
            return result
        case .success(let resolvedPoint):
            let success = await action(resolvedPoint.point)
            return gestureDispatchResult(
                method: method,
                diagnosticPoint: resolvedPoint.point,
                success: success
            ).withSubjectEvidence(resolvedPoint.subjectEvidence)
        }
    }

    // MARK: - Synthetic Gesture Dispatch

    func executeTap(_ target: TapTarget) async -> TheSafecracker.InteractionResult {
        return await performPointAction(
            selection: target.selection,
            method: .syntheticTap
        ) { point in
            await self.safecracker.tap(at: point)
        }
    }

    func executeLongPress(_ target: LongPressTarget) async -> TheSafecracker.InteractionResult {
        return await performPointAction(
            selection: target.selection,
            method: .syntheticLongPress
        ) { point in
            await self.safecracker.longPress(at: point, duration: target.duration)
        }
    }

    func executeSwipe(_ target: SwipeTarget) async -> TheSafecracker.InteractionResult {
        switch target.selection {
        case .unitElement(let elementTarget, let start, let end):
            return await performElementFrameSwipe(
                elementTarget: elementTarget,
                start: start,
                end: end,
                duration: target.resolvedDuration
            )
        case .elementDirection(let elementTarget, let direction):
            return await performElementFrameSwipe(
                elementTarget: elementTarget,
                start: direction.defaultStart,
                end: direction.defaultEnd,
                duration: target.resolvedDuration
            )
        case .point(let startSelection, let destination):
            let startPoint: CGPoint
            switch await resolveGesturePoint(selection: startSelection, method: .syntheticSwipe) {
            case .failure(let result):
                return result
            case .success(let resolvedPoint):
                startPoint = resolvedPoint.point
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
                return await performResolvedSwipe(
                    from: startPoint,
                    to: endPoint,
                    duration: target.resolvedDuration
                ).withSubjectEvidence(resolvedPoint.subjectEvidence)
            }
        }
    }

    private func performElementFrameSwipe(
        elementTarget: ElementTarget,
        start: UnitPoint,
        end: UnitPoint,
        duration: GestureDuration
    ) async -> TheSafecracker.InteractionResult {
        let inflatedTarget: ElementInflation.InflatedElementTarget
        switch await navigation.elementInflation.inflate(
            for: elementTarget,
            method: .syntheticSwipe,
            deallocatedBoundary: "gesture action"
        ) {
        case .inflated(let target):
            inflatedTarget = target
        case .failed(let failure):
            return failure.interactionResult(commandMethod: .syntheticSwipe)
        }
        let frame: CGRect
        switch resolveGestureFrame(for: inflatedTarget, method: .syntheticSwipe) {
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
        return await performResolvedSwipe(from: startPoint, to: endPoint, duration: duration)
            .withSubjectEvidence(inflatedTarget.subjectEvidence(source: .elementGestureTarget))
    }

    private func performResolvedSwipe(
        from startPoint: CGPoint,
        to endPoint: CGPoint,
        duration: GestureDuration
    ) async -> TheSafecracker.InteractionResult {
        let success = await safecracker.swipe(from: startPoint, to: endPoint, duration: duration)
        return gestureDispatchResult(method: .syntheticSwipe, diagnosticPoint: startPoint, success: success)
    }

    func executeDrag(_ target: DragTarget) async -> TheSafecracker.InteractionResult {
        let selection: GesturePointSelection
        let end: ScreenPoint
        switch target.selection {
        case .elementToPoint(let target, let endPoint):
            selection = .element(target)
            end = endPoint
        case .pointToPoint(let startPoint, let endPoint):
            selection = .coordinate(startPoint)
            end = endPoint
        }
        let endPoint = end.cgPoint
        if let failure = geometryFailure(method: .syntheticDrag, field: "endPoint", point: endPoint) {
            return failure
        }
        return await performPointAction(
            selection: selection,
            method: .syntheticDrag
        ) { startPoint in
            await self.safecracker.drag(from: startPoint, to: endPoint, duration: target.resolvedDuration)
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
