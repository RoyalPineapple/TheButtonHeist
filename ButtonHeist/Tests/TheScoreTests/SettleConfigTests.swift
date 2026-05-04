import XCTest
@testable import TheScore

/// Wire-shape and precedence tests for `SettleConfig` and the auto-settle
/// fields layered onto `RequestEnvelope`, `AuthenticatePayload`, and
/// `ActionResult`.
final class SettleConfigTests: XCTestCase {

    // MARK: - SettleConfig Round Trip

    func testSettleConfigDefaultsRoundTrip() throws {
        let config = SettleConfig()
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(SettleConfig.self, from: data)
        XCTAssertEqual(decoded, config)
        XCTAssertEqual(decoded.cycles, 3)
        XCTAssertEqual(decoded.timeoutMs, 10_000)
    }

    func testSettleConfigExplicitValuesRoundTrip() throws {
        let config = SettleConfig(cycles: 5, timeoutMs: 15_000)
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(SettleConfig.self, from: data)
        XCTAssertEqual(decoded, config)
    }

    func testSettleConfigEquatable() {
        XCTAssertEqual(SettleConfig(cycles: 3, timeoutMs: 10_000), SettleConfig())
        XCTAssertNotEqual(SettleConfig(cycles: 3, timeoutMs: 10_000),
                          SettleConfig(cycles: 4, timeoutMs: 10_000))
    }

    // MARK: - SettleConfig.resolve precedence

    func testResolvePerActionWinsOverSession() {
        let perAction = SettleConfig(cycles: 1, timeoutMs: 500)
        let session = SettleConfig(cycles: 5, timeoutMs: 30_000)
        let effective = SettleConfig.resolve(perAction: perAction, session: session)
        XCTAssertEqual(effective, perAction)
    }

    func testResolveSessionWinsOverDefaults() {
        let session = SettleConfig(cycles: 7, timeoutMs: 20_000)
        let effective = SettleConfig.resolve(perAction: nil, session: session)
        XCTAssertEqual(effective, session)
    }

    func testResolveDefaultsWhenBothNil() {
        let effective = SettleConfig.resolve(perAction: nil, session: nil)
        XCTAssertEqual(effective, .builtInDefaults)
        XCTAssertEqual(effective.cycles, 3)
        XCTAssertEqual(effective.timeoutMs, 10_000)
    }

    // MARK: - RequestEnvelope.settleOverride

    func testRequestEnvelopeWithoutOverrideRoundTrip() throws {
        let envelope = RequestEnvelope(
            requestId: "req-123",
            message: .requestInterface
        )
        let data = try JSONEncoder().encode(envelope)
        let decoded = try RequestEnvelope.decoded(from: data)
        XCTAssertNil(decoded.settleOverride)
        XCTAssertEqual(decoded.requestId, "req-123")
    }

    func testRequestEnvelopeWithOverrideRoundTrip() throws {
        let override = SettleConfig(cycles: 1, timeoutMs: 200)
        let envelope = RequestEnvelope(
            requestId: "req-456",
            message: .requestInterface,
            settleOverride: override
        )
        let data = try JSONEncoder().encode(envelope)
        let decoded = try RequestEnvelope.decoded(from: data)
        XCTAssertEqual(decoded.settleOverride, override)
    }

    func testOldEnvelopeWithoutSettleOverrideStillDecodes() throws {
        // Simulate a payload sent by an old client that has no knowledge of
        // settleOverride. The new decoder must accept it.
        let json = """
        {
            "protocolVersion": "8.0",
            "requestId": "legacy",
            "type": "requestInterface"
        }
        """.data(using: .utf8)!
        let decoded = try RequestEnvelope.decoded(from: json)
        XCTAssertNil(decoded.settleOverride)
        XCTAssertEqual(decoded.requestId, "legacy")
    }

    // MARK: - AuthenticatePayload.settleConfig

    func testAuthenticatePayloadWithoutSettleConfigRoundTrip() throws {
        let payload = AuthenticatePayload(token: "tok", driverId: "driver-1")
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(AuthenticatePayload.self, from: data)
        XCTAssertNil(decoded.settleConfig)
        XCTAssertEqual(decoded.token, "tok")
        XCTAssertEqual(decoded.driverId, "driver-1")
    }

    func testAuthenticatePayloadWithSettleConfigRoundTrip() throws {
        let config = SettleConfig(cycles: 2, timeoutMs: 5_000)
        let payload = AuthenticatePayload(token: "tok", driverId: nil, settleConfig: config)
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(AuthenticatePayload.self, from: data)
        XCTAssertEqual(decoded.settleConfig, config)
    }

    func testOldAuthenticatePayloadWithoutSettleConfigDecodes() throws {
        let json = """
        {
            "token": "legacy-token",
            "driverId": "legacy-driver"
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AuthenticatePayload.self, from: json)
        XCTAssertNil(decoded.settleConfig)
        XCTAssertEqual(decoded.token, "legacy-token")
    }

    // MARK: - ActionResult.settled / settleTimeMs

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
        // An action result encoded before auto-settle landed has no
        // `settled` or `settleTimeMs`. New decoder must accept it.
        let json = """
        {
            "success": true,
            "method": "activate"
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ActionResult.self, from: json)
        XCTAssertNil(decoded.settled)
        XCTAssertNil(decoded.settleTimeMs)
    }
}
