#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore
import ThePlans

extension Actions {

    enum GestureResolution<Value> {
        case success(Value)
        case failure(TheSafecracker.ActionDispatchResult)
    }

    enum GesturePointSource {
        case liveTarget(TheVault.LiveActionTarget, unitPoint: UnitPoint?)
        case coordinate(CGPoint)
    }

    struct ResolvedGesturePoint {
        let source: GesturePointSource
        let subjectEvidence: ActionSubjectEvidence?
    }

    struct PreparedGestureDispatch<PreparedDispatch: Sendable>: Sendable {
        let point: CGPoint
        let dispatch: PreparedDispatch?
    }

    func resolveGesturePoint(
        selection: ResolvedGesturePointSelection,
        payload: ActionResult.Payload,
    ) async -> GestureResolution<ResolvedGesturePoint> {
        let inflatedTarget: ElementInflation.InflatedElementTarget?
        switch selection {
        case .element(let target), .elementUnitPoint(let target, _):
            switch await navigation.elementInflation.inflate(
                for: target,
                method: payload.method,
            ) {
            case .inflated(let target):
                inflatedTarget = target
            case .failed(let failure):
                return .failure(failure.actionDispatchResult(payload: payload))
            }
        case .coordinate:
            inflatedTarget = nil
        }
        return resolveGesturePoint(from: inflatedTarget, selection: selection, payload: payload)
    }

    func resolveGesturePoint(
        from inflatedTarget: ElementInflation.InflatedElementTarget?,
        selection: ResolvedGesturePointSelection,
        payload: ActionResult.Payload
    ) -> GestureResolution<ResolvedGesturePoint> {
        switch selection {
        case .element:
            guard let inflatedTarget else {
                return .failure(.failure(
                    payload,
                    message: "No target specified",
                    failureKind: .targetUnavailable
                ))
            }
            return .success(ResolvedGesturePoint(
                source: .liveTarget(inflatedTarget.liveTarget, unitPoint: nil),
                subjectEvidence: inflatedTarget.subjectEvidence(source: .elementGestureTarget)
            ))
        case .elementUnitPoint(_, let unitPoint):
            guard let inflatedTarget else {
                return .failure(.failure(
                    payload,
                    message: "No target specified",
                    failureKind: .targetUnavailable
                ))
            }
            return .success(ResolvedGesturePoint(
                source: .liveTarget(inflatedTarget.liveTarget, unitPoint: unitPoint),
                subjectEvidence: inflatedTarget.subjectEvidence(source: .elementGestureTarget)
            ))
        case .coordinate(let screenPoint):
            return .success(ResolvedGesturePoint(
                source: .coordinate(screenPoint.cgPoint),
                subjectEvidence: nil
            ))
        }
    }

    func prepareGestureDispatch<PreparedDispatch: Sendable>(
        for resolvedPoint: ResolvedGesturePoint,
        payload: ActionResult.Payload,
        prepare: (CGPoint) -> GestureResolution<PreparedDispatch?>
    ) -> GestureResolution<PreparedGestureDispatch<PreparedDispatch>> {
        switch resolvedPoint.source {
        case .coordinate(let point):
            return prepareGestureDispatch(at: point, payload: payload, prepare: prepare)
        case .liveTarget(let liveTarget, let unitPoint):
            switch vault.dispatchOnFreshLiveActionTarget(
                liveTarget,
                operation: { currentTarget
                -> GestureResolution<PreparedGestureDispatch<PreparedDispatch>> in
                let point: CGPoint
                if let unitPoint {
                    let frame = currentTarget.frame
                    if let message = GeometryValidation.validateRect(frame, field: "frame") {
                        return .failure(.failure(
                            payload,
                            message: "\(payload.method.rawValue) failed: \(message)",
                            failureKind: .inputValidation
                        ))
                    }
                    point = CGPoint(
                        x: frame.origin.x + unitPoint.x * frame.width,
                        y: frame.origin.y + unitPoint.y * frame.height
                    )
                } else {
                    point = currentTarget.activationPoint
                }
                return prepareGestureDispatch(at: point, payload: payload, prepare: prepare)
                }
            ) {
            case .success(let resolution):
                return resolution
            case .failure(let staleness):
                return .failure(staleLiveTargetFailure(staleness, payload: payload))
            }
        }
    }

    private func prepareGestureDispatch<PreparedDispatch: Sendable>(
        at point: CGPoint,
        payload: ActionResult.Payload,
        prepare: (CGPoint) -> GestureResolution<PreparedDispatch?>
    ) -> GestureResolution<PreparedGestureDispatch<PreparedDispatch>> {
        if let failure = geometryFailure(payload: payload, field: "point", point: point) {
            return .failure(failure)
        }
        switch prepare(point) {
        case .success(let dispatch):
            return .success(PreparedGestureDispatch(point: point, dispatch: dispatch))
        case .failure(let failure):
            return .failure(failure)
        }
    }

    func geometryFailure(
        payload: ActionResult.Payload,
        field: String,
        point: CGPoint
    ) -> TheSafecracker.ActionDispatchResult? {
        guard let message = GeometryValidation.validateScreenPoint(point, field: field) else { return nil }
        return .failure(
            payload,
            message: "\(payload.method.rawValue) failed: \(message)",
            failureKind: .inputValidation
        )
    }

    func geometryFailure(
        payload: ActionResult.Payload,
        field: String,
        points: [CGPoint]
    ) -> TheSafecracker.ActionDispatchResult? {
        guard let message = GeometryValidation.validateScreenPoints(points, field: field) else { return nil }
        return .failure(
            payload,
            message: "\(payload.method.rawValue) failed: \(message)",
            failureKind: .inputValidation
        )
    }

    static let defaultSwipeDistance: CGFloat = 200

}

#endif // DEBUG
#endif // canImport(UIKit)
