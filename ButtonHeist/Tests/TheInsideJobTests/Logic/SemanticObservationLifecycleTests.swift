#if canImport(UIKit)
#if DEBUG
import Foundation
import XCTest

@testable import TheInsideJob
@testable import TheScore

@MainActor
final class SemanticObservationLifecycleTests: XCTestCase {
    private var vault: TheVault!

    override func setUp() async throws {
        vault = TheVault(tripwire: TheTripwire())
    }

    override func tearDown() async throws {
        vault.semanticObservationStream.stop()
        vault = nil
    }

    func testLifecycleOwnsOnlyWhetherObservationIsRunning() async {
        var state = SemanticObservationLifecycle.stopped

        XCTAssertTrue(state.start())
        XCTAssertTrue(state.isRunning)
        XCTAssertFalse(state.start())
        XCTAssertTrue(state.stop())
        XCTAssertFalse(state.isRunning)
        XCTAssertFalse(state.stop())
    }

    func testStreamRunningTruthIsLifecycle() async {
        let stream = vault.semanticObservationStream
        XCTAssertFalse(stream.isActive)
        XCTAssertFalse(stream.lifecycle.isRunning)

        stream.start()
        XCTAssertTrue(stream.isActive)
        XCTAssertTrue(stream.lifecycle.isRunning)

        stream.stop()
        XCTAssertFalse(stream.isActive)
        XCTAssertFalse(stream.lifecycle.isRunning)
    }

    func testIdleStreamDoesNotReadAccessibility() async {
        let source = VisibleObservationSourceFixture()
        source.observation = .empty
        let tripwire = TheTripwire()
        let idleVault = TheVault(
            tripwire: tripwire,
            visibleObservationSource: source.capture
        )
        tripwire.startPulse()
        defer {
            idleVault.semanticObservationStream.stop()
            tripwire.stopPulse()
        }
        idleVault.semanticObservationStream.start()

        tripwire.onTick()
        tripwire.onTick()

        XCTAssertEqual(source.captureCount, 0)
    }

    func testDemandedPulseCommitsOneObservationCycle() async {
        let source = VisibleObservationSourceFixture()
        source.observation = .empty
        let tripwire = TheTripwire()
        let demandedVault = TheVault(
            tripwire: tripwire,
            visibleObservationSource: source.capture
        )
        tripwire.startPulse()
        defer {
            demandedVault.semanticObservationStream.stop()
            tripwire.stopPulse()
        }
        let stream = demandedVault.semanticObservationStream
        stream.start()
        let historyIndex = stream.historyEndIndex()
        let subscription = stream.subscribe(scope: .visible)
        defer { subscription.cancel() }

        tripwire.onTick()
        let result = await stream.waitForObservation(
            after: historyIndex,
            scope: .visible,
            boundary: .externalDeadline(SemanticObservationDeadline(
                start: RuntimeElapsed.now,
                timeout: .seconds(1)
            ))
        )

        guard case .observation = result else {
            return XCTFail("Expected one committed observation, got \(result)")
        }
        XCTAssertEqual(source.captureCount, 1)
    }

    func testDiscoveryDemandCapturesNextPulseAfterCycleCompletes() throws {
        var cycle = SemanticObservationCycle()
        _ = cycle.demand(scope: .discovery, pulseDemand: .ambient)

        XCTAssertEqual(
            try XCTUnwrap(cycle.receive(pulse(tick: 1, timestamp: 10))).pulse.tick,
            1
        )
        XCTAssertNil(cycle.receive(pulse(tick: 2, timestamp: 10.5)))
        cycle.complete()
        XCTAssertEqual(
            try XCTUnwrap(cycle.receive(pulse(tick: 3, timestamp: 11))).pulse.tick,
            3
        )
    }

    func testSubscriptionPublishesVaultHistoryInAuthoredOrder() async throws {
        let stream = vault.semanticObservationStream
        let before = await stream.commitVisibleObservationForTesting(.empty)
        var received: [Observation.Event] = []
        var historyError: Observation.History.ReadError?

        let subscription = stream.subscribe(
            scope: .visible,
            replayingAfter: 0,
            receive: { received.append($0) },
            historyUnavailable: { historyError = $0 }
        )
        stream.discardCurrentObservation()
        let during = await stream.commitVisibleObservationForTesting(.empty)
        let expected = before.events + during.events
        let current = stream.current()
        let history = try stream.events(after: 0).get()

        XCTAssertNil(historyError)
        XCTAssertEqual(received, expected)
        XCTAssertEqual(
            during.historyRange,
            before.historyRange.upperBound..<(before.historyRange.upperBound + during.events.count)
        )
        XCTAssertEqual(current, during.current)
        XCTAssertEqual(history, expected)

        subscription.cancel()
        let afterCancellation = await stream.commitVisibleObservationForTesting(.empty)
        let currentAfterCancellation = stream.current()
        let historyAfterCancellation = try stream.events(after: 0).get()

        XCTAssertEqual(received, expected)
        XCTAssertEqual(currentAfterCancellation, afterCancellation.current)
        XCTAssertEqual(historyAfterCancellation, expected + afterCancellation.events)
    }

    private func pulse(
        tick: UInt64,
        timestamp: CFAbsoluteTime = 0
    ) -> TheTripwire.PulseReading {
        TheTripwire.PulseReading(
            tick: tick,
            timestamp: timestamp,
            topmostVC: nil,
            tripwireSignal: .empty,
            windowCount: 0
        )
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
