import XCTest
@testable import TheScore

final class HeistTraitTests: XCTestCase {

    func testUnknownCaseRoundTrip() throws {
        let unknown = HeistTrait.unknown("futureTrait")
        let data = try JSONEncoder().encode(unknown)
        let decoded = try JSONDecoder().decode(HeistTrait.self, from: data)
        XCTAssertEqual(decoded, unknown)
    }

    func testUnknownStringDecodesToUnknown() throws {
        let json = Data(#""neverHeardOfIt""#.utf8)
        let decoded = try JSONDecoder().decode(HeistTrait.self, from: json)
        XCTAssertEqual(decoded, .unknown("neverHeardOfIt"))
    }

    func testKnownStringDecodesToKnownCase() throws {
        let json = Data(#""button""#.utf8)
        let decoded = try JSONDecoder().decode(HeistTrait.self, from: json)
        XCTAssertEqual(decoded, .button)
    }

    func testUnknownRawValueReturnsNil() {
        XCTAssertNil(HeistTrait(rawValue: "futureTrait"))
    }

}
