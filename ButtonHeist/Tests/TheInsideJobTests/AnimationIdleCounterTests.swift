#if canImport(UIKit)
import Testing
@testable import TheInsideJob

@Suite("Animation idle counter")
struct AnimationIdleCounterTests {
    @Test("Idle wait completes immediately when no animation is active")
    func idleWaitCompletesImmediately() async {
        let counter = AnimationIdleCounter()

        #expect(await counter.waitUntilIdle(timeout: .seconds(1)))
        #expect(counter.waiterCount == 0)
    }

    @Test("Aggregate count fires only on the one-to-zero edge")
    func aggregateCountFiresAtZeroEdge() async {
        let counter = AnimationIdleCounter()
        counter.observeAnimationStarted()
        counter.observeAnimationStarted()
        let waiter = Task { await counter.waitUntilIdle(timeout: .seconds(1)) }
        await waitForWaiter(in: counter)

        #expect(counter.observeAnimationStopped() == .active(remaining: 1))
        #expect(counter.activeCount == 1)
        #expect(counter.waiterCount == 1)
        #expect(counter.observeAnimationStopped() == .becameIdle)
        #expect(await waiter.value)
        #expect(counter.activeCount == 0)
        #expect(counter.waiterCount == 0)
    }

    @Test("Idle waiters are one-shot and later cycles must register again")
    func waitersAreOneShot() async {
        let counter = AnimationIdleCounter()
        counter.observeAnimationStarted()
        let first = Task { await counter.waitUntilIdle(timeout: .seconds(1)) }
        await waitForWaiter(in: counter)

        #expect(counter.observeAnimationStopped() == .becameIdle)
        #expect(await first.value)

        counter.observeAnimationStarted()
        let second = Task { await counter.waitUntilIdle(timeout: .seconds(1)) }
        await waitForWaiter(in: counter)
        #expect(counter.waiterCount == 1)
        #expect(counter.observeAnimationStopped() == .becameIdle)
        #expect(await second.value)
    }

    @Test("Unmatched stop clamps the count at zero")
    func unmatchedStopClampsAtZero() {
        let counter = AnimationIdleCounter()

        #expect(counter.observeAnimationStopped() == .unmatchedStop)
        #expect(counter.activeCount == 0)
    }

    private func waitForWaiter(in counter: AnimationIdleCounter) async {
        for _ in 0..<1_000 {
            guard counter.waiterCount == 0 else { return }
            await Task.yield()
        }
        Issue.record("Timed out waiting for animation-idle waiter registration")
    }
}
#endif
