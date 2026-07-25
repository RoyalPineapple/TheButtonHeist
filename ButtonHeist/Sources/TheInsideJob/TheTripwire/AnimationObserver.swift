#if canImport(UIKit)
#if DEBUG
import Foundation
import os

import TheScore

private let animationObserverLogger = ButtonHeistLog.logger(.insideJob(.accessibility))

/// Keeps UIKit's animation lifecycle hooks installed while The Inside Job is
/// active and counts the process-wide animation edges they report.
///
/// Installation is runtime-owned because Objective-C method replacement is
/// process-global. The count is a lifecycle-wide fact: it retains animations
/// that began before a heist started, and `animationSnapshot` reads it
/// synchronously with no prior registration.
@MainActor
final class AnimationObserver {
    // MARK: - Nested Types

    /// An immutable sample of the animation edge counts at one instant.
    struct Snapshot: Sendable, Equatable {
        let activeCount: Int
        let observedStartCount: Int
        let matchedStopCount: Int
        let unmatchedStopCount: Int
    }

    enum StopOutcome: Equatable {
        case active(remaining: Int)
        case becameIdle
        case unmatchedStop
    }

    private struct Counts: Sendable {
        var activeCount = 0
        var observedStartCount = 0
        var matchedStopCount = 0
        var unmatchedStopCount = 0
    }

    private struct Installation {
        let startSwizzle: ObjCRuntime.InstanceMethodSwizzle
        let stopSwizzle: ObjCRuntime.InstanceMethodSwizzle
    }

    private enum Phase {
        case uninstalled
        case installed(Installation)
    }

    // MARK: - Properties

    private let counts = OSAllocatedUnfairLock(initialState: Counts())

    private var phase: Phase = .uninstalled

    var isInstalled: Bool {
        if case .uninstalled = phase { return false }
        return true
    }

    /// The current animation edge counts, or `nil` while the hooks are uninstalled.
    var animationSnapshot: Snapshot? {
        guard case .installed = phase else { return nil }
        return counts.withLock {
            Snapshot(
                activeCount: $0.activeCount,
                observedStartCount: $0.observedStartCount,
                matchedStopCount: $0.matchedStopCount,
                unmatchedStopCount: $0.unmatchedStopCount
            )
        }
    }

    // MARK: - Runtime Lifecycle

    @discardableResult
    func installIfNeeded() throws -> Bool {
        guard case .uninstalled = phase else { return false }

        let startSwizzle = try ObjCRuntime.swizzle(
            .animationDidStart,
            on: .uiViewAnimationState
        ) { [weak self] invocation in
            invocation.callOriginal()
            self?.observeAnimationStarted()
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
            throw error
        }

        // Each installation starts a fresh count, matching the per-install
        // counter instance this type replaced.
        counts.withLock { $0 = Counts() }
        phase = .installed(Installation(startSwizzle: startSwizzle, stopSwizzle: stopSwizzle))
        return true
    }

    func installIfAvailable() {
        do {
            _ = try installIfNeeded()
        } catch {
            animationObserverLogger.warning(
                "Animation observer is unavailable: \(String(describing: error), privacy: .public)"
            )
        }
    }

    @discardableResult
    func uninstallIfNeeded() -> Bool {
        guard case .installed(let installation) = phase else { return false }
        _ = installation.stopSwizzle.restore()
        _ = installation.startSwizzle.restore()
        phase = .uninstalled
        return true
    }

    // MARK: - Animation Observation

    func observeAnimationStarted() {
        counts.withLock { counts in
            precondition(counts.activeCount < Int.max, "Animation count overflowed")
            counts.activeCount += 1
            counts.observedStartCount += 1
        }
    }

    @discardableResult
    func observeAnimationStopped() -> StopOutcome {
        let outcome = counts.withLock { counts -> StopOutcome in
            guard counts.activeCount > 0 else {
                counts.unmatchedStopCount += 1
                return .unmatchedStop
            }
            counts.activeCount -= 1
            counts.matchedStopCount += 1
            return counts.activeCount == 0 ? .becameIdle : .active(remaining: counts.activeCount)
        }
        if outcome == .unmatchedStop {
            animationObserverLogger.debug(
                "UIViewAnimationState animationDidStop arrived without a matching animationDidStart; clamped active animation count to zero"
            )
        }
        return outcome
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
