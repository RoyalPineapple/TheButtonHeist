import Foundation
import XCTest

@testable import ButtonHeist

final class PublicJSONInputLimitsTests: XCTestCase {

    func testValidateArrayAcceptsValuesWithinRemainingLimits() {
        let json = #"["alpha","beta","gamma"]"#

        XCTAssertNoThrow(try PublicJSONInputPreflight.validateArray(
            Data(json.utf8),
            maxBytes: 32,
            maxNestingDepth: 2,
            maxTotalObjectKeys: 0
        ))
    }

    func testValidateObjectAcceptsStringWithinRemainingLimits() {
        let json = #"{"text":"alpha beta"}"#

        XCTAssertNoThrow(try PublicJSONInputPreflight.validateObject(
            json,
            maxBytes: 32,
            maxNestingDepth: 2,
            maxTotalObjectKeys: 1
        ))
    }

}
