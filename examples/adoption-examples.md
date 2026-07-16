# Adoption examples

These examples are for iOS DEBUG test targets that import
`ButtonHeistTesting`. They are intentionally shaped as normal test methods so
they can be pasted into an existing XCTest, Swift Testing, or KIF-style harness.

## KIF-style synchronous replacement

Use `runHeistSync` when the surrounding test target is synchronous and teardown
already assumes the main run loop stays under the test method's control.
Recording to an explicit directory makes the receipt artifact independent from
inherited environment variables:

```swift
import ButtonHeistTesting
import Foundation
import XCTest

final class CheckoutHeistTests: XCTestCase {
    func testCheckoutCompletes() {
        let receiptsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("buttonheist-receipts", isDirectory: true)

        runHeistSync("Checkout.pay", recordReceipt: .always, to: receiptsURL) {
            Activate(.label("Pay"))
                .expect(.changed(.elements([.appeared(.label("Payment Complete"))])))
        }
    }
}
```

## Bounded external takeover

Use `withJoinedHeistSession` when an external probe, CLI command, or agent needs
a live app session but the test must still finish. The closure owns the bounded
takeover window, and the helper stops the fresh `TheInsideJob` server when the
closure exits:

```swift
import ButtonHeistTesting
import XCTest

final class CheckoutProbeTests: XCTestCase {
    func testExternalProbeCanInspectCheckout() throws {
        logIn()
        navigateToCheckout()

        try withJoinedHeistSession(token: "checkout-probe") { session in
            try runCheckoutProbe(endpoint: session.endpoint, token: session.token)
        }
    }
}
```

Bare `joinHeist` is for manual parachute sessions only. It parks the test
forever while pumping the run loop, so do not add it to PR CI:

```swift
func test_PARACHUTE_manualCheckoutProbe() {
    logIn()
    navigateToCheckout()
    joinHeist(token: "manual-checkout-probe", port: 1456)
}
```

## Pairing with XCUITest for system dialogs

Button Heist runs in the app process and cannot see SpringBoard, permission
alerts, share sheets, Safari view content, or other process-owned surfaces. Pair
the tools by giving XCUITest the system UI and giving Button Heist the in-app
accessibility contract after the app has returned to an app-owned screen.

The XCUITest shell handles the permission alert:

```swift
import XCTest

final class LocationPermissionShellUITests: XCTestCase {
    func testGrantsLocationPermission() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing-location-permission"]
        app.launch()

        app.buttons["Request Location"].tap()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.alerts.buttons["Allow While Using App"].tap()

        XCTAssertTrue(app.staticTexts["Location Enabled"].waitForExistence(timeout: 5))
    }
}
```

The app-hosted Button Heist test asserts the app-owned screen. No Button Heist
command runs while the SpringBoard alert is visible:

```swift
import ButtonHeistTesting
import Foundation
import XCTest

final class LocationPermissionContractTests: XCTestCase {
    func testGrantedStateInAppAccessibilityContract() {
        seedLocationPermissionAsGranted()

        let receiptsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("buttonheist-receipts", isDirectory: true)

        runHeistSync("Permissions.location.granted", recordReceipt: .always, to: receiptsURL) {
            WaitFor(.exists(.label("Location Enabled")), timeout: 5)

            Activate(.label("Continue"))
                .expect(.changed(.elements([.appeared(.label("Map"))])))
        }
    }
}
```
