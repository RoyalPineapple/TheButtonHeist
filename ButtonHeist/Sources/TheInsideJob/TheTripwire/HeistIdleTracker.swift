#if canImport(UIKit)
#if DEBUG
import Foundation
import TheScore

private let heistIdleLogger = ButtonHeistLog.logger(.insideJob(.accessibility))

enum HeistIdleTrackingError: Error, Equatable {
    case alreadyTracking
}

@MainActor
final class HeistIdleTrackingLease {
    private enum Phase {
        case active(cancel: @MainActor () -> Void)
        case cancelled
    }

    private var phase: Phase

    init(cancel: @escaping @MainActor () -> Void) {
        phase = .active(cancel: cancel)
    }

    func cancel() {
        guard case .active(let cancel) = phase else { return }
        phase = .cancelled
        cancel()
    }
}

/// Gates settlement on UIKit animation completion and a drained main run loop.
///
/// The tracker deliberately owns one aggregate counter, not per-animation or
/// per-group state. Its lease is installed once at the outer heist boundary
/// and restored after final settlement/evidence capture.
@MainActor
final class HeistIdleTracker {
    private struct Session {
        let id: UUID
        let counter: AnimationIdleCounter
        let runLoopIdleObserver: RunLoopIdleObserver
        let startSwizzle: ObjCRuntime.InstanceMethodSwizzle
        let stopSwizzle: ObjCRuntime.InstanceMethodSwizzle
    }

    private enum Phase {
        case idle
        case tracking(Session)
    }

    private var phase: Phase = .idle

    var isTracking: Bool {
        if case .tracking = phase { return true }
        return false
    }

    func beginTracking() throws -> HeistIdleTrackingLease {
        guard case .idle = phase else {
            throw HeistIdleTrackingError.alreadyTracking
        }

        let counter = AnimationIdleCounter()
        let runLoopIdleObserver = RunLoopIdleObserver()
        let startSwizzle: ObjCRuntime.InstanceMethodSwizzle
        do {
            startSwizzle = try ObjCRuntime.swizzle(
                .animationDidStart,
                on: .uiViewAnimationState
            ) { invocation in
                invocation.callOriginal()
                counter.observeAnimationStarted()
            }
        } catch {
            runLoopIdleObserver.invalidate()
            throw error
        }

        let stopSwizzle: ObjCRuntime.InstanceMethodSwizzle
        do {
            stopSwizzle = try ObjCRuntime.swizzle(
                .animationDidStop,
                on: .uiViewAnimationState
            ) { invocation in
                invocation.callOriginal()
                if counter.observeAnimationStopped() == .unmatchedStop {
                    heistIdleLogger.warning(
                        "UIViewAnimationState animationDidStop arrived without a matching animationDidStart; clamped active animation count to zero"
                    )
                }
            }
        } catch {
            _ = startSwizzle.restore()
            runLoopIdleObserver.invalidate()
            throw error
        }

        let sessionID = UUID()
        phase = .tracking(Session(
            id: sessionID,
            counter: counter,
            runLoopIdleObserver: runLoopIdleObserver,
            startSwizzle: startSwizzle,
            stopSwizzle: stopSwizzle
        ))
        return HeistIdleTrackingLease { [weak self] in
            self?.endTracking(sessionID: sessionID)
        }
    }

    func beginTrackingIfAvailable() -> HeistIdleTrackingLease? {
        do {
            return try beginTracking()
        } catch {
            heistIdleLogger.info(
                "Heist idle tracker is unavailable: \(String(describing: error), privacy: .public)"
            )
            return nil
        }
    }

    func waitUntilIdle(timeout: Duration) async -> Bool {
        guard case .tracking(let session) = phase else { return false }
        let deadline = ContinuousClock.now.advanced(by: timeout)

        while !Task.isCancelled {
            let animationBudget = ContinuousClock.now.duration(to: deadline)
            guard animationBudget > .zero,
                  await session.counter.waitUntilIdle(timeout: animationBudget) else {
                return false
            }

            let runLoopBudget = ContinuousClock.now.duration(to: deadline)
            guard runLoopBudget > .zero,
                  await session.runLoopIdleObserver.waitForNextIdle(timeout: runLoopBudget) else {
                return false
            }

            if session.counter.activeCount == 0 {
                return true
            }
        }
        return false
    }

    fileprivate func endTracking(sessionID: UUID) {
        guard case .tracking(let session) = phase, session.id == sessionID else { return }

        session.counter.cancelAll()
        session.runLoopIdleObserver.invalidate()
        _ = session.stopSwizzle.restore()
        _ = session.startSwizzle.restore()
        phase = .idle
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
