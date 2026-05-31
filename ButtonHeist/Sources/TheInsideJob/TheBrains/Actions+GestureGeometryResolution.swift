#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

extension Actions {

    enum GestureResolution<Value> {
        case success(Value)
        case failure(TheSafecracker.InteractionResult)
    }

    func resolveGesturePoint(
        selection: GesturePointSelection,
        method: ActionMethod
    ) async -> GestureResolution<CGPoint> {
        let actionableTarget: SemanticActionability.SemanticActionableTarget?
        switch selection {
        case .element(let target):
            switch await navigation.actionability.makeActionable(
                for: target,
                method: method,
                deallocatedBoundary: "gesture action"
            ) {
            case .actionable(let target):
                actionableTarget = target
            case .failed(let failure):
                return .failure(failure.interactionResult(commandMethod: method))
            }
        case .coordinate:
            actionableTarget = nil
        }
        return resolveGesturePoint(from: actionableTarget, selection: selection, method: method)
    }

    func resolveGesturePoint(
        from actionableTarget: SemanticActionability.SemanticActionableTarget?,
        selection: GesturePointSelection,
        method: ActionMethod
    ) -> GestureResolution<CGPoint> {
        switch selection {
        case .element:
            guard let actionableTarget else {
                return .failure(.failure(method, message: "No target specified", failureKind: .targetUnavailable))
            }
            let point = actionableTarget.liveTarget.activationPoint
            if let failure = geometryFailure(method: method, field: "point", point: point) {
                return .failure(failure)
            }
            return .success(point)
        case .coordinate(let screenPoint):
            let point = screenPoint.cgPoint
            if let failure = geometryFailure(method: method, field: "point", point: point) {
                return .failure(failure)
            }
            return .success(point)
        }
    }

    func resolveGestureFrame(
        for actionableTarget: SemanticActionability.SemanticActionableTarget,
        method: ActionMethod
    ) -> GestureResolution<CGRect> {
        let frame = actionableTarget.liveTarget.frame
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
