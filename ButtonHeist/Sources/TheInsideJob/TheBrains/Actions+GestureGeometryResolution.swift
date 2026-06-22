#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore
import ThePlans

extension Actions {

    enum GestureResolution<Value> {
        case success(Value)
        case failure(TheSafecracker.InteractionResult)
    }

    struct ResolvedGesturePoint {
        let point: CGPoint
        let subjectEvidence: ActionSubjectEvidence?
    }

    func resolveGesturePoint(
        selection: GesturePointSelection,
        method: ActionMethod
    ) async -> GestureResolution<ResolvedGesturePoint> {
        let inflatedTarget: ElementInflation.InflatedElementTarget?
        switch selection {
        case .element(let target):
            switch await navigation.elementInflation.inflate(
                for: target,
                method: method,
                deallocatedBoundary: "gesture action"
            ) {
            case .inflated(let target):
                inflatedTarget = target
            case .failed(let failure):
                return .failure(failure.interactionResult(commandMethod: method))
            }
        case .coordinate:
            inflatedTarget = nil
        }
        return resolveGesturePoint(from: inflatedTarget, selection: selection, method: method)
    }

    func resolveGesturePoint(
        from inflatedTarget: ElementInflation.InflatedElementTarget?,
        selection: GesturePointSelection,
        method: ActionMethod
    ) -> GestureResolution<ResolvedGesturePoint> {
        switch selection {
        case .element:
            guard let inflatedTarget else {
                return .failure(.failure(method, message: "No target specified", failureKind: .targetUnavailable))
            }
            let point = inflatedTarget.liveTarget.activationPoint
            if let failure = geometryFailure(method: method, field: "point", point: point) {
                return .failure(failure)
            }
            return .success(ResolvedGesturePoint(
                point: point,
                subjectEvidence: inflatedTarget.subjectEvidence(source: .elementGestureTarget)
            ))
        case .coordinate(let screenPoint):
            let point = screenPoint.cgPoint
            if let failure = geometryFailure(method: method, field: "point", point: point) {
                return .failure(failure)
            }
            return .success(ResolvedGesturePoint(point: point, subjectEvidence: nil))
        }
    }

    func resolveGestureFrame(
        for inflatedTarget: ElementInflation.InflatedElementTarget,
        method: ActionMethod
    ) -> GestureResolution<CGRect> {
        let frame = inflatedTarget.liveTarget.frame
        if let message = GeometryValidation.validateRect(frame, field: "frame") {
            return .failure(.failure(
                method,
                message: "\(method.rawValue) failed: \(message)",
                failureKind: .inputValidation
            ))
        }
        return .success(frame)
    }

    func geometryFailure(
        method: ActionMethod,
        field: String,
        point: CGPoint
    ) -> TheSafecracker.InteractionResult? {
        guard let message = GeometryValidation.validateScreenPoint(point, field: field) else { return nil }
        return .failure(
            method,
            message: "\(method.rawValue) failed: \(message)",
            failureKind: .inputValidation
        )
    }

    func geometryFailure(
        method: ActionMethod,
        field: String,
        points: [CGPoint]
    ) -> TheSafecracker.InteractionResult? {
        guard let message = GeometryValidation.validateScreenPoints(points, field: field) else { return nil }
        return .failure(
            method,
            message: "\(method.rawValue) failed: \(message)",
            failureKind: .inputValidation
        )
    }

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

}

#endif // DEBUG
#endif // canImport(UIKit)
