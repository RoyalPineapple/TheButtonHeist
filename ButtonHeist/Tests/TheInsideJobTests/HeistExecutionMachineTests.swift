#if canImport(UIKit)
#if DEBUG
import XCTest

@testable import TheInsideJob
@testable import ThePlans
@testable import TheScore

final class HeistExecutionMachineTests: XCTestCase {
    func testMachineVocabularyIsPendingPerformPendingWaitOrComplete() throws {
        var waitMachine = try machine(command: notificationWait())
        assertWait(waitMachine.start())

        var actionMachine = try machine(command: notificationAction())
        assertDispatch(actionMachine.start(), id: operationID)

        let completion = actionMachine.externalCompletion(.completed)
        assertComplete(.complete(completion), id: operationID)
    }

    func testMachineInputVocabularyContainsOnlyEventsAndRequestCompletions() {
        let notification = notificationEvent()
        let dispatch = TheSafecracker.ActionDispatchResult.success(payload: .dismiss)
        let inputs: [HeistExecution.Input] = [
            .event(notification),
            .dispatchCompleted(operationID, dispatch),
            .viewportExited(operationID, .restored),
        ]

        XCTAssertEqual(inputs.map(inputKind), [
            "event",
            "dispatchCompleted",
            "viewportExited",
        ])
    }

    func testActionDispatchIsRequestedExactlyOnce() throws {
        var machine = try machine(command: notificationAction())
        var dispatchCount = 0

        dispatchCount += countDispatches(in: machine.start())
        dispatchCount += countDispatches(in: machine.advance(.event(notificationEvent())))
        dispatchCount += countDispatches(in: machine.advance(.event(notificationEvent())))
        dispatchCount += countDispatches(in: machine.advance(.dispatchCompleted(
            operationID,
            .success(payload: .dismiss)
        )))

        XCTAssertEqual(dispatchCount, 1)
    }

    func testOrderedEventsAdvanceTheExpectationOnceEach() throws {
        var machine = try machine(command: notificationWait())
        assertWait(machine.start())

        assertWait(machine.advance(.event(notificationEvent(text: "Not yet"))))
        assertWait(machine.advance(.event(notificationEvent())))
        assertFinishExploration(machine.advance(.event(.noChange)), id: operationID)
    }

    func testDispatchCompletionGatesSatisfiedActionExpectation() throws {
        var machine = try machine(command: notificationAction())
        assertDispatch(machine.start(), id: operationID)

        assertWait(machine.advance(.event(notificationEvent())))
        assertWait(machine.advance(.event(.noChange)))

        assertFinishExploration(
            machine.advance(.dispatchCompleted(
                operationID,
                .success(payload: .dismiss)
            )),
            id: operationID
        )
    }

    func testStaleRequestCompletionsDoNotAdvanceTheMachine() throws {
        var machine = try machine(command: notificationAction())
        assertDispatch(machine.start(), id: operationID)

        assertWait(machine.advance(.dispatchCompleted(
            staleOperationID,
            .success(payload: .dismiss)
        )))
        assertWait(machine.advance(.event(notificationEvent())))
        assertWait(machine.advance(.event(.noChange)))
        assertFinishExploration(
            machine.advance(.dispatchCompleted(
                operationID,
                .success(payload: .dismiss)
            )),
            id: operationID
        )

        assertWait(machine.advance(.viewportExited(staleOperationID, .restored)))
        assertComplete(
            machine.advance(.viewportExited(operationID, .restored)),
            id: operationID
        )
    }

    func testViewportCompletionProducesCompleteState() throws {
        var machine = try machine(command: notificationWait())
        assertWait(machine.start())
        assertWait(machine.advance(.event(notificationEvent())))
        assertFinishExploration(machine.advance(.event(.noChange)), id: operationID)

        let state = machine.advance(.viewportExited(operationID, .retained))

        assertComplete(state, id: operationID)
    }

    func testCompleteStateIsIdempotent() throws {
        var machine = try completedMachine()
        let completed = machine.state

        let states = [
            machine.advance(.event(notificationEvent(text: "Late"))),
            machine.advance(.dispatchCompleted(
                staleOperationID,
                .failure(.dismiss, message: "Late")
            )),
            machine.advance(.viewportExited(staleOperationID, .restored)),
        ]

        let expectedID = completionID(in: completed)
        XCTAssertEqual(expectedID, operationID)
        XCTAssertTrue(states.allSatisfy { completionID(in: $0) == expectedID })
    }
}

