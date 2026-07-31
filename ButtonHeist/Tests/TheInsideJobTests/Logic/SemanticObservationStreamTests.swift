#if canImport(UIKit)
#if DEBUG
import Foundation
import XCTest

@testable import TheInsideJob
@testable import TheScore

@MainActor
final class SemanticObservationStreamTests: XCTestCase {
    private var vault: TheVault!

    override func setUp() async throws {
        vault = TheVault(tripwire: TheTripwire())
    }

    override func tearDown() async throws {
        vault.semanticObservationStream.stop()
        vault = nil
    }

    func testIdleStreamDoesNotReadAccessibility() {
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
        let historyIndex = vault.state.history.endIndex
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

    func testSubscriptionPublishesVaultHistoryInAuthoredOrder() async throws {
        let stream = vault.semanticObservationStream
        let beforeReceipt = await capturePublication(in: vault) {
            await stream.commitVisibleObservationForTesting(.empty)
        }
        let before = beforeReceipt.publication
        var received: [Observation.Event] = []

        let installation = stream.subscribe(
            scope: .visible,
            replayingAfter: 0,
            receive: { received.append($0) }
        )
        let subscription = installation.subscription
        received.append(contentsOf: try installation.replay.get())
        stream.discardCurrentObservation()
        let duringReceipt = await capturePublication(in: vault) {
            await stream.commitVisibleObservationForTesting(.empty)
        }
        let during = duringReceipt.publication
        let expected = before.events + during.events
        let current = vault.state.current
        let history = try stream.events(after: 0).get()

        XCTAssertEqual(received, expected)
        XCTAssertEqual(
            duringReceipt.historyRange,
            beforeReceipt.historyRange.upperBound..<(beforeReceipt.historyRange.upperBound + during.events.count)
        )
        XCTAssertEqual(current, during.current)
        XCTAssertEqual(history, expected)

        subscription.cancel()
        let afterCancellation = await stream.commitVisibleObservationForTesting(.empty)
        let currentAfterCancellation = vault.state.current
        let historyAfterCancellation = try stream.events(after: 0).get()

        XCTAssertEqual(received, expected)
        XCTAssertEqual(currentAfterCancellation, afterCancellation.current)
        XCTAssertEqual(historyAfterCancellation, expected + afterCancellation.events)
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
