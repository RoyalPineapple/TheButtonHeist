#if canImport(UIKit)
#if DEBUG
import UIKit

extension TheSafecracker {

    // MARK: - Public: Multi-Touch Gestures

    /// Simulate a pinch gesture centered at a screen point.
    /// - Parameters:
    ///   - center: Center point of the pinch in screen coordinates
    ///   - scale: Scale factor (>1.0 = spread/zoom in, <1.0 = pinch/zoom out)
    ///   - spread: Initial distance from center to each finger (default 100pt)
    ///   - duration: Duration of the gesture (default 0.5s)
    func pinch(center: CGPoint, scale: CGFloat, spread: CGFloat = 100, duration: TimeInterval = 0.5) async -> Bool {
        let angle: CGFloat = .pi / 4 // 45° diagonal
        let startSpread = spread
        let endSpread = spread * scale

        let finger1Start = CGPoint(
            x: center.x + cos(angle) * startSpread,
            y: center.y + sin(angle) * startSpread
        )
        let finger2Start = CGPoint(
            x: center.x - cos(angle) * startSpread,
            y: center.y - sin(angle) * startSpread
        )

        guard touchesDown(at: [finger1Start, finger2Start]) else { return false }
        fingerprints.beginTrackingFingerprints(at: [finger1Start, finger2Start])
        onGestureMove?([finger1Start, finger2Start])

        let stepDelay: TimeInterval = 0.01
        let steps = max(Int(duration / stepDelay), 5)

        for i in 1...steps {
            let progress = CGFloat(i) / CGFloat(steps)
            let currentSpread = startSpread + progress * (endSpread - startSpread)

            let p1 = CGPoint(
                x: center.x + cos(angle) * currentSpread,
                y: center.y + sin(angle) * currentSpread
            )
            let p2 = CGPoint(
                x: center.x - cos(angle) * currentSpread,
                y: center.y - sin(angle) * currentSpread
            )
            if Task.isCancelled { break }
            moveTouches(to: [p1, p2])
            fingerprints.updateTrackingFingerprints(to: [p1, p2])
            onGestureMove?([p1, p2])
            guard await cancellableSleep(nanoseconds: UInt64(stepDelay * 1_000_000_000)) else { break }
        }

        fingerprints.endTrackingFingerprints()
        return touchesUp()
    }

    /// Simulate a rotation gesture centered at a screen point.
    /// - Parameters:
    ///   - center: Center point of the rotation in screen coordinates
    ///   - angle: Rotation angle in radians (positive = counter-clockwise)
    ///   - radius: Distance from center to each finger (default 100pt)
    ///   - duration: Duration of the gesture (default 0.5s)
    func rotate(center: CGPoint, angle: CGFloat, radius: CGFloat = 100, duration: TimeInterval = 0.5) async -> Bool {
        let startAngle: CGFloat = 0

        let finger1Start = CGPoint(
            x: center.x + cos(startAngle) * radius,
            y: center.y + sin(startAngle) * radius
        )
        let finger2Start = CGPoint(
            x: center.x + cos(startAngle + .pi) * radius,
            y: center.y + sin(startAngle + .pi) * radius
        )

        guard touchesDown(at: [finger1Start, finger2Start]) else { return false }
        fingerprints.beginTrackingFingerprints(at: [finger1Start, finger2Start])
        onGestureMove?([finger1Start, finger2Start])

        let stepDelay: TimeInterval = 0.01
        let steps = max(Int(duration / stepDelay), 5)

        for i in 1...steps {
            let progress = CGFloat(i) / CGFloat(steps)
            let currentAngle = startAngle + progress * angle

            let p1 = CGPoint(
                x: center.x + cos(currentAngle) * radius,
                y: center.y + sin(currentAngle) * radius
            )
            let p2 = CGPoint(
                x: center.x + cos(currentAngle + .pi) * radius,
                y: center.y + sin(currentAngle + .pi) * radius
            )
            if Task.isCancelled { break }
            moveTouches(to: [p1, p2])
            fingerprints.updateTrackingFingerprints(to: [p1, p2])
            onGestureMove?([p1, p2])
            guard await cancellableSleep(nanoseconds: UInt64(stepDelay * 1_000_000_000)) else { break }
        }

        fingerprints.endTrackingFingerprints()
        return touchesUp()
    }

    /// Simulate a two-finger tap at a screen point.
    /// Yields to the main run loop between began and ended phases so that
    /// SwiftUI gesture recognizers have time to process the began event.
    /// - Parameters:
    ///   - center: Center point between the two fingers
    ///   - spread: Distance between the two fingers (default 40pt)
    func twoFingerTap(at center: CGPoint, spread: CGFloat = 40) async -> Bool {
        let p1 = CGPoint(x: center.x - spread / 2, y: center.y)
        let p2 = CGPoint(x: center.x + spread / 2, y: center.y)
        guard touchesDown(at: [p1, p2]) else { return false }
        guard await cancellableSleep(for: TheSafecracker.gestureYieldDelay) else { return false }
        return touchesUp()
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
