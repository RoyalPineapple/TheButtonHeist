#if canImport(UIKit)
// Integration tests for TheTripwire that depend on wall-clock timing (CADisplayLink).
// These require a live UIWindowScene test host and real time passing.
import ButtonHeistSupport
import XCTest
@testable import TheInsideJob

@MainActor
final class TripwireIntegrationTests: XCTestCase {

    private var tripwire: TheTripwire!

    override func setUp() async throws {
        tripwire = TheTripwire()
        tripwire.startPulse()
    }

    override func tearDown() async throws {
        tripwire.stopPulse()
        tripwire = nil
    }

    // MARK: - Heartbeat waiters

    func testNextHeartbeatIsUnavailableWithoutRuntimePulse() async {
        let isolatedTripwire = TheTripwire()

        let outcome = await isolatedTripwire.waitForNextTick(
            timeout: .seconds(1),
            demand: .immediate
        )

        XCTAssertEqual(outcome, .unavailable)
    }

    func testNextHeartbeatObservesFuturePulseAndRestoresAmbientRate() async throws {
        let context = try XCTUnwrap(tripwire.runningContext)
        let ambientRate = context.link.preferredFrameRateRange

        let outcome = await tripwire.waitForNextTick(
            timeout: .seconds(1),
            demand: .immediate
        )

        XCTAssertEqual(outcome, .observed)
        XCTAssertTrue(context.tickWaiters.isEmpty)
        XCTAssertEqual(context.link.preferredFrameRateRange, ambientRate)
    }

    func testNextHeartbeatCancellationRemovesWaiterAndRestoresAmbientRate() async throws {
        let context = try XCTUnwrap(tripwire.runningContext)
        let ambientRate = context.link.preferredFrameRateRange
        context.link.isPaused = true
        defer { context.link.isPaused = false }
        let task = Task { @MainActor in
            await self.tripwire.waitForNextTick(
                timeout: .seconds(1),
                demand: .immediate
            )
        }

        for _ in 0..<20 where context.tickWaiters.isEmpty {
            await Task.yield()
        }
        XCTAssertEqual(context.tickWaiters.count, 1)
        XCTAssertNotEqual(context.link.preferredFrameRateRange, ambientRate)

        task.cancel()
        let outcome = await task.value

        XCTAssertEqual(outcome, .cancelled)
        XCTAssertTrue(context.tickWaiters.isEmpty)
        XCTAssertEqual(context.link.preferredFrameRateRange, ambientRate)
    }

    func testStoppingPulseResolvesTickWaiterAsUnavailable() async throws {
        let context = try XCTUnwrap(tripwire.runningContext)
        context.link.isPaused = true
        let task = Task { @MainActor in
            await self.tripwire.waitForNextTick(
                timeout: .seconds(1),
                demand: .immediate
            )
        }

        for _ in 0..<20 where context.tickWaiters.isEmpty {
            await Task.yield()
        }
        XCTAssertEqual(context.tickWaiters.count, 1)

        tripwire.stopPulse()
        let outcome = await task.value

        XCTAssertEqual(outcome, .unavailable)
        XCTAssertTrue(context.tickWaiters.isEmpty)
    }

    func testImmediateHeartbeatRateUsesScreenMaximum() {
        let range = TheTripwire.activeDisplayFrameRateRange(maximumFramesPerSecond: 120)

        XCTAssertEqual(range.minimum, 120)
        XCTAssertEqual(range.maximum, 120)
        XCTAssertEqual(range.preferred, 120)
    }

    // MARK: - Pulse produces readings

    func testPulseProducesReadingAfterStart() async throws {
        await observeTick()
        let reading = try XCTUnwrap(tripwire.latestReading)
        XCTAssertGreaterThan(reading.tick, 0)
    }

    func testPulseReadingHasValidWindowCount() async throws {
        await observeTick()
        let reading = try XCTUnwrap(tripwire.latestReading, "No reading produced")
        XCTAssertGreaterThan(reading.windowCount, 0)
    }

    func testPulseReadingTracksVCIdentity() async throws {
        await observeTick()
        let reading = try XCTUnwrap(tripwire.latestReading, "No reading produced")
        // Test host should have a VC
        XCTAssertNotNil(reading.topmostVC)
    }

    /// Await one tick of the caller-owned pulse — an observable signal that a
    /// reading has been produced, rather than a wall-clock sleep.
    private func observeTick(
        timeout: Duration = .seconds(1),
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let outcome = await tripwire.waitForNextTick(timeout: timeout, demand: .ambient)
        XCTAssertEqual(
            outcome,
            .observed,
            "Pulse should tick within timeout; \(latestPulseDiagnostic())",
            file: file,
            line: line
        )
    }

    private func latestPulseDiagnostic() -> String {
        guard let reading = tripwire.latestReading else {
            return "pulseRunning=\(tripwire.isPulseRunning) latestReading=nil"
        }
        return [
            "pulseRunning=\(tripwire.isPulseRunning)",
            "tick=\(reading.tick)",
            "windowCount=\(reading.windowCount)",
            "topmostVC=\(String(describing: reading.topmostVC))",
        ].joined(separator: " ")
    }

}

#endif // canImport(UIKit)
