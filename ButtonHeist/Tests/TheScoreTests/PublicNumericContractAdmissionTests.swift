import Foundation
import XCTest
@testable import TheScore

final class PublicNumericContractAdmissionTests: XCTestCase {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func testSessionLockedPayloadAdmissionAndRoundTrip() throws {
        XCTAssertNil(SessionLockedPayload.admit(message: "Locked", activeConnections: -1))
        XCTAssertNil(SessionLockedPayload.admit(message: "Locked", activeConnections: 2))

        for activeConnections in 0...1 {
            let payload = try XCTUnwrap(SessionLockedPayload.admit(
                message: "Locked",
                activeConnections: activeConnections
            ))
            let decoded = try decoder.decode(SessionLockedPayload.self, from: encoder.encode(payload))

            XCTAssertEqual(decoded.message, payload.message)
            XCTAssertEqual(decoded.activeConnections, activeConnections)
        }
    }

    func testSessionLockedPayloadRejectsMalformedWireValuesAndUnknownFields() {
        let invalidPayloads = [
            #"{"message":"Locked","activeConnections":-1}"#,
            #"{"message":"Locked","activeConnections":2}"#,
            #"{"message":"Locked","activeConnections":1,"watchers":0}"#,
        ]

        for payload in invalidPayloads {
            XCTAssertThrowsError(try decoder.decode(SessionLockedPayload.self, from: Data(payload.utf8)))
        }
    }

    func testStatusSessionAdmissionAndRoundTrip() throws {
        let driverID: DriverID = "driver-a"
        let admittedStates: [(active: Bool, connections: Int, driverID: DriverID?)] = [
            (false, 0, nil),
            (true, 0, nil),
            (true, 1, driverID),
        ]

        for state in admittedStates {
            let session = try XCTUnwrap(StatusSession.admit(
                active: state.active,
                watchersAllowed: false,
                activeConnections: state.connections,
                activeDriverId: state.driverID
            ))
            let decoded = try decoder.decode(StatusSession.self, from: encoder.encode(session))

            XCTAssertEqual(decoded.active, state.active)
            XCTAssertFalse(decoded.watchersAllowed)
            XCTAssertEqual(decoded.activeConnections, state.connections)
            XCTAssertEqual(decoded.activeDriverId, state.driverID)
        }
    }

    func testStatusSessionAdmissionRejectsInvalidRelationships() {
        XCTAssertNil(StatusSession.admit(active: true, watchersAllowed: true, activeConnections: 1))
        XCTAssertNil(StatusSession.admit(active: true, watchersAllowed: false, activeConnections: -1))
        XCTAssertNil(StatusSession.admit(active: true, watchersAllowed: false, activeConnections: 2))
        XCTAssertNil(StatusSession.admit(active: false, watchersAllowed: false, activeConnections: 1))
        XCTAssertNil(StatusSession.admit(
            active: false,
            watchersAllowed: false,
            activeConnections: 0,
            activeDriverId: "driver-a"
        ))
    }

    func testStatusSessionRejectsMalformedWireValuesAndUnknownFields() {
        let invalidPayloads = [
            #"{"active":true,"watchersAllowed":true,"activeConnections":1}"#,
            #"{"active":true,"watchersAllowed":false,"activeConnections":-1}"#,
            #"{"active":true,"watchersAllowed":false,"activeConnections":2}"#,
            #"{"active":false,"watchersAllowed":false,"activeConnections":1}"#,
            #"{"active":false,"watchersAllowed":false,"activeConnections":0,"activeDriverId":"driver-a"}"#,
            #"{"active":false,"watchersAllowed":false,"activeConnections":0,"watchers":0}"#,
        ]

        for payload in invalidPayloads {
            XCTAssertThrowsError(try decoder.decode(StatusSession.self, from: Data(payload.utf8)))
        }
    }

    func testElementPropertyFrameAdmissionAndRoundTrip() throws {
        XCTAssertNil(ElementPropertyFrame.admit(x: 0, y: 0, width: -1, height: 10))
        XCTAssertNil(ElementPropertyFrame.admit(x: 0, y: 0, width: 10, height: -1))

        let frame = try XCTUnwrap(ElementPropertyFrame.admit(x: -10, y: -20, width: 0, height: 44))
        let decoded = try decoder.decode(ElementPropertyFrame.self, from: encoder.encode(frame))

        XCTAssertEqual(decoded, frame)
    }

    func testElementPropertyFrameRejectsMalformedWireValuesAndUnknownFields() {
        let invalidFrames = [
            #"{"x":0,"y":0,"width":-1,"height":10}"#,
            #"{"x":0,"y":0,"width":10,"height":-1}"#,
            #"{"x":0,"y":0,"width":10,"height":10,"scale":2}"#,
        ]

        for frame in invalidFrames {
            XCTAssertThrowsError(try decoder.decode(ElementPropertyFrame.self, from: Data(frame.utf8)))
        }
    }
}
