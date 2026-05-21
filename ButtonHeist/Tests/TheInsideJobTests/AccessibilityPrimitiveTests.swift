#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser

final class AccessibilityPrimitiveTests: XCTestCase {

    func testTraitsKeepSetSemanticsAndCodableNames() throws {
        let traits: AccessibilityTraits = [.button, .selected, AccessibilityTraits(rawValue: 1 << 63)]

        XCTAssertTrue(traits.contains(.button))
        XCTAssertTrue(traits.contains(.selected))
        XCTAssertFalse(traits.contains(.header))

        let encoded = try JSONEncoder().encode(traits)
        let decoded = try JSONDecoder().decode(AccessibilityTraits.self, from: encoded)

        XCTAssertEqual(decoded, traits)
        XCTAssertTrue(decoded.traitNames.contains("button"))
        XCTAssertTrue(decoded.traitNames.contains("selected"))
    }

    func testGeometryAdaptersRoundTripCoreGraphicsValues() {
        let rect = CGRect(x: 10, y: 20, width: 30, height: 40)
        let portable = AccessibilityRect(rect)

        XCTAssertEqual(portable.cgRect, rect)
        XCTAssertEqual(portable.origin.cgPoint, rect.origin)
        XCTAssertEqual(portable.size.cgSize, rect.size)
    }

    func testShapeCodableUsesPortableGeometry() throws {
        let shape = AccessibilityShape.frame(AccessibilityRect(x: 1, y: 2, width: 3, height: 4))

        let decoded = try JSONDecoder().decode(
            AccessibilityShape.self,
            from: try JSONEncoder().encode(shape)
        )

        XCTAssertEqual(decoded, shape)
        guard case .frame(let rect) = decoded else {
            return XCTFail("Expected frame shape")
        }
        XCTAssertEqual(rect.cgRect, CGRect(x: 1, y: 2, width: 3, height: 4))
    }

    func testCustomActionEncodesAsActionName() throws {
        let action = AccessibilityElement.CustomAction("Share")

        let encoded = try JSONEncoder().encode(action)
        let value = try JSONDecoder().decode(String.self, from: encoded)

        XCTAssertEqual(value, "Share")
        let decoded = try JSONDecoder().decode(AccessibilityElement.CustomAction.self, from: encoded)
        XCTAssertEqual(decoded, "Share")
    }
}

#endif // canImport(UIKit)
