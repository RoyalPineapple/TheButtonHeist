#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

extension Actions {

    func resolveGesturePoint(
        selection: GesturePointSelection,
        method: ActionMethod
    ) async -> PointResolution {
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
    ) -> PointResolution {
        switch selection {
        case .element:
            guard let actionableTarget else {
                return .failure(.failure(.elementNotFound, message: "No target specified"))
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

    enum GestureFrameResolution {
        case success(CGRect)
        case failure(TheSafecracker.InteractionResult)
    }

    func resolveGestureFrame(
        for actionableTarget: SemanticActionability.SemanticActionableTarget,
        method: ActionMethod
    ) -> GestureFrameResolution {
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

    // MARK: - Duration Helpers

    private static let defaultGestureDuration: Double = 0.5
    private static let minGestureDuration: Double = 0.01
    private static let maxGestureDuration: Double = 60.0

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

    func clampDuration(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return Self.defaultGestureDuration }
        return min(max(value, Self.minGestureDuration), Self.maxGestureDuration)
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
