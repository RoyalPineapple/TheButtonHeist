#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore
import ThePlans

extension Actions {

    func performPointAction<PreparedDispatch: Sendable>(
        selection: ResolvedGesturePointSelection,
        payload: ActionResult.Payload,
        prepare: (CGPoint) -> PreparedDispatch?,
        complete: (PreparedDispatch) async -> Bool
    ) async -> TheSafecracker.ActionDispatchResult {
        switch await resolveGesturePoint(selection: selection, payload: payload) {
        case .failure(let result):
            return result
        case .success(let resolvedPoint):
            switch prepareGestureDispatch(
                for: resolvedPoint,
                payload: payload,
                prepare: { .success(prepare($0)) }
            ) {
            case .failure(let result):
                return result
            case .success(let prepared):
                return await completePreparedGesture(
                    prepared,
                    payload: payload,
                    subjectEvidence: resolvedPoint.subjectEvidence,
                    complete: complete
                )
            }
        }
    }

    func executeTap(
        _ target: ResolvedTapTarget,
    ) async -> TheSafecracker.ActionDispatchResult {
        return await performPointAction(
            selection: target.selection,
            payload: .oneFingerTap,
            prepare: safecracker.prepareTap,
            complete: safecracker.completePreparedTouch
        )
    }

    func executeLongPress(
        _ target: ResolvedLongPressTarget,
    ) async -> TheSafecracker.ActionDispatchResult {
        return await performPointAction(
            selection: target.selection,
            payload: .longPress,
            prepare: { point in
                self.safecracker.prepareLongPress(at: point, duration: target.duration)
            },
            complete: safecracker.completePreparedTouch
        )
    }

    func executeSwipe(
        _ request: ResolvedSwipeTarget,
    ) async -> TheSafecracker.ActionDispatchResult {
        let duration = request.duration ?? SwipeTarget.defaultDuration
        switch request.selection {
        case .unitElement(let target, let start, let end):
            return await performElementFrameSwipe(
                target: target,
                start: start,
                end: end,
                duration: duration,
            )
        case .elementDirection(let target, let direction):
            return await performElementFrameSwipe(
                target: target,
                start: direction.defaultStart,
                end: direction.defaultEnd,
                duration: duration,
            )
        case .pointToPoint(let start, let end):
            return await performPointSwipe(start: start, duration: duration) { _ in end.cgPoint }
        case .pointDirection(let start, let direction):
            return await performPointSwipe(start: start, duration: duration) { startPoint in
                self.swipeEndPoint(from: startPoint, direction: direction)
            }
        }
    }

    private func performPointSwipe(
        start: ScreenPoint,
        duration: GestureDuration,
        resolveEndPoint: (CGPoint) -> CGPoint
    ) async -> TheSafecracker.ActionDispatchResult {
        switch resolveGesturePoint(
            from: nil,
            selection: .coordinate(start),
            payload: .swipe
        ) {
        case .failure(let result):
            return result
        case .success(let resolvedPoint):
            switch prepareGestureDispatch(
                for: resolvedPoint,
                payload: .swipe,
                prepare: { startPoint -> GestureResolution<TheSafecracker.PreparedTouchDispatch?> in
                    let endPoint = resolveEndPoint(startPoint)
                    if let failure = self.geometryFailure(
                        payload: .swipe,
                        field: "swipe point",
                        points: [startPoint, endPoint]
                    ) {
                        return .failure(failure)
                    }
                    return .success(self.safecracker.prepareSwipe(
                        from: startPoint,
                        to: endPoint,
                        duration: duration
                    ))
                }
            ) {
            case .failure(let result):
                return result
            case .success(let prepared):
                return await completePreparedGesture(
                    prepared,
                    payload: .swipe,
                    subjectEvidence: resolvedPoint.subjectEvidence,
                    complete: safecracker.completePreparedTouch
                )
            }
        }
    }

