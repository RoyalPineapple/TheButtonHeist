import ButtonHeistSupport
import Testing

@Suite struct OneShotContinuationTests {
    @Test func `resume before register makes later register report completion`() async {
        let continuation = OneShotContinuation<Int>()

        continuation.resume(returning: 7)

        let result = await withCheckedContinuation { (waiting: CheckedContinuation<Int, Never>) in
            let didRegister = continuation.register(waiting)
            if didRegister {
                continuation.resume(returning: 0)
            } else {
                waiting.resume(returning: -1)
            }
        }

        #expect(result == -1)
    }

    @Test func `registered continuation resumes exactly once`() async {
        let continuation = OneShotContinuation<Int>()
        let registered = OneShotContinuation<Void>()

        let task = Task {
            await withCheckedContinuation { waiting in
                let didRegister = continuation.register(waiting)
                #expect(didRegister)
                registered.resume(returning: ())
                if !didRegister {
                    waiting.resume(returning: -1)
                }
            }
        }

        await wait(for: registered)
        continuation.resume(returning: 11)
        continuation.resume(returning: 12)

        await #expect(task.value == 11)
    }

    @Test func `register after completed wait does not park continuation`() async {
        let continuation = OneShotContinuation<Int>()
        let registered = OneShotContinuation<Void>()

        let task = Task {
            await withCheckedContinuation { waiting in
                let didRegister = continuation.register(waiting)
                #expect(didRegister)
                registered.resume(returning: ())
                if !didRegister {
                    waiting.resume(returning: -1)
                }
            }
        }

        await wait(for: registered)
        continuation.resume(returning: 3)
        await #expect(task.value == 3)

        let result = await withCheckedContinuation { (waiting: CheckedContinuation<Int, Never>) in
            let didRegister = continuation.register(waiting)
            if didRegister {
                continuation.resume(returning: 4)
            } else {
                waiting.resume(returning: -1)
            }
        }

        #expect(result == -1)
    }

    private func wait(for continuation: OneShotContinuation<Void>) async {
        await withCheckedContinuation { (waiting: CheckedContinuation<Void, Never>) in
            guard continuation.register(waiting) else {
                waiting.resume()
                return
            }
        }
    }
}
