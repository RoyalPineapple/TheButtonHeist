#if canImport(UIKit)
#if DEBUG
import Foundation
import XCTest

@testable import TheInsideJob

@MainActor
final class SemanticObservationCycleTests: XCTestCase {
    func testStopInvalidatesPriorCycleExecutionIdentity() {
        var execution = Observation.Stream.CycleExecutionOwnership<Int>()
        let staleIdentity = execution.begin { _ in 1 }

        XCTAssertEqual(execution.invalidate(), 1)

        let replacementIdentity = execution.begin { _ in 2 }
        XCTAssertNotEqual(staleIdentity, replacementIdentity)
        XCTAssertNil(execution.admitCompletion(for: staleIdentity))
        XCTAssertEqual(
            execution.admitCompletion(for: replacementIdentity),
            2
        )
    }

    func testStaleCompletionDoesNotRearmReplacementCycle() throws {
        var harness = CycleHarness()
        harness.start()

        let staleIdentity = try XCTUnwrap(harness.receive(pulse(tick: 1)))
        XCTAssertNil(harness.receive(pulse(tick: 2)))
        harness.stop()

        harness.start()
        let replacementIdentity = try XCTUnwrap(harness.receive(pulse(tick: 10)))
        XCTAssertNil(harness.receive(pulse(tick: 11)))

        XCTAssertFalse(harness.complete(staleIdentity))
        XCTAssertEqual(harness.claimedTicks, [1, 10])
        XCTAssertEqual(harness.acknowledgedTicks, [])
        XCTAssertNil(harness.receive(pulse(tick: 12)))

        XCTAssertTrue(harness.complete(replacementIdentity))
        XCTAssertEqual(harness.claimedTicks, [1, 10])
        XCTAssertEqual(harness.acknowledgedTicks, [10])

        XCTAssertFalse(harness.complete(replacementIdentity))
        XCTAssertEqual(harness.claimedTicks, [1, 10])
        XCTAssertEqual(harness.acknowledgedTicks, [10])

        XCTAssertNotNil(harness.receive(pulse(tick: 13)))
        XCTAssertEqual(harness.claimedTicks, [1, 10, 13])
    }

    func testBusyPulsesCannotStartSecondRequestUntilLaterPulse() throws {
        var cycle = SemanticObservationCycle()
        XCTAssertEqual(
            cycle.demand(scope: .visible, pulseDemand: .immediate),
            .immediate
        )

        let first = try XCTUnwrap(cycle.receive(pulse(tick: 1)))
        XCTAssertEqual(first.pulse.tick, 1)
        XCTAssertEqual(first.scope, .visible)
        XCTAssertNil(cycle.receive(pulse(tick: 2)))
        XCTAssertNil(cycle.receive(pulse(tick: 3)))

        cycle.complete()
        cycle.complete()

        let followUp = try XCTUnwrap(cycle.receive(pulse(tick: 4)))
        XCTAssertEqual(followUp.pulse.tick, 4)
        XCTAssertEqual(followUp.scope, .visible)
    }

    func testCompletionBecomesDormantWhenDemandEnds() throws {
        var cycle = SemanticObservationCycle()
        _ = cycle.demand(scope: .visible, pulseDemand: .immediate)

        XCTAssertEqual(
            try XCTUnwrap(cycle.receive(pulse(tick: 1))).pulse.tick,
            1
        )
        XCTAssertNil(cycle.demand(scope: nil, pulseDemand: .immediate))
        XCTAssertNil(cycle.receive(pulse(tick: 2)))

        cycle.complete()
        XCTAssertNil(cycle.receive(pulse(tick: 3)))

        _ = cycle.demand(scope: .discovery, pulseDemand: .ambient)
        let followUp = try XCTUnwrap(cycle.receive(pulse(tick: 4)))
        XCTAssertEqual(followUp.pulse.tick, 4)
        XCTAssertEqual(followUp.scope, .discovery)
    }

    func testZeroDemandIsInert() {
        var cycle = SemanticObservationCycle()

        XCTAssertNil(cycle.demand(scope: nil, pulseDemand: .immediate))
        XCTAssertNil(cycle.receive(pulse(tick: 1)))
        cycle.complete()
    }

    private struct CycleHarness {
        private struct Claim {
            let tick: UInt64
        }

        private var cycle = SemanticObservationCycle()
        private var execution = Observation.Stream.CycleExecutionOwnership<Claim>()
        private(set) var claimedTicks: [UInt64] = []
        private(set) var acknowledgedTicks: [UInt64] = []

        mutating func start() {
            _ = cycle.demand(scope: .visible, pulseDemand: .immediate)
        }

        mutating func stop() {
            _ = execution.invalidate()
            cycle.stop()
        }

        mutating func receive(
            _ pulse: TheTripwire.PulseReading
        ) -> Observation.Stream.CycleExecutionIdentity? {
            guard let request = cycle.receive(pulse) else { return nil }
            return begin(request)
        }

        mutating func complete(
            _ identity: Observation.Stream.CycleExecutionIdentity
        ) -> Bool {
            guard let claim = execution.admitCompletion(for: identity) else {
                return false
            }
            acknowledgedTicks.append(claim.tick)
            cycle.complete()
            return true
        }

        private mutating func begin(
            _ request: SemanticObservationCycle.Request
        ) -> Observation.Stream.CycleExecutionIdentity {
            let claim = Claim(tick: request.pulse.tick)
            claimedTicks.append(claim.tick)
            return execution.begin { _ in claim }
        }
    }

    private func pulse(tick: UInt64) -> TheTripwire.PulseReading {
        TheTripwire.PulseReading(
            tick: tick,
            timestamp: 0,
            topmostVC: nil,
            tripwireSignal: .empty,
            windowCount: 0
        )
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
