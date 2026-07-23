#if canImport(UIKit)
import AccessibilitySnapshotParser
import UIKit
import XCTest
@testable import TheInsideJob

@MainActor
final class UIKitIdleTrackerIntegrationTests: XCTestCase {
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

    func testUIViewAnimationCompletesRuntimeInstalledOperationIdleWait() async throws {
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

        let tracker = UIKitIdleTracker()
        try tracker.installIfNeeded()
        defer { tracker.uninstallIfNeeded() }
        let tripwire = TheTripwire()
        tripwire.startPulse()
        defer { tripwire.stopPulse() }
        var completionRan = false

        UIView.animate(withDuration: 0.05, animations: {
            animatedView.frame.origin.x = 100
        }, completion: { _ in
            completionRan = true
        })

        let heartbeat = await tripwire.waitForNextHeartbeat(
            timeout: .seconds(1),
            demand: .immediate
        )
        XCTAssertEqual(heartbeat, .observed)
        XCTAssertGreaterThan(try XCTUnwrap(tracker.animationSnapshot).observedStartCount, 0)
        tracker.beginOperationIfAvailable()
        defer { tracker.endOperationIfNeeded() }
        let becameIdle = await tracker.waitUntilIdle(timeout: .seconds(1))
        let remainsIdle = await tracker.waitUntilIdle(timeout: .zero)
        XCTAssertTrue(becameIdle)
        XCTAssertTrue(remainsIdle)
        XCTAssertTrue(completionRan, "The original UIKit stop implementation must run before idle is published")
    }

    func testRuntimeInstallationSurvivesConsecutiveOperationScopes() throws {
        let tracker = UIKitIdleTracker()
        XCTAssertTrue(try tracker.installIfNeeded())
        XCTAssertFalse(try tracker.installIfNeeded())
        XCTAssertTrue(tracker.isInstalled)

        tracker.beginOperationIfAvailable()
        XCTAssertTrue(tracker.isTrackingOperation)
        tracker.endOperationIfNeeded()
        XCTAssertTrue(tracker.isInstalled)
        XCTAssertFalse(tracker.isTrackingOperation)

        tracker.beginOperationIfAvailable()
        XCTAssertTrue(tracker.isTrackingOperation)
        tracker.endOperationIfNeeded()

        XCTAssertTrue(tracker.uninstallIfNeeded())
        XCTAssertFalse(tracker.uninstallIfNeeded())
        XCTAssertFalse(tracker.isInstalled)
    }

    func testRepeatingAnimationSettlesThroughAccessibilityQuietWindow() async throws {
        let window = UIWindow(windowScene: try requireForegroundWindowScene())
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
        let viewController = UIViewController()
        let animatedView = UIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        viewController.view.addSubview(animatedView)
        window.rootViewController = viewController
        window.isHidden = false
        window.layer.speed = 1
        defer { window.isHidden = true }

        let tripwire = TheTripwire()
        tripwire.startPulse()
        let vault = TheVault(tripwire: tripwire)
        try tripwire.uikitIdleTracker.installIfNeeded()
        tripwire.uikitIdleTracker.beginOperationIfAvailable()
        defer {
            tripwire.uikitIdleTracker.endOperationIfNeeded()
            tripwire.uikitIdleTracker.uninstallIfNeeded()
            tripwire.stopPulse()
        }

        UIView.animate(
            withDuration: 0.01,
            delay: 0,
            options: [.autoreverse, .repeat],
            animations: {
                animatedView.frame.origin.x = 100
            }
        )
        defer { animatedView.layer.removeAllAnimations() }

        let settlement = await SettleSession.live(
            vault: vault,
            tripwire: tripwire,
            timeoutMs: 500,
            policy: .uikitIdleOrQuietWindow(milliseconds: 60)
        ).run(
            start: RuntimeElapsed.now,
            baselineTripwireSignal: tripwire.tripwireSignal()
        )

        let snapshot = try XCTUnwrap(tripwire.uikitIdleTracker.animationSnapshot)
        XCTAssertTrue(settlement.outcome.didSettleCleanly)
        XCTAssertEqual(settlement.evidence, .accessibilityQuietWindow)
        XCTAssertGreaterThan(snapshot.observedStartCount, 0)
        XCTAssertLessThan(snapshot.matchedStopCount, snapshot.observedStartCount)
        XCTAssertGreaterThan(snapshot.activeCount, 0)
        XCTAssertTrue(tripwire.uikitIdleTracker.isTrackingOperation)
        let repeatingAnimationIsIdle = await tripwire.uikitIdleTracker.waitUntilIdle(timeout: .zero)
        XCTAssertFalse(repeatingAnimationIsIdle)
    }

