import XCTest
@testable import TheScore

final class GroupTypeTests: XCTestCase {

    func testKnownCaseRoundTrip() throws {
        for groupType in GroupType.allCases {
            let data = try JSONEncoder().encode(groupType)
            let decoded = try JSONDecoder().decode(GroupType.self, from: data)
            XCTAssertEqual(decoded, groupType)
        }
    }

    func testUnknownCaseRoundTrip() throws {
        let unknown = GroupType.unknown("futureType")
        let data = try JSONEncoder().encode(unknown)
        let decoded = try JSONDecoder().decode(GroupType.self, from: data)
        XCTAssertEqual(decoded, unknown)
    }

    func testUnknownStringDecodesToUnknown() throws {
        let json = Data(#""neverHeardOfIt""#.utf8)
        let decoded = try JSONDecoder().decode(GroupType.self, from: json)
        XCTAssertEqual(decoded, .unknown("neverHeardOfIt"))
    }

    func testKnownStringDecodesToKnownCase() throws {
        let json = Data(#""list""#.utf8)
        let decoded = try JSONDecoder().decode(GroupType.self, from: json)
        XCTAssertEqual(decoded, .list)
    }

    func testRawValueRoundTrip() {
        for groupType in GroupType.allCases {
            let raw = groupType.rawValue
            let recovered = GroupType(rawValue: raw)
            XCTAssertEqual(recovered, groupType)
        }
    }

    func testUnknownRawValueReturnsNil() {
        XCTAssertNil(GroupType(rawValue: "futureType"))
    }

    /// Pin the literal wire strings — these are the contract with every client.
    /// A failure here means a case was renamed without bumping the protocol.
    func testKnownCaseWireStrings() {
        XCTAssertEqual(GroupType.semanticGroup.rawValue, "semanticGroup")
        XCTAssertEqual(GroupType.list.rawValue, "list")
        XCTAssertEqual(GroupType.landmark.rawValue, "landmark")
        XCTAssertEqual(GroupType.dataTable.rawValue, "dataTable")
        XCTAssertEqual(GroupType.tabBar.rawValue, "tabBar")
        XCTAssertEqual(GroupType.scrollable.rawValue, "scrollable")
    }
}
