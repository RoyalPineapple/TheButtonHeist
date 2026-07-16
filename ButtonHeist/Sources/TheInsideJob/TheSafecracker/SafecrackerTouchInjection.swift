#if canImport(UIKit)
#if DEBUG
import UIKit
import ButtonHeistSupport
import TheScore
import ThePlans

@MainActor
final class SafecrackerTouchInjection {

    fileprivate struct ActiveTouch {
        var touch: TheSafecracker.SyntheticTouch
        let window: UIWindow
    }

    fileprivate enum Completion {
        case tap
        case stationary(GestureDuration)
        case path([CGPoint])
    }

    struct PreparedTouch {
        fileprivate let activeTouch: ActiveTouch
        fileprivate let completion: Completion
    }

    struct PreparedTouchID: RawRepresentable, Equatable, Hashable, Sendable {
        let rawValue: UInt64
    }

    private let fingerprints: TheFingerprints
    private var preparedTouches: [PreparedTouchID: PreparedTouch] = [:]
    private var nextPreparedTouchID = PreparedTouchID(rawValue: 1)

    init(fingerprints: TheFingerprints) {
        self.fingerprints = fingerprints
    }

    func prepareTap(at point: CGPoint) -> PreparedTouchID? {
        retain(prepareTouch(at: point, field: "tap point", completion: .tap))
    }

    func prepareLongPress(
        at point: CGPoint,
        duration: GestureDuration = .longPressDefault
    ) -> PreparedTouchID? {
        retain(prepareTouch(
            at: point,
            field: "long press point",
            completion: .stationary(duration)
        ))
    }

    func prepareSwipe(
        from start: CGPoint,
        to end: CGPoint,
        duration: GestureDuration = .swipeDefault
    ) -> PreparedTouchID? {
        retain(prepareLineGesture(
            from: start,
            to: end,
            duration: duration,
            minimumSteps: 3,
            field: "swipe point"
        ))
    }

    func prepareDrag(
        from start: CGPoint,
        to end: CGPoint,
        duration: GestureDuration = .dragDefault
    ) -> PreparedTouchID? {
        retain(prepareLineGesture(
            from: start,
            to: end,
            duration: duration,
            minimumSteps: 5,
            field: "drag point"
        ))
    }

    func complete(_ preparedTouchID: PreparedTouchID) async -> Bool {
        guard let prepared = preparedTouches.removeValue(forKey: preparedTouchID) else {
            return false
        }
        var touchState = prepared.activeTouch
        switch prepared.completion {
        case .tap:
            guard await Task.cancellableSleep(for: TheSafecracker.gestureYieldDelay) else {
                fingerprints.endTracking()
                return false
            }
        case .stationary(let duration):
            var elapsed: TimeInterval = 0
            while elapsed < duration.seconds && !Task.isCancelled {
                guard await Task.cancellableSleep(
                    nanoseconds: UInt64(TheSafecracker.touchGestureStepDelay * 1_000_000_000)
                ) else { break }
                elapsed += TheSafecracker.touchGestureStepDelay
                sendStationary(&touchState.touch)
            }
        case .path(let waypoints):
            for point in waypoints {
                if Task.isCancelled { break }
                moveTouch(&touchState.touch, in: touchState.window, to: point)
                guard await Task.cancellableSleep(
                    nanoseconds: UInt64(TheSafecracker.touchGestureStepDelay * 1_000_000_000)
                ) else { break }
            }
        }
        return endTouch(&touchState.touch)
    }

    private func retain(_ preparedTouch: PreparedTouch?) -> PreparedTouchID? {
        guard let preparedTouch else { return nil }
        let preparedTouchID = nextPreparedTouchID
        nextPreparedTouchID = PreparedTouchID(rawValue: preparedTouchID.rawValue + 1)
        preparedTouches[preparedTouchID] = preparedTouch
        return preparedTouchID
    }

    private func prepareTouch(
        at point: CGPoint,
        field: String,
        completion: Completion
    ) -> PreparedTouch? {
        guard Self.geometryIsValid([point], field: field),
              let activeTouch = beginTouch(at: point) else { return nil }
        return PreparedTouch(activeTouch: activeTouch, completion: completion)
    }

    private func prepareLineGesture(
        from start: CGPoint,
        to end: CGPoint,
        duration: GestureDuration,
        minimumSteps: Int,
        field: String
    ) -> PreparedTouch? {
        guard Self.geometryIsValid([start, end], field: field) else { return nil }
        let steps = max(Int(duration.seconds / TheSafecracker.touchGestureStepDelay), minimumSteps)
        return prepareTouch(
            at: start,
            field: field,
            completion: .path(Self.linearPath(from: start, to: end, steps: steps))
        )
    }

    private func beginTouch(at point: CGPoint) -> ActiveTouch? {
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
        return ActiveTouch(touch: touch, window: window)
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
