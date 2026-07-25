#if canImport(UIKit)
import UIKit
import XCTest
@testable import TheInsideJob

@MainActor
final class AnimationObserverIntegrationTests: XCTestCase {
    private var animationsWereEnabled = false

    override func setUp() async throws {
        try await super.setUp()
        animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(true)
    }

    override func tearDown() async throws {
        UIView.setAnimationsEnabled(animationsWereEnabled)
        try await super.tearDown()
    }

    func testInstalledSwizzleCountsLiveUIViewAnimationEdges() async throws {
        let previousKeyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let viewController = UIViewController()
        let animatedView = UIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        viewController.view.addSubview(animatedView)
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        window.layer.speed = 1
        defer {
            window.isHidden = true
            previousKeyWindow?.makeKey()
        }

        let observer = AnimationObserver()
        try observer.installIfNeeded()
        defer { observer.uninstallIfNeeded() }
        let tripwire = TheTripwire()
        tripwire.startPulse()
        defer { tripwire.stopPulse() }
        var completionRan = false

        UIView.animate(withDuration: 0.05, animations: {
            animatedView.frame.origin.x = 100
        }, completion: { _ in
            completionRan = true
        })

        let tick = await tripwire.waitForNextTick(
            timeout: .seconds(1),
            demand: .immediate
        )
        XCTAssertEqual(tick, .observed)
        XCTAssertGreaterThan(try XCTUnwrap(observer.animationSnapshot).observedStartCount, 0)
        XCTAssertTrue(
            completionRan,
            "The original UIKit stop implementation must still run under the swizzle"
        )
    }

    func testInstallIsIdempotentAndRestoresOnUninstall() throws {
        let observer = AnimationObserver()
        XCTAssertNil(observer.animationSnapshot)

        XCTAssertTrue(try observer.installIfNeeded())
        XCTAssertFalse(try observer.installIfNeeded())
        XCTAssertTrue(observer.isInstalled)
        XCTAssertNotNil(observer.animationSnapshot)

        XCTAssertTrue(observer.uninstallIfNeeded())
        XCTAssertFalse(observer.uninstallIfNeeded())
        XCTAssertFalse(observer.isInstalled)
        XCTAssertNil(observer.animationSnapshot)
    }

    func testAnimationSnapshotReadsWithoutAnyPriorRegistration() throws {
        let tripwire = TheTripwire()
        try tripwire.animationObserver.installIfNeeded()
        defer { tripwire.animationObserver.uninstallIfNeeded() }

        tripwire.animationObserver.observeAnimationStarted()

        let snapshot = try XCTUnwrap(tripwire.animationObserver.animationSnapshot)
        XCTAssertEqual(snapshot.activeCount, 1)
        XCTAssertEqual(snapshot.observedStartCount, 1)

        tripwire.animationObserver.observeAnimationStopped()
        XCTAssertEqual(try XCTUnwrap(tripwire.animationObserver.animationSnapshot).activeCount, 0)
    }

    func testCountTracksNestedStartAndStopEdges() throws {
        let observer = AnimationObserver()
        try observer.installIfNeeded()
        defer { observer.uninstallIfNeeded() }

        observer.observeAnimationStarted()
        observer.observeAnimationStarted()
        XCTAssertEqual(observer.observeAnimationStopped(), .active(remaining: 1))
        XCTAssertEqual(observer.observeAnimationStopped(), .becameIdle)

        let snapshot = try XCTUnwrap(observer.animationSnapshot)
        XCTAssertEqual(snapshot.activeCount, 0)
        XCTAssertEqual(snapshot.observedStartCount, 2)
        XCTAssertEqual(snapshot.matchedStopCount, 2)
        XCTAssertEqual(snapshot.unmatchedStopCount, 0)
    }

    func testUnmatchedStopClampsTheCountAtZero() throws {
        let observer = AnimationObserver()
        try observer.installIfNeeded()
        defer { observer.uninstallIfNeeded() }

        XCTAssertEqual(observer.observeAnimationStopped(), .unmatchedStop)

        let snapshot = try XCTUnwrap(observer.animationSnapshot)
        XCTAssertEqual(snapshot.activeCount, 0)
        XCTAssertEqual(snapshot.matchedStopCount, 0)
        XCTAssertEqual(snapshot.unmatchedStopCount, 1)
    }

    func testEachInstallationStartsAFreshCount() throws {
        let observer = AnimationObserver()
        try observer.installIfNeeded()
        observer.observeAnimationStarted()
        XCTAssertEqual(try XCTUnwrap(observer.animationSnapshot).observedStartCount, 1)
        observer.uninstallIfNeeded()

        try observer.installIfNeeded()
        defer { observer.uninstallIfNeeded() }
        XCTAssertEqual(try XCTUnwrap(observer.animationSnapshot).observedStartCount, 0)
    }
}
#endif
