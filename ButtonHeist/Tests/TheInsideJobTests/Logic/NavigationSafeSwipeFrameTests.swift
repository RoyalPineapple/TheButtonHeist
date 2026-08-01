#if canImport(UIKit)
import UIKit
import XCTest

@testable import AccessibilitySnapshotParser
@testable import TheInsideJob

@MainActor
final class NavigationSafeSwipeFrameTests: XCTestCase {
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

    func testSafeSwipeFrameFullyInSafeBoundsIsUnchanged() async throws {
        let screenBounds = ScreenMetrics.current.bounds
        let input = screenBounds.insetBy(dx: 80, dy: 120)
        XCTAssertEqual(try XCTUnwrap(brains.navigation.safeSwipeFrame(from: input)), input)
    }

    func testSafeSwipeFrameZeroWidthReturnsNil() async {
        XCTAssertNil(brains.navigation.safeSwipeFrame(from: CGRect(x: 0, y: 0, width: 0, height: 100)))
    }

    func testSafeSwipeFrameFullyOffscreenReturnsNil() async {
        XCTAssertNil(brains.navigation.safeSwipeFrame(from: CGRect(x: -500, y: -500, width: 100, height: 100)))
    }

    func testSafeSwipeFrameOversizedFrameClampsWithinScreen() async throws {
        let result = try XCTUnwrap(
            brains.navigation.safeSwipeFrame(from: CGRect(x: -1_000, y: -1_000, width: 10_000, height: 10_000))
        )
        XCTAssertTrue(ScreenMetrics.current.bounds.contains(result))
    }

    func testSafeSwipeFrameClampsAboveTabBarContainer() async throws {
        let tabBarFrame = CGRect(x: 0, y: 700, width: 400, height: 80)
        let tabBar = AccessibilityContainer(type: .tabBar, frame: AccessibilityRect(tabBarFrame))
        await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            InterfaceObservation.makeForTests(
                elements: [:],
                hierarchy: [.container(tabBar, children: [])],
                firstResponderHeistId: nil
            )
        )

        let result = try XCTUnwrap(
            brains.navigation.safeSwipeFrame(from: CGRect(x: 100, y: 400, width: 200, height: 500))
        )
        XCTAssertEqual(result.maxY, tabBarFrame.minY)
    }
}

#endif
