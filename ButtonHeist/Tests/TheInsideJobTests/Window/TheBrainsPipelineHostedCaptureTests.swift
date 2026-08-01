#if canImport(UIKit)
import XCTest

@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import ThePlans
@_spi(ButtonHeistInternals) @testable import TheScore

@MainActor
final class TheBrainsPipelineHostedCaptureTests: XCTestCase {
    private var brains: TheBrains!

    override func setUp() async throws {
        try await super.setUp()
        brains = TheBrains(tripwire: TheTripwire())
    }

    override func tearDown() async throws {
        brains.vault.semanticObservationStream.stop()
        brains = nil
        try await super.tearDown()
    }

    func testExploreScreenStopsEarlyWhenTargetAlreadyResolved() async throws {
        brains.tripwire.startPulse()
        defer { brains.tripwire.stopPulse() }
        let screen = try XCTUnwrap(
            brains.vault.captureVisibleObservation(),
            "Expected a live hierarchy in the hosted test app"
        )
        await brains.vault.semanticObservationStream
            .commitVisibleObservationForTesting(screen)
        let label = try XCTUnwrap(
            screen.tree.viewportElementIDs
                .compactMap { screen.tree.findElement(heistId: $0)?.element.label }
                .first(where: { !$0.isEmpty }),
            "Expected a labeled viewport element in the hosted test app"
        )

        guard let exploration = await brains.navigation.exploreScreen(
            target: try AccessibilityTarget.label(label).resolve(in: .empty)
        ) else {
            return XCTFail("Expected target exploration to settle")
        }

        XCTAssertEqual(exploration.progress.scrollCount, 0)
        XCTAssertTrue(exploration.progress.pendingScrollPaths.isEmpty)
        XCTAssertTrue(exploration.progress.exploredScrollPaths.isEmpty)
    }
}

#endif