    func testNestedActiveDemandsShareOutermostOperationScope() throws {
        let tripwire = TheTripwire()
        try tripwire.uikitIdleTracker.installIfNeeded()
        defer { tripwire.uikitIdleTracker.uninstallIfNeeded() }
        let vault = TheVault(tripwire: tripwire)

        let outerDemand = vault.semanticObservationStream.beginActiveObservationDemand()
        XCTAssertTrue(tripwire.uikitIdleTracker.isTrackingOperation)
        let nestedDemand = vault.semanticObservationStream.beginActiveObservationDemand()
        XCTAssertTrue(tripwire.uikitIdleTracker.isTrackingOperation)

        nestedDemand.cancel()
        XCTAssertTrue(tripwire.uikitIdleTracker.isTrackingOperation)
        outerDemand.cancel()
        XCTAssertFalse(tripwire.uikitIdleTracker.isTrackingOperation)
        XCTAssertTrue(tripwire.uikitIdleTracker.isInstalled)
    }

    func testParserSeesQueuedAccessibilityUpdateImmediatelyAfterIdle() async throws {
        let previousKeyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: try requireForegroundWindowScene())
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
        window.windowLevel = .alert + 80
        let viewController = UIViewController()
        viewController.view.accessibilityViewIsModal = true
        let animatedView = UIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        animatedView.isAccessibilityElement = true
        animatedView.accessibilityLabel = "Loading"
        animatedView.accessibilityTraits = .staticText
        viewController.view.addSubview(animatedView)
        window.rootViewController = viewController
        window.isHidden = false
        window.layer.speed = 1
        window.layoutIfNeeded()
        defer {
            window.isHidden = true
            previousKeyWindow?.makeKey()
        }

        let tripwire = TheTripwire()
        tripwire.startPulse()
        defer { tripwire.stopPulse() }
        let vault = TheVault(tripwire: tripwire)
        try tripwire.uikitIdleTracker.installIfNeeded()
        defer { tripwire.uikitIdleTracker.uninstallIfNeeded() }
        tripwire.uikitIdleTracker.beginOperationIfAvailable()
        defer { tripwire.uikitIdleTracker.endOperationIfNeeded() }

        let settlementStart = RuntimeElapsed.now
        UIView.animate(withDuration: 0.1, animations: {
            animatedView.frame.origin.x = 100
        }, completion: { _ in
            DispatchQueue.main.async {
                animatedView.accessibilityLabel = "Ready"
            }
        })

        let settlement = await SettleSession.live(
            vault: vault,
            tripwire: tripwire,
            timeoutMs: 1_000,
            policy: .uikitIdleOrQuietWindow(milliseconds: 500)
        ).run(
            start: settlementStart,
            baselineTripwireSignal: tripwire.tripwireSignal()
        )
        XCTAssertTrue(settlement.outcome.didSettleCleanly)
        XCTAssertEqual(settlement.evidence, .uikitIdle)
        XCTAssertEqual(
            animatedView.accessibilityLabel,
            "Ready",
            "Idle counter: \(String(describing: tripwire.uikitIdleTracker.animationSnapshot))"
        )
        XCTAssertTrue(tripwire.runningContext?.heartbeatWaiters.isEmpty == true)
        let labels = try XCTUnwrap(settlement.finalObservation)
            .tree.viewportCapture.hierarchy.sortedElements.compactMap(\.label)
        XCTAssertTrue(
            labels.contains("Ready"),
            "Settled labels: \(labels); idle counter: \(String(describing: tripwire.uikitIdleTracker.animationSnapshot))"
        )
        XCTAssertFalse(labels.contains("Loading"), "Settled labels: \(labels)")
    }
}
#endif
