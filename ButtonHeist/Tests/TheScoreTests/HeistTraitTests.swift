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

    func testIsExtendedPrivate() {
        let extendedCases: [HeistTrait] = [
            .webContent, .pickerElement, .radioButton, .launchIcon, .statusBarElement,
            .secureTextField, .inactive, .footer, .autoCorrectCandidate, .deleteKey,
            .selectionDismissesItem, .visited, .spacer, .tableIndex, .map,
            .textOperationsAvailable, .draggable, .popupButton, .menuItem, .alert,
        ]
        for trait in extendedCases {
            XCTAssertTrue(trait.isExtendedPrivate, "\(trait) should be extended private")
        }

        let nonExtended: [HeistTrait] = [
            .button, .link, .image, .staticText, .header, .adjustable,
            .textEntry, .isEditing, .backButton, .tabBarItem, .textArea, .switchButton,
        ]
        for trait in nonExtended {
            XCTAssertFalse(trait.isExtendedPrivate, "\(trait) should not be extended private")
        }
    }
}
