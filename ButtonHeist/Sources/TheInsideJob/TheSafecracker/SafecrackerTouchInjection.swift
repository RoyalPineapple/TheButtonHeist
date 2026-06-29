#if canImport(UIKit)
#if DEBUG
import UIKit
import TheScore
import ThePlans

@MainActor
final class SafecrackerTouchInjection {

    private let fingerprints: TheFingerprints

    init(fingerprints: TheFingerprints) {
        self.fingerprints = fingerprints
    }

    /// Simulate a tap at the given screen coordinates.
    /// Yields to the main run loop between began and ended phases so that
    /// SwiftUI gesture recognizers (which process events asynchronously)
    /// have a chance to transition from "possible" to "recognized".
    func tap(at point: CGPoint) async -> Bool {
        guard Self.geometryIsValid([point], field: "tap point") else { return false }
        return await performTouchTap(at: point)
    }

    /// Simulate a long press at the given screen coordinates.
    /// Sends `.stationary` phase events every 10ms during the hold (matching KIF)
    /// so gesture recognizers stay alive and processing.
    func longPress(at point: CGPoint, duration: GestureDuration = .longPressDefault) async -> Bool {
        guard Self.geometryIsValid([point], field: "long press point") else { return false }
        guard var touchState = beginTouch(at: point) else { return false }

        var elapsed: TimeInterval = 0
        while elapsed < duration.seconds && !Task.isCancelled {
            guard await Task.cancellableSleep(
                nanoseconds: UInt64(TheSafecracker.touchGestureStepDelay * 1_000_000_000)
            ) else { break }
            elapsed += TheSafecracker.touchGestureStepDelay
            sendStationary(&touchState.touch)
        }

        return endTouch(&touchState.touch)
    }

    /// Simulate a swipe gesture between two screen points.
    /// Pre-computes all waypoints before the gesture loop so the path is stable
    /// even if the view moves during the gesture.
    func swipe(from start: CGPoint, to end: CGPoint, duration: GestureDuration = .swipeDefault) async -> Bool {
        guard Self.geometryIsValid([start, end], field: "swipe point") else { return false }
        return await performLineGesture(from: start, to: end, duration: duration, minimumSteps: 3)
    }

    /// Simulate a drag gesture between two screen points.
    /// Slower than swipe — used for reordering, slider adjustment, etc.
    func drag(from start: CGPoint, to end: CGPoint, duration: GestureDuration = .dragDefault) async -> Bool {
        guard Self.geometryIsValid([start, end], field: "drag point") else { return false }
        return await performLineGesture(from: start, to: end, duration: duration, minimumSteps: 5)
    }

    @discardableResult
    private func performTouchPath(start: CGPoint, waypoints: [CGPoint]) async -> Bool {
        guard var touchState = beginTouch(at: start) else { return false }

        for point in waypoints {
            if Task.isCancelled { break }
            moveTouch(&touchState.touch, in: touchState.window, to: point)
            guard await Task.cancellableSleep(
                nanoseconds: UInt64(TheSafecracker.touchGestureStepDelay * 1_000_000_000)
            ) else { break }
        }

        return endTouch(&touchState.touch)
    }

    private func performTouchTap(at point: CGPoint) async -> Bool {
        guard var touchState = beginTouch(at: point) else { return false }
        guard await Task.cancellableSleep(for: TheSafecracker.gestureYieldDelay) else {
            fingerprints.endTracking()
            return false
        }
        return endTouch(&touchState.touch)
    }

    private func performLineGesture(
        from start: CGPoint,
        to end: CGPoint,
        duration: GestureDuration,
        minimumSteps: Int
    ) async -> Bool {
        let steps = max(Int(duration.seconds / TheSafecracker.touchGestureStepDelay), minimumSteps)
        return await performTouchPath(
            start: start,
            waypoints: Self.linearPath(from: start, to: end, steps: steps)
        )
    }

    private func beginTouch(at point: CGPoint) -> (touch: TheSafecracker.SyntheticTouch, window: UIWindow)? {
        guard Self.geometryIsValid([point], field: "touch point") else { return nil }
        guard let window = windowForPoint(point) else {
            insideJobLogger.error("No window found for point \(String(describing: point))")
            return nil
        }

        let target = TheSafecracker.TouchTarget.resolve(at: point, in: window)
        guard let touch = target.makeTouch(phase: .began) else {
            insideJobLogger.error("Failed to create touch")
            return nil
        }

        guard let event = TheSafecracker.TouchEvent(touches: [touch]) else {
            insideJobLogger.error("Failed to create began event")
            return nil
        }

        event.send()
        fingerprints.beginTracking(at: [point])
        return (touch, window)
    }

    @discardableResult
    private func moveTouch(_ touch: inout TheSafecracker.SyntheticTouch, in window: UIWindow, to point: CGPoint) -> Bool {
        guard Self.geometryIsValid([point], field: "touch move point") else { return false }

        let windowPoint = window.convert(point, from: nil)
        touch.update(phase: .moved, location: windowPoint)

        guard let event = TheSafecracker.TouchEvent(touches: [touch]) else { return false }
        event.send()
        fingerprints.updateTracking(to: [point])
        return true
    }

    @discardableResult
    private func sendStationary(_ touch: inout TheSafecracker.SyntheticTouch) -> Bool {
        touch.update(phase: .stationary)

        guard let event = TheSafecracker.TouchEvent(touches: [touch]) else { return false }
        event.send()
        return true
    }

    private func endTouch(_ touch: inout TheSafecracker.SyntheticTouch) -> Bool {
        defer { fingerprints.endTracking() }
        touch.update(phase: .ended)

        guard let event = TheSafecracker.TouchEvent(touches: [touch]) else {
            insideJobLogger.error("Failed to create ended event")
            return false
        }

        event.send()
        return true
    }

    static func geometryIsValid(_ points: [CGPoint], field: String) -> Bool {
        if let reason = GeometryValidation.validateScreenPoints(points, field: field) {
            insideJobLogger.error("Rejected synthetic touch geometry: \(reason, privacy: .public)")
            return false
        }
        return true
    }

    static func linearPath(from start: CGPoint, to end: CGPoint, steps: Int) -> [CGPoint] {
        (1...steps).map { step in
            let progress = Double(step) / Double(steps)
            return CGPoint(
                x: start.x + progress * (end.x - start.x),
                y: start.y + progress * (end.y - start.y)
            )
        }
    }

    /// Find the correct window for a tap at the given screen point.
    /// Iterates all windows frontmost-first (highest windowLevel first),
    /// following KIF's pattern from UIApplication-KIFAdditions.m.
    /// Returns the first window whose hitTest succeeds at the point.
    private func windowForPoint(_ point: CGPoint) -> UIWindow? {
        guard GeometryValidation.validateScreenPoint(point) == nil else { return nil }
        for window in TheTripwire.orderedVisibleWindows() {
            let windowPoint = window.convert(point, from: nil)
            if window.hitTest(windowPoint, with: nil) != nil {
                return window
            }
        }
        return nil
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
