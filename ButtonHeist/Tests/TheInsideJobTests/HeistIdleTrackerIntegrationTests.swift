#if canImport(UIKit)
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
}
#endif
