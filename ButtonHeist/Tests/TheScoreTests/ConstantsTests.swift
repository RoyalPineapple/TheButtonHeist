import XCTest
 import TheScore

final class ConstantsTests: XCTestCase {

    func testServiceType() {
        XCTAssertEqual(buttonHeistServiceType, "_buttonheist._tcp")
    }

    func testProtocolVersion() {
        XCTAssertEqual(protocolVersion, "6.4")
    }

    func testServiceTypeFormat() {
        // Verify the service type follows Bonjour naming conventions
        XCTAssertTrue(buttonHeistServiceType.hasPrefix("_"))
        XCTAssertTrue(buttonHeistServiceType.hasSuffix("._tcp"))
    }
}
