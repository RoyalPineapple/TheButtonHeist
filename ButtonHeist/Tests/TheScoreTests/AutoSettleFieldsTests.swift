import XCTest
@testable import TheScore

/// Wire-shape tests for the two additive auto-settle fields:
/// `ActionResult.settled` / `settleTimeMs` and
/// `AccessibilityTrace.Delta.transient`. Old payloads without these fields decode
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

    // MARK: - AccessibilityTrace.Delta.transient

    func testAccessibilityTraceDeltaRoundTripsWithTransient() throws {
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
        let delta: AccessibilityTrace.Delta = .noChange(.init(elementCount: 12, transient: [element]))
        let data = try JSONEncoder().encode(delta)
        let decoded = try JSONDecoder().decode(AccessibilityTrace.Delta.self, from: data)
        XCTAssertEqual(decoded.transient.count, 1)
        XCTAssertEqual(decoded.transient.first?.label, "Processing")
    }

    func testAccessibilityTraceDeltaWithoutTransientDecodesAsEmpty() throws {
        let jsonString = """
        {"kind": "noChange", "elementCount": 5}
        """
        let decoded = try JSONDecoder().decode(AccessibilityTrace.Delta.self, from: Data(jsonString.utf8))
        XCTAssertTrue(decoded.transient.isEmpty)
        XCTAssertEqual(decoded.elementCount, 5)
    }

    // MARK: - New-payload to Old-decoder

    /// A stand-in for an "older client" that decodes only the fields it
    /// knows about. Locks the contract that adding `settled` /
    /// `settleTimeMs` / `transient` to the wire is non-breaking — the
    /// older shape continues to deserialize cleanly when the encoder
    /// emits the new fields.
    private struct LegacyActionResult: Decodable {
        let success: Bool
        let method: ActionMethod
        let message: String?
    }

    private struct LegacyAccessibilityDelta: Decodable {
        let kind: String
        let elementCount: Int
    }

    func testNewActionResultPayloadDecodesIntoLegacyShape() throws {
        let result = ActionResult(
            success: true,
            method: .activate,
            message: "tap",
            settled: true,
            settleTimeMs: 312
        )
        let data = try JSONEncoder().encode(result)
        let legacy = try JSONDecoder().decode(LegacyActionResult.self, from: data)
        XCTAssertTrue(legacy.success)
        XCTAssertEqual(legacy.method, .activate)
        XCTAssertEqual(legacy.message, "tap")
    }

    func testNewAccessibilityTraceDeltaPayloadDecodesIntoLegacyShape() throws {
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
        let delta: AccessibilityTrace.Delta = .noChange(.init(elementCount: 7, transient: [element]))
        let data = try JSONEncoder().encode(delta)
        let legacy = try JSONDecoder().decode(LegacyAccessibilityDelta.self, from: data)
        XCTAssertEqual(legacy.kind, "noChange")
        XCTAssertEqual(legacy.elementCount, 7)
    }
}
