import XCTest
@testable import ButtonHeist

final class IdleMonitorTests: XCTestCase {

    @ButtonHeistActor
    func testTimeoutFiresAfterInactivity() async throws {
        let expectation = XCTestExpectation(description: "timeout fires")
        let monitor = IdleMonitor(timeout: 0.1) {
            expectation.fulfill()
        }
        monitor.resetTimer()
        await fulfillment(of: [expectation], timeout: 1.0)
    }

    @ButtonHeistActor
    func testResetPreventsTimeout() async throws {
        var fired = false
        let monitor = IdleMonitor(timeout: 0.2) {
            fired = true
        }
        monitor.resetTimer()
        try await Task.sleep(for: .seconds(0.1))
        monitor.resetTimer()
        try await Task.sleep(for: .seconds(0.1))
        XCTAssertFalse(fired)
        monitor.cancel()
    }

    @ButtonHeistActor
    func testZeroTimeoutNeverFires() async throws {
        var fired = false
        let monitor = IdleMonitor(timeout: 0) {
            fired = true
        }
        monitor.resetTimer()
        try await Task.sleep(for: .seconds(0.1))
        XCTAssertFalse(fired)
    }

    @ButtonHeistActor
    func testCancelStopsTimer() async throws {
        var fired = false
        let monitor = IdleMonitor(timeout: 0.1) {
            fired = true
        }
        monitor.resetTimer()
        monitor.cancel()
        try await Task.sleep(for: .seconds(0.2))
        XCTAssertFalse(fired)
    }
}
