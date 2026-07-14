#if canImport(UIKit)
import XCTest
@testable import ButtonHeistTesting

@MainActor
final class HeistSyncOperationTests: XCTestCase {
    func testWaitReturnsCompletedValueAndReleasesOwnedTask() {
        let state = HeistSyncState<Int>()
        state.attach(Task {})
        let waitControl = ManualHeistSyncWaitControl { state.finish(.success(42)) }

        let value = waitForSynchronousResult(
            state,
            timeout: 1,
            waitControl: waitControl.control,
            file: #filePath,
            line: #line
        )

        XCTAssertEqual(value, 42)
        XCTAssertFalse(state.ownsTask)
    }

    func testWaitReportsThrownFailureAndReleasesOwnedTask() {
        let state = HeistSyncState<Int>()
        state.attach(Task {})
        let waitControl = ManualHeistSyncWaitControl {
            state.finish(.failure(ExpectedHeistSyncError.failure))
        }
        let options = XCTExpectedFailure.Options()
        options.issueMatcher = { issue in
            issue.type == .assertionFailure
                && issue.compactDescription.contains("expected sync failure")
        }
        var value: Int?

        XCTExpectFailure("Thrown synchronous operations are reported through XCTest", options: options) {
            value = waitForSynchronousResult(
                state,
                timeout: 1,
                waitControl: waitControl.control,
                file: #filePath,
                line: #line
            )
        }

        XCTAssertNil(value)
        XCTAssertFalse(state.ownsTask)
    }

    func testWaitTimesOutAtInjectedDeadlineAndCancelsReleasedTask() {
        let state = HeistSyncState<Int>()
        let task = makeCancellableTask()
        state.attach(task)
        let waitControl = ManualHeistSyncWaitControl()
        let options = XCTExpectedFailure.Options()
        options.issueMatcher = { issue in
            issue.type == .assertionFailure
                && issue.compactDescription.contains(
                    "runHeistSyncOperation timed out after 0.25 seconds and cancelled its task"
                )
        }
        var value: Int?

        XCTExpectFailure("A bounded synchronous operation reports a dedicated timeout", options: options) {
            value = waitForSynchronousResult(
                state,
                timeout: 0.25,
                waitControl: waitControl.control,
                file: #filePath,
                line: #line
            )
        }

        XCTAssertNil(value)
        XCTAssertEqual(waitControl.elapsed, 0.25, accuracy: 0.000_001)
        XCTAssertTrue(task.isCancelled)
        XCTAssertFalse(state.ownsTask)
        guard case .timedOut = state.status else {
            return XCTFail("Expected the timeout to be terminal")
        }
    }

    func testNonPositiveAndNonFiniteBoundsTimeOutWithoutWaiting() {
        for timeout in [0, -1, .infinity, .nan] {
            let state = HeistSyncState<Int>()
            let task = makeCancellableTask()
            state.attach(task)
            let waitControl = ManualHeistSyncWaitControl()
            let options = XCTExpectedFailure.Options()
            options.issueMatcher = { issue in
                issue.type == .assertionFailure
                    && issue.compactDescription.contains("timed out after 0.0 seconds")
            }

            XCTExpectFailure("Invalid timeout bounds fail closed", options: options) {
                let value = waitForSynchronousResult(
                    state,
                    timeout: timeout,
                    waitControl: waitControl.control,
                    file: #filePath,
                    line: #line
                )
                XCTAssertNil(value)
            }

            XCTAssertEqual(waitControl.waitCount, 0)
            XCTAssertTrue(task.isCancelled)
            XCTAssertFalse(state.ownsTask)
        }
    }

    func testCompletionAtDeadlineWinsOverTimeout() {
        let state = HeistSyncState<Int>()
        state.attach(Task {})
        state.finish(.success(7))

        switch state.resolveDeadline() {
        case .completed(.success(let value)):
            XCTAssertEqual(value, 7)
        case .completed(.failure(let error)):
            XCTFail("Unexpected failure: \(error)")
        case .timedOut:
            XCTFail("A result published before deadline resolution must win")
        }
        XCTAssertFalse(state.ownsTask)
    }

    func testLateCompletionCannotReplaceTimeout() {
        let state = HeistSyncState<Int>()
        let task = makeCancellableTask()
        state.attach(task)

        guard case .timedOut(let ownedTask) = state.resolveDeadline() else {
            return XCTFail("Expected deadline resolution to time out")
        }
        ownedTask?.cancel()
        state.finish(.success(99))

        XCTAssertTrue(task.isCancelled)
        XCTAssertFalse(state.ownsTask)
        guard case .timedOut = state.status else {
            return XCTFail("Late completion must not replace the terminal timeout")
        }
    }

    private func makeCancellableTask() -> Task<Void, Never> {
        Task {
            while !Task.isCancelled {
                await Task.yield()
            }
        }
    }
}

private enum ExpectedHeistSyncError: Error, CustomStringConvertible {
    case failure

    var description: String {
        "expected sync failure"
    }
}

private final class ManualHeistSyncWaitControl {
    private(set) var elapsed: TimeInterval = 0
    private(set) var waitCount = 0
    private var onFirstWait: (() -> Void)?

    init(onFirstWait: (() -> Void)? = nil) {
        self.onFirstWait = onFirstWait
    }

    var control: HeistSyncWaitControl {
        HeistSyncWaitControl(
            now: { [unowned self] in elapsed },
            wait: { [unowned self] maximumInterval in
                elapsed += maximumInterval
                waitCount += 1
                let action = onFirstWait
                onFirstWait = nil
                action?()
            }
        )
    }
}
#endif // canImport(UIKit)
