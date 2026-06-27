import XCTest
@testable import TheScore

/// Wire-shape tests for the current auto-settle fields:
/// `ActionResult.settled` / `settleTimeMs` and
/// transient elements on the no-change delta payload.
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

    func testFailedActionResultRoundTripsWithSettleFields() throws {
        let result = ActionResult(
            success: false,
            method: .wait,
            message: "timed out",
            errorKind: .timeout,
            settled: false,
            settleTimeMs: 750
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)
        XCTAssertFalse(decoded.success)
        XCTAssertEqual(decoded.errorKind, .timeout)
        XCTAssertEqual(decoded.settled, false)
        XCTAssertEqual(decoded.settleTimeMs, 750)
    }

    // MARK: - Delta transient payload

    func testAccessibilityTraceDeltaRoundTripsWithTransient() throws {
        let element = HeistElement(
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
        guard case .noChange(let payload) = decoded else {
            return XCTFail("Expected noChange, got \(decoded)")
        }
        XCTAssertEqual(payload.transient.count, 1)
        XCTAssertEqual(payload.transient.first?.label, "Processing")
    }

}
