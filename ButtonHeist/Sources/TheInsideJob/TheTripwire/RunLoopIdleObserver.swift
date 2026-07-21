#if canImport(UIKit)
#if DEBUG
import ButtonHeistSupport
import CoreFoundation
import Foundation

/// Publishes one-shot main-run-loop idle edges for a single heist session.
@MainActor
final class RunLoopIdleObserver {
    private enum Phase {
        case observing(CFRunLoopObserver)
        case invalidated
    }

    private var phase: Phase = .invalidated
    private var waiters = WaiterStore<UInt64, TimedOneShot<Bool>>()

    init() {
        let observer = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault,
            CFRunLoopActivity.beforeWaiting.rawValue,
            true,
            0
        ) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.observeBeforeWaiting()
            }
        }
        guard let observer else {
            preconditionFailure("Main run-loop idle observer must be constructible")
        }
        phase = .observing(observer)
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    func waitForNextIdle(timeout: Duration) async -> Bool {
        guard timeout > .zero, case .observing = phase else { return false }
        let waiterID = waiters.reserveID()
        let oneShot = TimedOneShot<Bool>()
        return await oneShot.wait(
            cancellationValue: false,
            onRegistered: { oneShot in
                waiters.insert(oneShot, id: waiterID)
                CFRunLoopWakeUp(CFRunLoopGetMain())
                oneShot.armTimeout(after: timeout) { [weak self] in
                    await self?.resolve(waiterID, returning: false)
                }
            },
            onFinished: { [weak self] in
                self?.remove(waiterID)
            }
        )
    }

    func invalidate() {
        guard case .observing(let observer) = phase else { return }
        CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
        CFRunLoopObserverInvalidate(observer)
        phase = .invalidated
        waiters.removeAll().forEach { $0.resolve(returning: false) }
    }

    private func observeBeforeWaiting() {
        let idleWaiters = waiters.removeAll()
        idleWaiters.forEach { $0.resolve(returning: true) }
    }

    private func resolve(_ waiterID: UInt64, returning value: Bool) {
        waiters.remove(id: waiterID)?.resolve(returning: value)
    }

    private func remove(_ waiterID: UInt64) {
        _ = waiters.remove(id: waiterID)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
