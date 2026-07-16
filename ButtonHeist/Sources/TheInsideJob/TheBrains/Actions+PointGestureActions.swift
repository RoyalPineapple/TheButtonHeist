#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore
import ThePlans

extension Actions {

    func performPointAction<PreparedDispatch: Sendable>(
        selection: ResolvedGesturePointSelection,
        method: ActionMethod,
        prepare: (CGPoint) -> PreparedDispatch?,
        complete: (PreparedDispatch) async -> Bool
    ) async -> TheSafecracker.ActionDispatchOutcome {
        switch await resolveGesturePoint(selection: selection, method: method) {
        case .failure(let result):
            return result
        case .success(let resolvedPoint):
            switch prepareGestureDispatch(
                for: resolvedPoint,
                method: method,
                prepare: { .success(prepare($0)) }
            ) {
            case .failure(let result):
                return result
            case .success(let prepared):
                return await completePreparedGesture(
                    prepared,
                    method: method,
                    subjectEvidence: resolvedPoint.subjectEvidence,
                    complete: complete
                )
            }
        }
    }

    func executeTap(
        _ target: ResolvedTapTarget,
    ) async -> TheSafecracker.ActionDispatchOutcome {
        return await performPointAction(
            selection: target.selection,
            method: .syntheticTap,
            prepare: safecracker.prepareTap,
            complete: safecracker.completePreparedTouch
        )
    }

    func executeLongPress(
        _ target: ResolvedLongPressTarget,
    ) async -> TheSafecracker.ActionDispatchOutcome {
        return await performPointAction(
            selection: target.selection,
            method: .syntheticLongPress,
            prepare: { point in
                self.safecracker.prepareLongPress(at: point, duration: target.duration)
            },
            complete: safecracker.completePreparedTouch
        )
    }

    func executeSwipe(
        _ request: ResolvedSwipeTarget,
    ) async -> TheSafecracker.ActionDispatchOutcome {
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
        case .point(let startSelection, let destination):
            switch await resolveGesturePoint(
                selection: startSelection,
                method: .syntheticSwipe,
            ) {
            case .failure(let result):
                return result
            case .success(let resolvedPoint):
                switch prepareGestureDispatch(
                    for: resolvedPoint,
                    method: .syntheticSwipe,
                    prepare: { startPoint -> GestureResolution<TheSafecracker.PreparedTouchDispatch?> in
                        let endPoint = self.swipeEndPoint(from: startPoint, destination: destination)
                        if let failure = self.geometryFailure(
                            method: .syntheticSwipe,
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
                        method: .syntheticSwipe,
                        subjectEvidence: resolvedPoint.subjectEvidence,
                        complete: safecracker.completePreparedTouch
                    )
                }
            }
        }
    }

    private func performElementFrameSwipe(
        target: ResolvedAccessibilityTarget,
        start: UnitPoint,
        end: UnitPoint,
        duration: GestureDuration,
    ) async -> TheSafecracker.ActionDispatchOutcome {
        let inflatedTarget: ElementInflation.InflatedElementTarget
        switch await navigation.elementInflation.inflate(
            for: target,
            method: .syntheticSwipe,
        ) {
        case .inflated(let target):
            inflatedTarget = target
        case .failed(let failure):
            return failure.actionDispatchOutcome(commandMethod: .syntheticSwipe)
        }
        let preparation = stash.dispatchOnFreshLiveActionTarget(
            inflatedTarget.liveTarget,
        ) { liveTarget in
            let frame = liveTarget.frame
            if let message = GeometryValidation.validateRect(frame, field: "frame") {
                return GestureResolution<
                    PreparedGestureDispatch<TheSafecracker.PreparedTouchDispatch>
                >.failure(.failure(
                        .syntheticSwipe,
                        message: "syntheticSwipe failed: \(message)",
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
                method: .syntheticSwipe,
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
            return staleLiveTargetFailure(staleness, method: .syntheticSwipe)
        case .success(.failure(let result)):
            return result
        case .success(.success(let prepared)):
            return await completePreparedGesture(
                prepared,
                method: .syntheticSwipe,
                subjectEvidence: inflatedTarget.subjectEvidence(source: .elementGestureTarget),
                complete: safecracker.completePreparedTouch
            )
        }
    }

    func executeDrag(
        _ target: ResolvedDragTarget,
    ) async -> TheSafecracker.ActionDispatchOutcome {
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
        if let failure = geometryFailure(method: .syntheticDrag, field: "endPoint", point: endPoint) {
            return failure
        }
        return await performPointAction(
            selection: selection,
            method: .syntheticDrag,
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
        method: ActionMethod,
        subjectEvidence: ActionSubjectEvidence?,
        complete: (PreparedDispatch) async -> Bool
    ) async -> TheSafecracker.ActionDispatchOutcome {
        let success = if let dispatch = prepared.dispatch {
            await complete(dispatch)
        } else {
            false
        }
        return gestureDispatchResult(
            method: method,
            diagnosticPoint: prepared.point,
            success: success
        ).withSubjectEvidence(subjectEvidence)
    }

    private func swipeEndPoint(
        from startPoint: CGPoint,
        destination: SwipeDestinationSelection
    ) -> CGPoint {
        switch destination {
        case .coordinate(let point):
            return point.cgPoint
        case .direction(let direction):
            let distance = Self.defaultSwipeDistance
            switch direction {
            case .up: return CGPoint(x: startPoint.x, y: startPoint.y - distance)
            case .down: return CGPoint(x: startPoint.x, y: startPoint.y + distance)
            case .left: return CGPoint(x: startPoint.x - distance, y: startPoint.y)
            case .right: return CGPoint(x: startPoint.x + distance, y: startPoint.y)
            }
        }
    }

    private func gestureDispatchResult(
        method: ActionMethod,
        diagnosticPoint: CGPoint,
        success: Bool
    ) -> TheSafecracker.ActionDispatchOutcome {
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
