#if canImport(UIKit)
import XCTest

@testable import TheInsideJob

final class AccessibilityArmingTests: XCTestCase {

    func testLibAccessibilityPathWithoutSimulatorRootIsAbsolute() {
        let path = libAccessibilityPath(environment: [:])
        XCTAssertEqual(path, "/usr/lib/libAccessibility.dylib")
    }

    func testLibAccessibilityPathPrefixesSimulatorRoot() {
        let path = libAccessibilityPath(environment: environment([.iPhoneSimulatorRoot: "/sim/root"]))
        XCTAssertEqual(path, "/sim/root/usr/lib/libAccessibility.dylib")
    }

    func testUIAccessibilityCandidatePathsIncludeKnownInstallNamesAndSimulatorRoots() {
        let paths = AccessibilityNotificationObserver.uiAccessibilityCandidatePaths(environment: [
            AccessibilityEnvironmentKey.iPhoneSimulatorRoot.rawValue: "/iphone/root",
            "SIMULATOR_ROOT": "/sim/root",
            "DYLD_ROOT_PATH": "/dyld/root",
        ])

        XCTAssertTrue(paths.contains("/System/Library/PrivateFrameworks/UIAccessibility.framework/UIAccessibility"))
        XCTAssertTrue(paths.contains("/System/Library/PrivateFrameworks/UIKitCore.framework/UIKitCore"))
        XCTAssertTrue(paths.contains("/System/Library/Frameworks/UIKit.framework/UIKit"))
        XCTAssertTrue(
            paths.contains(
                "/iphone/root/System/Library/PrivateFrameworks/UIAccessibility.framework/UIAccessibility"
            )
        )
        XCTAssertTrue(
            paths.contains(
                "/sim/root/System/Library/PrivateFrameworks/UIAccessibility.framework/UIAccessibility"
            )
        )
        XCTAssertTrue(
            paths.contains(
                "/dyld/root/System/Library/PrivateFrameworks/UIAccessibility.framework/UIAccessibility"
            )
        )
    }

    private func environment(_ values: [AccessibilityEnvironmentKey: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value) })
    }
}
#endif // canImport(UIKit)
