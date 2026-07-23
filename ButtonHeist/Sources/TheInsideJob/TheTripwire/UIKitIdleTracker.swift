#if canImport(UIKit)
#if DEBUG
import Foundation
import TheScore

private let uikitIdleLogger = ButtonHeistLog.logger(.insideJob(.accessibility))

/// Keeps UIKit's animation lifecycle hooks and one continuous animation count
/// installed while The Inside Job is active.
///
/// Installation is runtime-owned because Objective-C method replacement is
/// process-global. Active observation demand owns permission to wait, while the
/// lifecycle count also retains animations that began before a heist started.
@MainActor
final class UIKitIdleTracker {
    // MARK: - Nested Types

    private struct Installation {
        let runLoopIdleObserver: RunLoopIdleObserver
        let startSwizzle: ObjCRuntime.InstanceMethodSwizzle
        let stopSwizzle: ObjCRuntime.InstanceMethodSwizzle
    }

    private struct InstalledState {
        let installation: Installation
        let counter: AnimationIdleCounter
        var operationDepth: Int
    }

    private enum Phase {
        case uninstalled
        case installed(InstalledState)
    }

    // MARK: - Properties

    private var phase: Phase = .uninstalled

    var isInstalled: Bool {
        if case .uninstalled = phase { return false }
        return true
    }

    var isTrackingOperation: Bool {
        guard case .installed(let state) = phase else { return false }
        return state.operationDepth > 0
    }

    var animationSnapshot: AnimationIdleCounter.Snapshot? {
        guard case .installed(let state) = phase else { return nil }
        return state.counter.snapshot
    }

    // MARK: - Runtime Lifecycle

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

        phase = .installed(InstalledState(
            installation: Installation(
                runLoopIdleObserver: runLoopIdleObserver,
                startSwizzle: startSwizzle,
                stopSwizzle: stopSwizzle
            ),
            counter: AnimationIdleCounter(),
            operationDepth: 0
        ))
        return true
    }

    func installIfAvailable() {
        do {
            _ = try installIfNeeded()
        } catch {
            uikitIdleLogger.warning(
                "UIKit idle tracker is unavailable: \(String(describing: error), privacy: .public)"
            )
        }
    }

    @discardableResult
    func uninstallIfNeeded() -> Bool {
        let installedState: InstalledState
        switch phase {
        case .uninstalled:
            return false
        case .installed(let state):
            installedState = state
        }

        installedState.counter.cancelAll()
        installedState.installation.runLoopIdleObserver.invalidate()
        _ = installedState.installation.stopSwizzle.restore()
        _ = installedState.installation.startSwizzle.restore()
        phase = .uninstalled
        return true
    }

    // MARK: - Active Observation

    func beginOperationIfAvailable() {
        guard case .installed(var state) = phase else { return }
        precondition(state.operationDepth < Int.max, "UIKit idle operation depth overflowed")
        state.operationDepth += 1
        phase = .installed(state)
    }

    func endOperationIfNeeded() {
        guard case .installed(var state) = phase, state.operationDepth > 0 else { return }
        state.operationDepth -= 1
        if state.operationDepth == 0 {
            state.counter.cancelAll()
        }
        phase = .installed(state)
    }

    func waitUntilIdle(timeout: Duration) async -> Bool {
        guard case .installed(let state) = phase, state.operationDepth > 0 else { return false }
        guard timeout > .zero else { return state.counter.activeCount == 0 }
        let deadline = ContinuousClock.now.advanced(by: timeout)

        while !Task.isCancelled {
            let animationBudget = ContinuousClock.now.duration(to: deadline)
            guard animationBudget > .zero,
                  await state.counter.waitUntilIdle(timeout: animationBudget) else {
                return false
            }

            let runLoopBudget = ContinuousClock.now.duration(to: deadline)
            guard runLoopBudget > .zero,
                  await state.installation.runLoopIdleObserver.waitForNextIdle(timeout: runLoopBudget) else {
                return false
            }

            if state.counter.activeCount == 0 {
                return true
            }
        }
        return false
    }

    // MARK: - Private Helpers

    private func observeAnimationStarted() {
        guard case .installed(let state) = phase else { return }
        state.counter.observeAnimationStarted()
    }

    private func observeAnimationStopped() {
        guard case .installed(let state) = phase else { return }
        if state.counter.observeAnimationStopped() == .unmatchedStop {
            uikitIdleLogger.debug(
                "UIViewAnimationState animationDidStop arrived without a matching animationDidStart; clamped active animation count to zero"
            )
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
