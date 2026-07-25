#if canImport(UIKit)
import Foundation
import XCTest

@testable import TheInsideJob
@testable import TheScore

final class AccessibilityNotificationCaptureStateTests: XCTestCase {
    func testCaptureStateIsDerivedFromEveryLifecycleCase() {
        let expectations: [(AccessibilityNotificationObserverLifecycleState, AccessibilityNotificationCaptureState)] = [
            (.unsubscribed, .unsubscribed),
            (.subscribed(callbackInstalled: true, unitTestModeArmed: true), .capturing(armed: true)),
            (.subscribed(callbackInstalled: true, unitTestModeArmed: false), .capturing(armed: false)),
            (.subscribed(callbackInstalled: false, unitTestModeArmed: false), .installationUnavailable),
            (.subscribed(callbackInstalled: false, unitTestModeArmed: true), .installationUnavailable),
        ]

        for (lifecycleState, expected) in expectations {
            XCTAssertEqual(lifecycleState.captureState, expected, "\(lifecycleState)")
        }
    }

    @MainActor
    func testFailedCallbackInstallIsReportedAsInstallationUnavailable() {
        struct InstallFailure: Error {}
        let observer = AccessibilityNotificationObserver(
            installCallbackForTesting: { throw InstallFailure() },
            uninstallCallbackForTesting: {}
        )
        let bus = AccessibilityNotificationBus()

        observer.subscribe(bus)

        XCTAssertEqual(observer.lifecycleState.captureState, .installationUnavailable)
    }

    @MainActor
    func testUnarmedUnitTestModeIsReportedSeparatelyFromAFailedInstall() {
        let observer = AccessibilityNotificationObserver(
            installCallbackForTesting: {},
            uninstallCallbackForTesting: {},
            unitTestModeArmedForTesting: false
        )
        let bus = AccessibilityNotificationBus()

        observer.subscribe(bus)

        XCTAssertEqual(observer.lifecycleState.captureState, .capturing(armed: false))
    }

    @MainActor
    func testAnUnsubscribedObserverReportsUnsubscribedNotAHealthyCapture() {
        let observer = AccessibilityNotificationObserver(
            installCallbackForTesting: {},
            uninstallCallbackForTesting: {}
        )

        XCTAssertEqual(observer.lifecycleState.captureState, .unsubscribed)
    }

    func testNonStringNotificationsAreSurfacedWhereAnnouncementsDropThem() {
        let bus = AccessibilityNotificationBus()

        bus.recordForTesting(
            code: 1001,
            notificationData: .none,
            associatedElement: .none
        )
        bus.recordForTesting(
            code: 1000,
            notificationData: CapturedAccessibilityNotificationPayload(NSObject()),
            associatedElement: .none
        )
        bus.recordForTesting(
            code: 1008,
            notificationData: CapturedAccessibilityNotificationPayload("Saved" as NSString),
            associatedElement: .none
        )

        // The string-only projection drops the first two events entirely.
        XCTAssertEqual(bus.announcements().map(\.text), ["Saved"])

        let notifications = bus.notifications()
        XCTAssertEqual(
            notifications.map(\.kind),
            [.elementChanged(.layout), .screenChanged, .announcement]
        )
        XCTAssertEqual(notifications.compactMap(\.capturedAnnouncement).map(\.text), ["Saved"])
    }
}
#endif // canImport(UIKit)
