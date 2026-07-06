#if canImport(UIKit)
#if DEBUG
import XCTest

@testable import TheInsideJob

final class SimpleSocketServerLifecycleMachineTests: XCTestCase {
    private let machine = SimpleSocketServerLifecycleMachine()

    func testBeginStartingMovesStoppedServerToStarting() {
        let attemptID = UUID()

        let change = machine.advance(.stopped, with: .beginStarting(attemptID))

        XCTAssertEqual(change.state, .starting(attemptID))
        XCTAssertTrue(change.effects.isEmpty)
    }

    func testBeginStartingRejectsRunningServer() {
        let change = machine.advance(.listening(port: 1234), with: .beginStarting(UUID()))

        XCTAssertEqual(change, .rejected(.alreadyRunning, stayingIn: .listening(port: 1234)))
    }

    func testFinishStartingPublishesPortForCurrentAttempt() {
        let attemptID = UUID()

        let change = machine.advance(.starting(attemptID), with: .finishStarting(attemptID, port: 2468))

        XCTAssertEqual(change.state, .listening(port: 2468))
        XCTAssertEqual(change.effects, [.publishPort(2468)])
    }

    func testFinishStartingRejectsStaleAttempt() {
        let currentID = UUID()
        let staleID = UUID()

        let change = machine.advance(.starting(currentID), with: .finishStarting(staleID, port: 2468))

        XCTAssertEqual(change, .rejected(.staleStartAttempt, stayingIn: .starting(currentID)))
    }

    func testFailStartingClearsPublishedPortForCurrentAttempt() {
        let attemptID = UUID()

        let change = machine.advance(.starting(attemptID), with: .failStarting(attemptID))

        XCTAssertEqual(change.state, .stopped)
        XCTAssertEqual(change.effects, [.clearPublishedPort])
    }

    func testStopWhileStartingClearsPortAndStopsRuntime() {
        let change = machine.advance(.starting(UUID()), with: .stop)

        XCTAssertEqual(change.state, .stopped)
        XCTAssertEqual(change.effects, [.clearPublishedPort, .stopRuntime])
    }

    func testStopWhileListeningClearsPortAndStopsRuntime() {
        let change = machine.advance(.listening(port: 2468), with: .stop)

        XCTAssertEqual(change.state, .stopped)
        XCTAssertEqual(change.effects, [.clearPublishedPort, .stopRuntime])
    }

    func testStopRejectsStoppedServer() {
        let change = machine.advance(.stopped, with: .stop)

        XCTAssertEqual(change, .rejected(.alreadyStopped, stayingIn: .stopped))
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