private extension HeistExecutionMachineTests {
    var operationID: HeistExecution.OperationID {
        HeistExecution.OperationID(rawValue: 7)
    }

    var staleOperationID: HeistExecution.OperationID {
        HeistExecution.OperationID(rawValue: 8)
    }

    func machine(
        command: HeistExecution.Command
    ) -> HeistExecution.Machine {
        HeistExecution.Machine(HeistExecution.Admission(
            id: operationID,
            command: command,
            baseline: .empty(timestamp: .distantPast),
            historyStartIndex: 0,
            startedAt: RuntimeElapsed.now
        ))
    }

    func completedMachine() throws -> HeistExecution.Machine {
        var machine = try machine(command: notificationWait())
        _ = machine.start()
        _ = machine.advance(.event(notificationEvent()))
        _ = machine.advance(.event(.noChange))
        _ = machine.advance(.viewportExited(operationID, .restored))
        return machine
    }

    func notificationWait() throws -> HeistExecution.Command {
        let predicate = try notificationPredicate()
        return .wait(predicate: predicate, timeout: .seconds(1))
    }

    func notificationAction() throws -> HeistExecution.Command {
        let predicate = try notificationPredicate()
        return .action(HeistExecution.ActionCommand(
            command: .dismiss,
            expectation: HeistExecution.ActionExpectation(
                authored: predicate.authored,
                resolved: predicate.resolved,
                timeout: 1
            ),
            readinessAllowance: .seconds(1)
        ))
    }

    func notificationPredicate() throws -> HeistExecution.Predicate {
        let authored = AccessibilityPredicate.notification("Saved")
        return HeistExecution.Predicate(
            authored: authored,
            resolved: try authored.resolve(in: HeistExecutionEnvironment())
        )
    }

    func notificationEvent(text: String = "Saved") -> Observation.Event {
        guard let notification = Observation.Notification(text: text, element: nil) else {
            preconditionFailure("A notification with text is valid")
        }
        return .notification(notification)
    }

    func inputKind(_ input: HeistExecution.Input) -> String {
        switch input {
        case .event:
            "event"
        case .dispatchCompleted:
            "dispatchCompleted"
        case .viewportExited:
            "viewportExited"
        }
    }

    func countDispatches(in state: HeistExecution.State) -> Int {
        switch state {
        case .pending(let action):
            switch action {
            case .perform(let requests):
                return requests.reduce(into: 0) { count, request in
                    if case .dispatch = request {
                        count += 1
                    }
                }
            case .wait:
                return 0
            }
        case .complete:
            return 0
        }
    }

    func completionID(
        in state: HeistExecution.State
    ) -> HeistExecution.OperationID? {
        switch state {
        case .pending(let action):
            switch action {
            case .perform, .wait:
                return nil
            }
        case .complete(let completion):
            return completion.id
        }
    }

    func assertDispatch(
        _ state: HeistExecution.State,
        id: HeistExecution.OperationID,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .pending(.perform(let requests)) = state,
              requests.count == 1,
              case .dispatch(let requestID, .dismiss) = requests[0] else {
            return XCTFail("Expected one dispatch request", file: file, line: line)
        }
        XCTAssertEqual(requestID, id, file: file, line: line)
    }

    func assertFinishExploration(
        _ state: HeistExecution.State,
        id: HeistExecution.OperationID,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .pending(.perform(let requests)) = state,
              requests.count == 1,
              case .finishExploration(let requestID) = requests[0] else {
            return XCTFail("Expected viewport finalization", file: file, line: line)
        }
        XCTAssertEqual(requestID, id, file: file, line: line)
    }

    func assertWait(
        _ state: HeistExecution.State,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .pending(.wait) = state else {
            return XCTFail("Expected pending wait", file: file, line: line)
        }
    }

    func assertComplete(
        _ state: HeistExecution.State,
        id: HeistExecution.OperationID,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .complete(let completion) = state else {
            return XCTFail("Expected completion", file: file, line: line)
        }
        XCTAssertEqual(completion.id, id, file: file, line: line)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
