#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

extension Actions {

    func resolveGesturePoint(
        from actionableTarget: Navigation.SemanticActionableTarget?,
        pointX: Double?,
        pointY: Double?,
        method: ActionMethod
    ) -> PointResolution {
        guard let actionableTarget else {
            guard let xCoord = pointX, let yCoord = pointY else {
                return .failure(.failure(.elementNotFound, message: "No target specified"))
            }
            let point = CGPoint(x: xCoord, y: yCoord)
            if let failure = geometryFailure(method: method, field: "point", point: point) {
                return .failure(failure)
            }
            return .success(point)
        }
        let point = actionableTarget.liveTarget.activationPoint
        if let failure = geometryFailure(method: method, field: "activationPoint", point: point) {
            return .failure(failure)
        }
        return .success(point)
    }

    func resolveGesturePoint(
        from normalizedTarget: TheStash.NormalizedTarget?,
        pointX: Double?,
        pointY: Double?,
        method: ActionMethod
    ) -> PointResolution {
        guard let normalizedTarget else {
            guard let xCoord = pointX, let yCoord = pointY else {
                return .failure(.failure(.elementNotFound, message: "No target specified"))
            }
            let point = CGPoint(x: xCoord, y: yCoord)
            if let failure = geometryFailure(method: method, field: "point", point: point) {
                return .failure(failure)
            }
            return .success(point)
        }
        let resolution = stash.resolveTarget(normalizedTarget.executableTarget)
        guard let resolved = resolution.resolved else {
            return .failure(.failure(.elementNotFound, message: normalizedTarget.diagnostics(resolution.diagnostics)))
        }
        guard case .resolved(let liveTarget) = stash.resolveLiveActionTarget(for: resolved) else {
            return .failure(.failure(
                method,
                message: normalizedTarget.diagnostics(
                    ActionCapabilityDiagnostic.gestureTargetUnavailable(
                        method: method,
                        element: resolved.screenElement,
                        isVisible: stash.visibleIds.contains(resolved.screenElement.heistId)
                    )
                )
            ))
        }
        let point = liveTarget.activationPoint
        if let failure = geometryFailure(method: method, field: "activationPoint", point: point) {
            return .failure(failure)
        }
        return .success(point)
    }

    enum GestureFrameResolution {
        case success(CGRect)
        case failure(TheSafecracker.InteractionResult)
    }

    func resolveGestureFrame(
        for actionableTarget: Navigation.SemanticActionableTarget,
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

    func resolveGestureFrame(
        for normalizedTarget: TheStash.NormalizedTarget,
        method: ActionMethod
    ) -> GestureFrameResolution {
        let resolution = stash.resolveTarget(normalizedTarget.executableTarget)
        guard let resolved = resolution.resolved else {
            return .failure(.failure(.elementNotFound, message: normalizedTarget.diagnostics(resolution.diagnostics)))
        }
        guard case .resolved(let liveTarget) = stash.resolveLiveActionTarget(for: resolved) else {
            return .failure(.failure(
                method,
                message: normalizedTarget.diagnostics(
                    ActionCapabilityDiagnostic.gestureTargetUnavailable(
                        method: method,
                        element: resolved.screenElement,
                        isVisible: stash.visibleIds.contains(resolved.screenElement.heistId)
                    )
                )
            ))
        }
        let frame = liveTarget.frame
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

    func resolveDuration(_ duration: Double?, velocity: Double?, points: [CGPoint]) -> TimeInterval {
        let result: Double
        if let resolvedDuration = duration, resolvedDuration.isFinite, resolvedDuration > 0 {
            result = resolvedDuration
        } else if let velocity = velocity, velocity.isFinite, velocity > 0 {
            let totalLength = zip(points, points.dropFirst()).reduce(0.0) { runningTotal, pair in
                runningTotal + hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y)
            }
            result = totalLength / velocity
        } else {
            result = Self.defaultGestureDuration
        }
        return clampDuration(result)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