    private func performElementFrameSwipe(
        target: ResolvedAccessibilityTarget,
        start: UnitPoint,
        end: UnitPoint,
        duration: GestureDuration,
    ) async -> TheSafecracker.ActionDispatchResult {
        let inflatedTarget: ElementInflation.InflatedElementTarget
        switch await navigation.elementInflation.inflate(
            for: target,
            method: .swipe,
        ) {
        case .inflated(let target):
            inflatedTarget = target
        case .failed(let failure):
            return failure.actionDispatchResult(payload: .swipe)
        }
        let preparation = vault.dispatchOnFreshLiveActionTarget(
            inflatedTarget.liveTarget,
        ) { liveTarget in
            let frame = liveTarget.frame
            if let message = GeometryValidation.validateRect(frame, field: "frame") {
                return GestureResolution<
                    PreparedGestureDispatch<TheSafecracker.PreparedTouchDispatch>
                >.failure(.failure(
                        .swipe,
                        message: "swipe failed: \(message)",
                        failureKind: .inputValidation
                    ))
            }
            let startPoint = CGPoint(
                x: frame.origin.x + start.x * frame.width,
                y: frame.origin.y + start.y * frame.height
            )
            let endPoint = CGPoint(
                x: frame.origin.x + end.x * frame.width,
                y: frame.origin.y + end.y * frame.height
            )
            if let failure = self.geometryFailure(
                payload: .swipe,
                field: "swipe point",
                points: [startPoint, endPoint]
            ) {
                return .failure(failure)
            }
            return .success(PreparedGestureDispatch(
                point: startPoint,
                dispatch: self.safecracker.prepareSwipe(
                    from: startPoint,
                    to: endPoint,
                    duration: duration
                )
            ))
        }
        switch preparation {
        case .failure(let staleness):
            return staleLiveTargetFailure(staleness, payload: .swipe)
        case .success(.failure(let result)):
            return result
        case .success(.success(let prepared)):
            return await completePreparedGesture(
                prepared,
                payload: .swipe,
                subjectEvidence: inflatedTarget.subjectEvidence(source: .elementGestureTarget),
                complete: safecracker.completePreparedTouch
            )
        }
    }

    func executeDrag(
        _ target: ResolvedDragTarget,
    ) async -> TheSafecracker.ActionDispatchResult {
        let selection: ResolvedGesturePointSelection
        let end: ScreenPoint
        switch target.selection {
        case .elementToPoint(let target, let start, let endPoint):
            if let start {
                selection = .elementUnitPoint(target, start)
            } else {
                selection = .element(target)
            }
            end = endPoint
        case .pointToPoint(let startPoint, let endPoint):
            selection = .coordinate(startPoint)
            end = endPoint
        }
        let endPoint = end.cgPoint
        if let failure = geometryFailure(payload: .drag, field: "endPoint", point: endPoint) {
            return failure
        }
        return await performPointAction(
            selection: selection,
            payload: .drag,
            prepare: { startPoint in
                self.safecracker.prepareDrag(
                    from: startPoint,
                    to: endPoint,
                    duration: target.duration ?? DragTarget.defaultDuration
                )
            },
            complete: safecracker.completePreparedTouch
        )
    }

    private func completePreparedGesture<PreparedDispatch: Sendable>(
        _ prepared: PreparedGestureDispatch<PreparedDispatch>,
        payload: ActionResult.Payload,
        subjectEvidence: ActionSubjectEvidence?,
        complete: (PreparedDispatch) async -> Bool
    ) async -> TheSafecracker.ActionDispatchResult {
        let success = if let dispatch = prepared.dispatch {
            await complete(dispatch)
        } else {
            false
        }
        return gestureDispatchResult(
            payload: payload,
            diagnosticPoint: prepared.point,
            success: success
        ).withSubjectEvidence(subjectEvidence)
    }

    private func swipeEndPoint(
        from startPoint: CGPoint,
        direction: SwipeDirection
    ) -> CGPoint {
        let distance = Self.defaultSwipeDistance
        switch direction {
        case .up: return CGPoint(x: startPoint.x, y: startPoint.y - distance)
        case .down: return CGPoint(x: startPoint.x, y: startPoint.y + distance)
        case .left: return CGPoint(x: startPoint.x - distance, y: startPoint.y)
        case .right: return CGPoint(x: startPoint.x + distance, y: startPoint.y)
        }
    }

    private func gestureDispatchResult(
        payload: ActionResult.Payload,
        diagnosticPoint: CGPoint,
        success: Bool
    ) -> TheSafecracker.ActionDispatchResult {
        guard !success else {
            return .success(payload: payload)
        }
        return .failure(
            payload,
            message: ActionCapabilityDiagnostic.gestureDispatchFailed(
                method: payload.method,
                point: diagnosticPoint,
                receiver: safecracker.tapReceiverDiagnostic(at: diagnosticPoint)
            )
        )
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
