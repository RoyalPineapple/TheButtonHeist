#if canImport(UIKit)
import CoreFoundation
import Foundation
import os

import TheScore

internal enum MainThreadProbe {
    internal struct Timeout: Sendable {
        private let finiteNanoseconds: UInt64?

        internal init(milliseconds: Int64) {
            let milliseconds = UInt64(clamping: milliseconds)
            let (nanoseconds, overflowed) = milliseconds.multipliedReportingOverflow(
                by: 1_000_000
            )
            finiteNanoseconds = overflowed ? nil : nanoseconds
        }

        internal init(nanoseconds: UInt64) {
            finiteNanoseconds = nanoseconds
        }

        fileprivate var deadline: DispatchTime {
            guard let finiteNanoseconds else { return .distantFuture }
            let (uptime, overflowed) = DispatchTime.now().uptimeNanoseconds
                .addingReportingOverflow(finiteNanoseconds)
            return overflowed ? .distantFuture : DispatchTime(uptimeNanoseconds: uptime)
        }
    }

    internal struct Timeouts: Sendable {
        internal let responsiveness: Timeout
        internal let work: Timeout

        internal init(responsiveness: Timeout, work: Timeout) {
            self.responsiveness = responsiveness
            self.work = work
        }

        internal init(_ request: MainThreadProbeRequest) {
            responsiveness = Timeout(
                milliseconds: request.responsivenessTimeoutMilliseconds
            )
            work = Timeout(milliseconds: request.workTimeoutMilliseconds)
        }
    }

    internal typealias MainOperation = @MainActor @Sendable () -> Void

    fileprivate enum Termination: Sendable {
        case outcome(MainThreadProbeOutcome)
        case cancelled
    }

    private enum Phase: Sendable {
        case waitingForMain
        case waitingForWork
        case executingWork
        case terminal(Termination)
    }

    internal struct Dependencies: Sendable {
        internal let schedule: @Sendable (@escaping MainOperation) -> Void
        internal let executeWork: @MainActor @Sendable (
            @escaping MainOperation,
            @escaping @Sendable () -> Void
        ) -> Void
        internal let wait: @Sendable (
            DispatchSemaphore,
            Timeout
        ) -> DispatchTimeoutResult
        internal let waitQueue: DispatchQueue

        internal static let live = Dependencies(
            schedule: { operation in
                let runLoop = CFRunLoopGetMain()
                CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes as AnyObject) {
                    MainActor.assumeIsolated {
                        operation()
                    }
                }
                CFRunLoopWakeUp(runLoop)
            },
            executeWork: { operation, completion in
                let runLoop = CFRunLoopGetMain()
                CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes as AnyObject) {
                    MainActor.assumeIsolated {
                        operation()
                        completion()
                    }
                }
                CFRunLoopWakeUp(runLoop)
            },
            wait: { semaphore, timeout in
                semaphore.wait(timeout: timeout.deadline)
            },
            waitQueue: DispatchQueue(
                label: "com.buttonheist.main-thread-probe",
                qos: .userInitiated,
                attributes: .concurrent
            )
        )
    }

    internal static func execute(
        _ request: MainThreadProbeRequest
    ) async throws -> MainThreadProbeResponse {
        MainThreadProbeResponse(
            outcome: try await execute(timeouts: Timeouts(request), work: {})
        )
    }

    internal static func execute(
        timeouts: Timeouts,
        dependencies: Dependencies = .live,
        work: @escaping MainOperation
    ) async throws -> MainThreadProbeOutcome {
        let gate = Gate()
        let responsivenessSemaphore = DispatchSemaphore(value: 0)
        let workSemaphore = DispatchSemaphore(value: 0)

        dependencies.schedule {
            guard gate.beginWork() else { return }
            responsivenessSemaphore.signal()
            dependencies.executeWork(
                {
                    guard gate.beginExecution() else { return }
                    work()
                },
                {
                    guard gate.complete() else { return }
                    workSemaphore.signal()
                }
            )
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                dependencies.waitQueue.async {
                    if dependencies.wait(
                        responsivenessSemaphore,
                        timeouts.responsiveness
                    ) == .timedOut, let termination = gate.timeoutWaitingForMain() {
                        continuation.resume(with: termination.result)
                        return
                    }

                    if let termination = gate.termination {
                        continuation.resume(with: termination.result)
                        return
                    }

                    if dependencies.wait(workSemaphore, timeouts.work) == .timedOut {
                        continuation.resume(with: gate.timeoutWork().result)
                        return
                    }

                    continuation.resume(with: gate.requiredTermination.result)
                }
            }
        } onCancel: {
            guard gate.cancel() else { return }
            responsivenessSemaphore.signal()
            workSemaphore.signal()
        }
    }
}

private extension MainThreadProbe.Termination {
    var result: Result<MainThreadProbeOutcome, Error> {
        switch self {
        case .outcome(let outcome):
            .success(outcome)
        case .cancelled:
            .failure(CancellationError())
        }
    }
}

private extension MainThreadProbe {
    final class Gate: Sendable {
        private let phase = OSAllocatedUnfairLock(initialState: Phase.waitingForMain)

        func beginWork() -> Bool {
            phase.withLock { phase in
                guard case .waitingForMain = phase else { return false }
                phase = .waitingForWork
                return true
            }
        }

        func beginExecution() -> Bool {
            phase.withLock { phase in
                guard case .waitingForWork = phase else { return false }
                phase = .executingWork
                return true
            }
        }

        func complete() -> Bool {
            phase.withLock { phase in
                guard case .executingWork = phase else { return false }
                phase = .terminal(.outcome(.responsive))
                return true
            }
        }

        func cancel() -> Bool {
            phase.withLock { phase in
                if case .terminal = phase {
                    return false
                } else {
                    phase = .terminal(.cancelled)
                    return true
                }
            }
        }

        func timeoutWaitingForMain() -> Termination? {
            phase.withLock { phase in
                switch phase {
                case .waitingForMain:
                    let termination = Termination.outcome(.mainThreadUnresponsive)
                    phase = .terminal(termination)
                    return termination
                case .waitingForWork, .executingWork:
                    return nil
                case .terminal(let termination):
                    return termination
                }
            }
        }

        func timeoutWork() -> Termination {
            phase.withLock { phase in
                switch phase {
                case .waitingForMain:
                    let termination = Termination.outcome(.mainThreadUnresponsive)
                    phase = .terminal(termination)
                    return termination
                case .waitingForWork, .executingWork:
                    let termination = Termination.outcome(.workTimedOut)
                    phase = .terminal(termination)
                    return termination
                case .terminal(let termination):
                    return termination
                }
            }
        }

        var termination: Termination? {
            phase.withLock { phase in
                guard case .terminal(let termination) = phase else { return nil }
                return termination
            }
        }

        var requiredTermination: Termination {
            phase.withLock { phase in
                guard case .terminal(let termination) = phase else {
                    preconditionFailure("A signaled main-thread probe must be terminal")
                }
                return termination
            }
        }
    }
}
#endif
