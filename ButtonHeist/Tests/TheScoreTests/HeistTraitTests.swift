import XCTest
import ThePlans
@testable import TheScore

final class HeistTraitTests: XCTestCase {

    func testUnknownStringFailsDecode() throws {
        let json = Data(#""neverHeardOfIt""#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(HeistTrait.self, from: json)) { error in
            XCTAssertTrue("\(error)".contains("enum one of"))
        }
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
