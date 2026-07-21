#if canImport(UIKit)
import AccessibilitySnapshotParser
import UIKit
import XCTest
@testable import TheInsideJob

@MainActor
final class HeistIdleTrackerIntegrationTests: XCTestCase {
    func testUIViewAnimationCompletesTheHeistScopedIdleWait() async throws {
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
        defer {
            window.isHidden = true
            previousKeyWindow?.makeKey()
        }

        let tracker = HeistIdleTracker()
        let lease = try tracker.beginTracking()
        defer { lease.cancel() }
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

    func testLeaseRestoresBothUIViewAnimationMethods() throws {
        let tracker = HeistIdleTracker()
        let firstLease = try tracker.beginTracking()
        XCTAssertTrue(tracker.isTracking)

        firstLease.cancel()
        XCTAssertFalse(tracker.isTracking)

        let secondLease = try tracker.beginTracking()
        XCTAssertTrue(tracker.isTracking)
        secondLease.cancel()
        XCTAssertFalse(tracker.isTracking)
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
        window.layoutIfNeeded()
        defer {
            window.isHidden = true
            previousKeyWindow?.makeKey()
        }

        let tripwire = TheTripwire()
        let lease = try tripwire.heistIdleTracker.beginTracking()
        defer { lease.cancel() }

        UIView.animate(withDuration: 0.05, animations: {
            animatedView.frame.origin.x = 100
        }, completion: { _ in
            DispatchQueue.main.async {
                animatedView.accessibilityLabel = "Ready"
            }
        })

        let becameIdle = await tripwire.heistIdleTracker.waitUntilIdle(timeout: .seconds(1))
        XCTAssertTrue(becameIdle)
        XCTAssertEqual(animatedView.accessibilityLabel, "Ready")
        let labels = AccessibilityHierarchyParser()
            .parseAccessibilityHierarchy(in: viewController.view, rotorResultLimit: 0)
            .flattenToElements()
            .compactMap(\.label)
        XCTAssertTrue(labels.contains("Ready"))
        XCTAssertFalse(labels.contains("Loading"))
    }
}
#endif
