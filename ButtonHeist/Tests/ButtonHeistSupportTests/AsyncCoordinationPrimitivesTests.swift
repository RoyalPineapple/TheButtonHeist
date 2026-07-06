import ButtonHeistSupport
import Testing

@Suite struct AsyncCoordinationPrimitivesTests {
    @Test func `resolve before timeout drains waiter and cancels timer`() async {
        let harness = WaiterHarness()
        let task = Task {
            await harness.wait(key: "resolve", timeout: .seconds(30), timeoutValue: 99)
        }

        await #expect(waitUntil { await harness.count == 1 })
        await #expect(harness.resolve("resolve", returning: 7))
        await #expect(task.value == 7)
        await #expect(harness.count == 0)
        await #expect(harness.timeoutFireCount == 0)
    }

    @Test func `timeout before resolve drains waiter and rejects stale resolve`() async {
        let harness = WaiterHarness()
        let task = Task {
            await harness.wait(key: "timeout", timeout: .milliseconds(1), timeoutValue: 42)
        }

        await #expect(task.value == 42)
        await #expect(harness.timeoutFireCount == 1)
        await #expect(harness.count == 0)
        await #expect(!harness.resolve("timeout", returning: 7))
    }

    @Test func `cancellation resumes and unregisters waiter`() async {
        let harness = WaiterHarness()
        let task = Task {
            await harness.wait(key: "cancel", timeout: .seconds(30), timeoutValue: 99)
        }

        await #expect(waitUntil { await harness.count == 1 })
        task.cancel()

        await #expect(task.value == WaiterHarness.cancelledValue)
        await #expect(waitUntil { await harness.count == 0 })
        await #expect(!harness.resolve("cancel", returning: 7))
    }

    @Test func `duplicate and stale resolution only resolves once`() async {
        let harness = WaiterHarness()
        let task = Task {
            await harness.wait(key: "once", timeout: nil, timeoutValue: 99)
        }

        await #expect(waitUntil { await harness.count == 1 })
        await #expect(harness.resolve("once", returning: 3))
        await #expect(!harness.resolve("once", returning: 4))
        await #expect(task.value == 3)
        await #expect(harness.count == 0)
        await #expect(!harness.resolve("missing", returning: 5))
    }

}

private actor WaiterHarness {
    static let cancelledValue = -1

    private var waiters = AsyncWaiterRegistry<String, Int>()
    private(set) var timeoutFireCount = 0

    var count: Int {
        waiters.count
    }

    func wait(key: String, timeout: Duration?, timeoutValue: Int) async -> Int {
        let oneShot = TimedOneShot<Int>()
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
                if Task.isCancelled {
                    continuation.resume(returning: Self.cancelledValue)
                    return
                }
                guard oneShot.register(continuation) else {
                    continuation.resume(returning: Self.cancelledValue)
                    return
                }
                waiters.insert(oneShot, for: key)
                if let timeout {
                    oneShot.armTimeout(after: timeout) { [weak self] in
                        await self?.timeout(key: key, returning: timeoutValue)
                    }
                }
            }
        } onCancel: {
            oneShot.resolve(returning: Self.cancelledValue)
        }
        waiters.resolve(key, returning: Self.cancelledValue)
        return result
    }

    @discardableResult
    func resolve(_ key: String, returning value: Int) -> Bool {
        waiters.resolve(key, returning: value)
    }

    private func timeout(key: String, returning value: Int) {
        timeoutFireCount += 1
        waiters.resolve(key, returning: value)
    }
}

private func waitUntil(_ condition: @escaping @Sendable () async -> Bool) async -> Bool {
    for _ in 0..<10_000 {
        if await condition() {
            return true
        }
        await Task.yield()
    }
    return await condition()
}
