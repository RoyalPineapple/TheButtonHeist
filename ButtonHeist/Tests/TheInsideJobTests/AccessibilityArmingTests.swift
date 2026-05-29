#if canImport(UIKit)
import XCTest

@testable import TheInsideJob

final class AccessibilityArmingTests: XCTestCase {

    func testLibAccessibilityPathWithoutSimulatorRootIsAbsolute() {
        let path = libAccessibilityPath(environment: [:])
        XCTAssertEqual(path, "/usr/lib/libAccessibility.dylib")
    }

    func testLibAccessibilityPathPrefixesSimulatorRoot() {
        let path = libAccessibilityPath(environment: ["IPHONE_SIMULATOR_ROOT": "/sim/root"])
        XCTAssertEqual(path, "/sim/root/usr/lib/libAccessibility.dylib")
    }
}
#endif // canImport(UIKit)
