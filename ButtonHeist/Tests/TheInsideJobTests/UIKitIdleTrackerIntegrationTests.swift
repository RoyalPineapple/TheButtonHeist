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
        tracker.beginOperationIfAvailable()
        defer { tracker.endOperationIfNeeded() }
        var completionRan = false

        UIView.animate(withDuration: 0.05, animations: {
            animatedView.frame.origin.x = 100
        }, completion: { _ in
            completionRan = true
        })

        let becameIdle = await tracker.waitUntilIdle(timeout: .seconds(1))
        XCTAssertTrue(becameIdle)
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

    func testRepeatingAnimationStartedInsideOperationUsesIdleTimeout() async throws {
        let window = UIWindow(windowScene: try requireForegroundWindowScene())
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
        let viewController = UIViewController()
        let animatedView = UIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        viewController.view.addSubview(animatedView)
        window.rootViewController = viewController
        window.isHidden = false
        window.layer.speed = 1
        defer { window.isHidden = true }

        let tracker = UIKitIdleTracker()
        try tracker.installIfNeeded()
        tracker.beginOperationIfAvailable()
        defer {
            tracker.endOperationIfNeeded()
            tracker.uninstallIfNeeded()
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

        let becameIdle = await tracker.waitUntilIdle(timeout: .milliseconds(100))

        let snapshot = try XCTUnwrap(tracker.operationSnapshot)
        XCTAssertFalse(becameIdle)
        XCTAssertGreaterThan(snapshot.observedStartCount, 0)
        XCTAssertLessThan(snapshot.matchedStopCount, snapshot.observedStartCount)
        XCTAssertGreaterThan(snapshot.activeCount, 0)
        XCTAssertTrue(tracker.isTrackingOperation)
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

        UIView.animate(withDuration: 0.05, animations: {
            animatedView.frame.origin.x = 100
        }, completion: { _ in
            DispatchQueue.main.async {
                animatedView.accessibilityLabel = "Ready"
            }
        })

        let becameIdle = await tripwire.uikitIdleTracker.waitUntilIdle(timeout: .seconds(1))
        XCTAssertTrue(becameIdle)
        XCTAssertEqual(animatedView.accessibilityLabel, "Ready")
        let settlement = await SettleSession.live(
            vault: vault,
            tripwire: tripwire,
            timeoutMs: 1_000,
            policy: .postIdleConfirmation
        ).run(
            start: RuntimeElapsed.now,
            baselineTripwireSignal: tripwire.tripwireSignal()
        )
        XCTAssertTrue(settlement.outcome.didSettleCleanly)
        XCTAssertTrue(tripwire.runningContext?.heartbeatWaiters.isEmpty == true)
        let labels = AccessibilityHierarchyParser()
            .parseAccessibilityHierarchy(in: viewController.view, rotorResultLimit: 0)
            .flattenToElements()
            .compactMap(\.label)
        XCTAssertTrue(labels.contains("Ready"))
        XCTAssertFalse(labels.contains("Loading"))
    }
}
#endif
