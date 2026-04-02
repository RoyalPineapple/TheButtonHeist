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
        // 0.5s to avoid flakiness on CI where scheduling jitter can expire 0.2s prematurely
        let monitor = IdleMonitor(timeout: 0.5) {
            fired = true
        }
        monitor.resetTimer()
        try await Task.sleep(for: .seconds(0.1))
        monitor.resetTimer()
        try await Task.sleep(for: .seconds(0.1))
        XCTAssertFalse(fired)
        monitor.stop()
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
        monitor.stop()
        try await Task.sleep(for: .seconds(0.2))
        XCTAssertFalse(fired)
    }
}
