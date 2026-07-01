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

    private func environment(_ values: [AccessibilityEnvironmentKey: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value) })
    }
}
#endif // canImport(UIKit)
