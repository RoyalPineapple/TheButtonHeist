import XCTest
@testable import TheScore

/// Wire-shape tests for the two additive auto-settle fields:
/// `ActionResult.settled` / `settleTimeMs` and
/// `InterfaceDelta.transient`. Old payloads without these fields decode
/// cleanly — that's the entire backward-compat contract.
final class AutoSettleFieldsTests: XCTestCase {

    // MARK: - ActionResult

    func testActionResultRoundTripsWithSettleFields() throws {
        let result = ActionResult(
            success: true,
            method: .activate,
            settled: true,
            settleTimeMs: 1234
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)
        XCTAssertEqual(decoded.settled, true)
        XCTAssertEqual(decoded.settleTimeMs, 1234)
    }

    func testOldActionResultWithoutSettleFieldsDecodes() throws {
        let jsonString = """
        {"success": true, "method": "activate"}
        """
        let decoded = try JSONDecoder().decode(ActionResult.self, from: Data(jsonString.utf8))
        XCTAssertNil(decoded.settled)
        XCTAssertNil(decoded.settleTimeMs)
    }

    // MARK: - InterfaceDelta.transient

    func testInterfaceDeltaRoundTripsWithTransient() throws {
        let element = HeistElement(
            heistId: "loading",
            description: "Loading",
            label: "Processing",
            value: nil,
            identifier: nil,
            traits: [.staticText],
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 30,
            actions: []
        )
        let delta = InterfaceDelta(kind: .noChange, elementCount: 12, transient: [element])
        let data = try JSONEncoder().encode(delta)
        let decoded = try JSONDecoder().decode(InterfaceDelta.self, from: data)
        XCTAssertEqual(decoded.transient?.count, 1)
        XCTAssertEqual(decoded.transient?.first?.label, "Processing")
    }

    func testOldInterfaceDeltaWithoutTransientDecodes() throws {
        let jsonString = """
        {"kind": "noChange", "elementCount": 5}
        """
        let decoded = try JSONDecoder().decode(InterfaceDelta.self, from: Data(jsonString.utf8))
        XCTAssertNil(decoded.transient)
        XCTAssertEqual(decoded.elementCount, 5)
    }
}
