#if canImport(UIKit)
#if DEBUG
import Foundation
import TheScore

private let uikitIdleLogger = ButtonHeistLog.logger(.insideJob(.accessibility))

/// Keeps UIKit's animation lifecycle hooks installed while The Inside Job is
/// active and counts only animations started during active Button Heist work.
///
/// Installation is runtime-owned because Objective-C method replacement is
/// process-global. Operation tracking is demand-owned so ambient animations
/// that predate an action cannot pin that action's idle wait indefinitely.
@MainActor
final class UIKitIdleTracker {
    private struct Installation {
        let runLoopIdleObserver: RunLoopIdleObserver
        let startSwizzle: ObjCRuntime.InstanceMethodSwizzle
        let stopSwizzle: ObjCRuntime.InstanceMethodSwizzle
    }

    private enum Phase {
        case uninstalled
        case installed(Installation)
        case tracking(Installation, AnimationIdleCounter)
    }

    private var phase: Phase = .uninstalled

    var isInstalled: Bool {
        if case .uninstalled = phase { return false }
        return true
    }

    var isTrackingOperation: Bool {
        if case .tracking = phase { return true }
        return false
    }

    var operationSnapshot: AnimationIdleCounter.Snapshot? {
        guard case .tracking(_, let counter) = phase else { return nil }
        return counter.snapshot
    }

    @discardableResult
    func installIfNeeded() throws -> Bool {
        guard case .uninstalled = phase else { return false }

        let runLoopIdleObserver = RunLoopIdleObserver()
        let startSwizzle: ObjCRuntime.InstanceMethodSwizzle
        do {
            startSwizzle = try ObjCRuntime.swizzle(
                .animationDidStart,
                on: .uiViewAnimationState
            ) { [weak self] invocation in
                invocation.callOriginal()
                self?.observeAnimationStarted()
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
            ) { [weak self] invocation in
                invocation.callOriginal()
                self?.observeAnimationStopped()
            }
        } catch {
            _ = startSwizzle.restore()
            runLoopIdleObserver.invalidate()
            throw error
        }

        phase = .installed(Installation(
            runLoopIdleObserver: runLoopIdleObserver,
            startSwizzle: startSwizzle,
            stopSwizzle: stopSwizzle
        ))
        return true
    }

    func installIfAvailable() {
        do {
            _ = try installIfNeeded()
        } catch {
            uikitIdleLogger.info(
                "UIKit idle tracker is unavailable: \(String(describing: error), privacy: .public)"
            )
        }
    }

    @discardableResult
    func uninstallIfNeeded() -> Bool {
        let installation: Installation
        switch phase {
        case .uninstalled:
            return false
        case .installed(let currentInstallation):
            installation = currentInstallation
        case .tracking(let currentInstallation, let counter):
            counter.cancelAll()
            installation = currentInstallation
        }

        installation.runLoopIdleObserver.invalidate()
        _ = installation.stopSwizzle.restore()
        _ = installation.startSwizzle.restore()
        phase = .uninstalled
        return true
    }

    func beginOperationIfAvailable() {
        guard case .installed(let installation) = phase else { return }
        phase = .tracking(installation, AnimationIdleCounter())
    }

    func endOperationIfNeeded() {
        guard case .tracking(let installation, let counter) = phase else { return }
        counter.cancelAll()
        phase = .installed(installation)
    }

    func waitUntilIdle(timeout: Duration) async -> Bool {
        guard case .tracking(let installation, let counter) = phase else { return false }
        let deadline = ContinuousClock.now.advanced(by: timeout)

        while !Task.isCancelled {
            let animationBudget = ContinuousClock.now.duration(to: deadline)
            guard animationBudget > .zero,
                  await counter.waitUntilIdle(timeout: animationBudget) else {
                return false
            }

            let runLoopBudget = ContinuousClock.now.duration(to: deadline)
            guard runLoopBudget > .zero,
                  await installation.runLoopIdleObserver.waitForNextIdle(timeout: runLoopBudget) else {
                return false
            }

            if counter.activeCount == 0 {
                return true
            }
        }
        return false
    }

    private func observeAnimationStarted() {
        guard case .tracking(_, let counter) = phase else { return }
        counter.observeAnimationStarted()
    }

    private func observeAnimationStopped() {
        guard case .tracking(_, let counter) = phase else { return }
        if counter.observeAnimationStopped() == .unmatchedStop {
            uikitIdleLogger.warning(
                "UIViewAnimationState animationDidStop arrived without a matching animationDidStart; clamped active animation count to zero"
            )
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
