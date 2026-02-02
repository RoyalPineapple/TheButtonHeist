import XCTest
@testable import AccraCore

final class ConstantsTests: XCTestCase {

    func testServiceType() {
        XCTAssertEqual(accraServiceType, "_a11ybridge._tcp")
    }

    func testProtocolVersion() {
        XCTAssertEqual(protocolVersion, "2.0")
    }

    func testServiceTypeFormat() {
        // Verify the service type follows Bonjour naming conventions
        XCTAssertTrue(accraServiceType.hasPrefix("_"))
        XCTAssertTrue(accraServiceType.hasSuffix("._tcp"))
    }
}
