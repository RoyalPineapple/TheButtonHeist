#if canImport(UIKit)
import CoreFoundation
import Foundation
import os

import TheScore

internal enum MainThreadProbe {
    internal enum Outcome: Sendable, Equatable {
        case completed
        case mainThreadUnresponsive
        case workTimedOut
    }

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

        fileprivate init(_ request: MainThreadProbeRequest) {
            responsiveness = Timeout(
                milliseconds: request.responsivenessTimeoutMilliseconds
            )
            work = Timeout(milliseconds: request.workTimeoutMilliseconds)
        }
    }

    internal typealias MainOperation = @MainActor @Sendable () -> Void

    private enum Phase: Sendable {
        case waitingForMain
        case runningWork
        case terminal(Outcome)
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
                operation()
                completion()
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
    ) async -> MainThreadProbeResponse {
        let outcome = await execute(timeouts: Timeouts(request), work: {})
        let responseOutcome: MainThreadProbeOutcome = switch outcome {
        case .completed:
            .responsive
        case .mainThreadUnresponsive:
            .mainThreadUnresponsive
        case .workTimedOut:
            .workTimedOut
        }
        return MainThreadProbeResponse(outcome: responseOutcome)
    }

    internal static func execute(
        timeouts: Timeouts,
        dependencies: Dependencies = .live,
        work: @escaping MainOperation
    ) async -> Outcome {
        let gate = Gate()
        let responsivenessSemaphore = DispatchSemaphore(value: 0)
        let workSemaphore = DispatchSemaphore(value: 0)

        dependencies.schedule {
            guard gate.beginWork() else { return }
            responsivenessSemaphore.signal()
            dependencies.executeWork(work) {
                guard gate.complete() else { return }
                workSemaphore.signal()
            }
        }

        return await withCheckedContinuation { continuation in
            dependencies.waitQueue.async {
                if dependencies.wait(
                    responsivenessSemaphore,
                    timeouts.responsiveness
                ) == .timedOut, let outcome = gate.timeoutWaitingForMain() {
                    continuation.resume(returning: outcome)
                    return
                }

                if dependencies.wait(workSemaphore, timeouts.work) == .timedOut {
                    continuation.resume(returning: gate.timeoutWork())
                    return
                }

                continuation.resume(returning: gate.terminalOutcome ?? gate.timeoutWork())
            }
        }
    }
}

private extension MainThreadProbe {
    final class Gate: Sendable {
        private let phase = OSAllocatedUnfairLock(initialState: Phase.waitingForMain)

        func beginWork() -> Bool {
            phase.withLock { phase in
                guard case .waitingForMain = phase else { return false }
                phase = .runningWork
                return true
            }
        }

        func complete() -> Bool {
            phase.withLock { phase in
                guard case .runningWork = phase else { return false }
                phase = .terminal(.completed)
                return true
            }
        }

        func timeoutWaitingForMain() -> Outcome? {
            phase.withLock { phase in
                switch phase {
                case .waitingForMain:
                    phase = .terminal(.mainThreadUnresponsive)
                    return .mainThreadUnresponsive
                case .runningWork:
                    return nil
                case .terminal(let outcome):
                    return outcome
                }
            }
        }

        func timeoutWork() -> Outcome {
            phase.withLock { phase in
                switch phase {
                case .waitingForMain:
                    phase = .terminal(.mainThreadUnresponsive)
                    return .mainThreadUnresponsive
                case .runningWork:
                    phase = .terminal(.workTimedOut)
                    return .workTimedOut
                case .terminal(let outcome):
                    return outcome
                }
            }
        }

        var terminalOutcome: Outcome? {
            phase.withLock { phase in
                guard case .terminal(let outcome) = phase else { return nil }
                return outcome
            }
        }
    }
}
#endif
