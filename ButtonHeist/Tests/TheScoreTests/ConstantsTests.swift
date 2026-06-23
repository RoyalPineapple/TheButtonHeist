import XCTest
import TheScore

final class ConstantsTests: XCTestCase {

    func testServiceType() {
        XCTAssertEqual(buttonHeistServiceType, "_buttonheist._tcp")
    }

    func testServiceTypeFormat() {
        // Verify the service type follows Bonjour naming conventions
        XCTAssertTrue(buttonHeistServiceType.hasPrefix("_"))
        XCTAssertTrue(buttonHeistServiceType.hasSuffix("._tcp"))
    }

    func testWireFrameLimitsExposeCurrentDirectionalCaps() {
        XCTAssertEqual(WireFrameLimits.newlineDelimiterByte, 0x0A)
        XCTAssertEqual(WireFrameLimits.receiveChunkBytes, 65_536)
        XCTAssertEqual(WireFrameLimits.clientToServerMaxBufferedBytes, 10_000_000)
        XCTAssertEqual(WireFrameLimits.serverToClientMaxBufferedBytes, 64 * 1024 * 1024)
        XCTAssertEqual(WireFrameLimits.serverToClientMaxPendingSendBytes, 20_000_000)
        XCTAssertGreaterThan(
            WireFrameLimits.serverToClientMaxBufferedBytes,
            WireFrameLimits.clientToServerMaxBufferedBytes,
            "Server-to-client buffering intentionally preserves the larger legacy client cap."
        )
    }
}
