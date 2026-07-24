import ButtonHeistTestSupport
import XCTest
@testable import TheScore

final class MainThreadProbeWireTests: XCTestCase {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func testClientMessageRoundTripUsesCanonicalProbeTagAndPayload() throws {
        let request = try XCTUnwrap(MainThreadProbeRequest.admit(
            responsivenessTimeoutMilliseconds: 250,
            workTimeoutMilliseconds: 1_000
        ))
        let data = try encoder.encode(ClientMessage.mainThreadProbe(request))
        let json = try JSONProbe(data: data)

        XCTAssertEqual(try json.string("type"), "mainThreadProbe")
        let payload = try json.object("payload")
        XCTAssertEqual(try payload.int("responsivenessTimeoutMilliseconds"), 250)
        XCTAssertEqual(try payload.int("workTimeoutMilliseconds"), 1_000)

        guard case .mainThreadProbe(let decoded) = try decoder.decode(ClientMessage.self, from: data) else {
            return XCTFail("Expected mainThreadProbe")
        }
        XCTAssertEqual(decoded, request)
    }

    func testServerMessageRoundTripsEveryProbeOutcome() throws {
        for outcome in MainThreadProbeOutcome.allCases {
            let data = try encoder.encode(ServerMessage.mainThreadProbe(.init(outcome: outcome)))
            let json = try JSONProbe(data: data)

            XCTAssertEqual(try json.string("type"), "mainThreadProbe")
            XCTAssertEqual(try json.object("payload").string("outcome"), outcome.rawValue)

            guard case .mainThreadProbe(let response) = try decoder.decode(ServerMessage.self, from: data) else {
                return XCTFail("Expected mainThreadProbe")
            }
            XCTAssertEqual(response.outcome, outcome)
        }
    }

    func testProbeRequestRejectsNonpositiveTimeoutAtWireBoundary() {
        let data = Data("""
        {
          "type": "mainThreadProbe",
          "payload": {
            "responsivenessTimeoutMilliseconds": 0,
            "workTimeoutMilliseconds": 1000
          }
        }
        """.utf8)

        XCTAssertThrowsError(try decoder.decode(ClientMessage.self, from: data)) { error in
            XCTAssertTrue("\(error)".contains("positive millisecond durations"), "\(error)")
        }
    }

    func testProbePayloadsRejectUnknownFields() {
        let request = Data("""
        {
          "type": "mainThreadProbe",
          "payload": {
            "responsivenessTimeoutMilliseconds": 250,
            "workTimeoutMilliseconds": 1000,
            "legacyTimeout": 100
          }
        }
        """.utf8)
        let response = Data("""
        {
          "type": "mainThreadProbe",
          "payload": {
            "outcome": "responsive",
            "legacyStatus": "ok"
          }
        }
        """.utf8)

        XCTAssertThrowsError(try decoder.decode(ClientMessage.self, from: request))
        XCTAssertThrowsError(try decoder.decode(ServerMessage.self, from: response))
    }
}
