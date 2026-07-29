#if canImport(UIKit)
#if DEBUG
import Foundation
import XCTest

@testable import TheInsideJob

@MainActor
final class SemanticObservationCycleTests: XCTestCase {
    func testBusyPulsesCoalesceToLatestPendingPulse() throws {
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

        let followUp = try XCTUnwrap(cycle.complete())
        XCTAssertEqual(followUp.pulse.tick, 3)
        XCTAssertEqual(followUp.scope, .visible)
        XCTAssertNil(cycle.complete())
    }

    func testZeroDemandIsInert() {
        var cycle = SemanticObservationCycle()

        XCTAssertNil(cycle.demand(scope: nil, pulseDemand: .immediate))
        XCTAssertNil(cycle.receive(pulse(tick: 1)))
        XCTAssertNil(cycle.complete())
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
