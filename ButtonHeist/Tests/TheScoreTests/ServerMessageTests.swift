import XCTest
import ThePlans
import TheScore

final class ServerMessageTests: XCTestCase {

    func testInfoEncodeDecode() throws {
        let info = ServerInfo(
            appName: "TestApp",
            bundleIdentifier: "com.test.app",
            deviceName: "iPhone",
            systemVersion: "17.0",
            screenWidth: 390,
            screenHeight: 844,
            instanceId: "test-session",
            instanceIdentifier: "test",
            listeningPort: 49152,
            tlsActive: true
        )
        let message = ServerMessage.info(info)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .info(let decodedInfo) = decoded {
            XCTAssertEqual(decodedInfo.appName, "TestApp")
            XCTAssertEqual(decodedInfo.bundleIdentifier, "com.test.app")
        } else {
            XCTFail("Expected info, got \(decoded)")
        }
    }

    func testStatusEncodeDecode() throws {
        let payload = StatusPayload(
            identity: StatusIdentity(
                appName: "ReachableApp",
                bundleIdentifier: "com.test.reachable",
                appBuild: "42",
                deviceName: "iPhone",
                systemVersion: "18.0",
                buttonHeistVersion: "5.0"
            ),
            session: StatusSession(
                active: true,
                watchersAllowed: false,
                activeConnections: 1
            )
        )
        let message = ServerMessage.status(payload)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .status(let decodedPayload) = decoded {
            XCTAssertEqual(decodedPayload.identity.appName, "ReachableApp")
            XCTAssertEqual(decodedPayload.identity.bundleIdentifier, "com.test.reachable")
            XCTAssertEqual(decodedPayload.session.active, true)
            XCTAssertEqual(decodedPayload.session.activeConnections, 1)
        } else {
            XCTFail("Expected status, got \(decoded)")
        }
    }

    func testInterfaceEncodeDecode() throws {
        let element = HeistElement(
            description: "Button",
            label: "Submit",
            value: nil,
            identifier: "submit_btn",
            frameX: 10, frameY: 20, frameWidth: 100, frameHeight: 44,
            actions: [.activate]
        )
        let payload = makeTestInterface(elements: [element], timestamp: Date())
        let message = ServerMessage.interface(payload)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(message)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ServerMessage.self, from: data)

        if case .interface(let decodedPayload) = decoded {
            XCTAssertEqual(decodedPayload.projectedElements.count, 1)
            XCTAssertEqual(decodedPayload.projectedElements[0].label, "Submit")
        } else {
            XCTFail("Expected interface, got \(decoded)")
        }
    }

    func testPongEncodeDecode() throws {
        let payload = PongPayload(
            buttonHeistVersion: "2026.05.22",
            appName: "TestApp",
            bundleIdentifier: "com.test.app",
            appVersion: "1.2.3",
            appBuild: "456",
            serverInstanceIdentifier: "server-1",
            serverTimestampMs: 1_700_000_000_000
        )
        let message = ServerMessage.pong(payload)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .pong(let decodedPayload) = decoded {
            XCTAssertEqual(decodedPayload, payload)
        } else {
            XCTFail("Expected pong, got \(decoded)")
        }
    }

    func testPongRejectsMissingPayload() throws {
        let data = Data(#"{"type":"pong"}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(ServerMessage.self, from: data))
    }

    func testServerMessageRejectsUnknownTopLevelField() throws {
        let data = Data(#"{"type":"serverHello","staleField":"value"}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(ServerMessage.self, from: data)) { error in
            XCTAssertTrue("\(error)".contains("staleField"), "\(error)")
        }
    }

    func testNoPayloadServerMessageRejectsStrayPayload() throws {
        let data = Data(#"{"type":"serverHello","payload":{"junk":true}}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(ServerMessage.self, from: data)) { error in
            XCTAssertTrue("\(error)".contains("serverHello must not include a payload"), "\(error)")
        }
    }

    func testNoPayloadResponseEnvelopeRejectsStrayPayload() throws {
        let data = Data("""
        {"buttonHeistVersion":"\(TheScore.buttonHeistVersion)","type":"serverHello","payload":{"junk":true}}
        """.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(ResponseEnvelope.self, from: data)) { error in
            XCTAssertTrue("\(error)".contains("serverHello must not include a payload"), "\(error)")
        }
    }

    func testResponseEnvelopeRejectsMissingPongPayload() throws {
        let data = Data("""
        {"buttonHeistVersion":"\(TheScore.buttonHeistVersion)","requestId":"ping-1","type":"pong"}
        """.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(ResponseEnvelope.self, from: data))
    }

    func testResponseEnvelopeRejectsClientOnlyMessageTypeAtTypedBoundary() {
        let data = Data("""
        {"buttonHeistVersion":"\(TheScore.buttonHeistVersion)","type":"clientHello"}
        """.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(ResponseEnvelope.self, from: data)) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertEqual(context.debugDescription, "Unsupported server wire message type: clientHello")
        }
    }

    func testErrorEncodeDecode() throws {
        let message = ServerMessage.error(ServerError(kind: .general, message: "Connection failed"))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .error(let serverError) = decoded {
            XCTAssertEqual(serverError.kind, .general)
            XCTAssertEqual(serverError.message, "Connection failed")
        } else {
            XCTFail("Expected error, got \(decoded)")
        }
    }

    func testErrorWireShape() throws {
        let message = ServerMessage.error(ServerError(kind: .general, message: "disk full"))
        let data = try JSONEncoder().encode(message)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "error")
        let payload = try XCTUnwrap(json["payload"] as? [String: Any])
        XCTAssertEqual(payload["kind"] as? String, "general")
        XCTAssertEqual(payload["message"] as? String, "disk full")
    }

    func testErrorDecodesFromExplicitJSON() throws {
        let json = """
        {"type":"error","payload":{"kind":"general","message":"oops"}}
        """
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: Data(json.utf8))
        guard case .error(let serverError) = decoded else {
            XCTFail("Expected error message, got \(decoded)")
            return
        }
        XCTAssertEqual(serverError.kind, .general)
        XCTAssertEqual(serverError.message, "oops")
    }

    // MARK: - ActionResult Tests

    func testActionResultWithValue() throws {
        let result = ActionResult(success: true, method: .typeText, payload: .value("Hello World"))
        let message = ServerMessage.actionResult(result)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .actionResult(let decodedResult) = decoded {
            XCTAssertTrue(decodedResult.success)
            XCTAssertEqual(decodedResult.method, .typeText)
            guard case .value(let string) = decodedResult.payload else {
                XCTFail("Expected .value payload")
                return
            }
            XCTAssertEqual(string, "Hello World")
            XCTAssertNil(decodedResult.message)
        } else {
            XCTFail("Expected actionResult, got \(decoded)")
        }
    }

    func testActionResultWithoutValue() throws {
        let result = ActionResult(success: true, method: .syntheticTap)
        let message = ServerMessage.actionResult(result)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .actionResult(let decodedResult) = decoded {
            XCTAssertTrue(decodedResult.success)
            XCTAssertEqual(decodedResult.method, .syntheticTap)
            XCTAssertNil(decodedResult.payload)
        } else {
            XCTFail("Expected actionResult, got \(decoded)")
        }
    }

    func testActionResultPayloadValueWireShape() throws {
        let result = ActionResult(success: true, method: .typeText, payload: .value("Hi"))
        let data = try JSONEncoder().encode(result)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let payload = try XCTUnwrap(json["payload"] as? [String: Any])
        XCTAssertEqual(payload["kind"] as? String, "value")
        XCTAssertEqual(payload["data"] as? String, "Hi")
    }

    func testActionResultPayloadScreenshotWireShape() throws {
        let screen = ScreenPayload(
            pngData: "png",
            width: 390,
            height: 844,
            timestamp: Date(timeIntervalSince1970: 0),
            interface: Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
        )
        let result = ActionResult(success: true, method: .takeScreenshot, payload: .screenshot(screen))

        let data = try JSONEncoder().encode(result)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let payload = try XCTUnwrap(json["payload"] as? [String: Any])
        XCTAssertEqual(payload["kind"] as? String, "screenshot")
        let inner = try XCTUnwrap(payload["data"] as? [String: Any])
        XCTAssertEqual(inner["pngData"] as? String, "png")
        XCTAssertEqual(inner["width"] as? Double, 390)
        XCTAssertEqual(inner["height"] as? Double, 844)
        XCTAssertNotNil(inner["interface"])

        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)
        XCTAssertEqual(decoded.payload, .screenshot(screen))
    }

    func testActionResultSubjectEvidenceWireShape() throws {
        let target = ElementTarget.predicate(ElementPredicate(label: "Delete", traits: [.button]))
        let element = HeistElement(
            description: "Delete",
            label: "Delete",
            value: nil,
            identifier: "delete_button",
            traits: [.button],
            frameX: 10,
            frameY: 20,
            frameWidth: 100,
            frameHeight: 44,
            actions: [.activate]
        )
        let evidence = ActionSubjectEvidence(
            source: .resolvedSemanticTarget,
            target: target,
            element: element,
            settledObservationSequence: 12
        )
        let result = ActionResult(success: true, method: .activate, subjectEvidence: evidence)

        let data = try JSONEncoder().encode(result)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let subjectEvidence = try XCTUnwrap(json["subjectEvidence"] as? [String: Any])
        XCTAssertEqual(subjectEvidence["source"] as? String, "resolvedSemanticTarget")
        XCTAssertEqual(subjectEvidence["phase"] as? String, "resolvedBeforeDispatch")
        XCTAssertEqual(subjectEvidence["settledObservationSequence"] as? Int, 12)
        let encodedTarget = try XCTUnwrap(subjectEvidence["target"] as? [String: Any])
        let checks = try XCTUnwrap(encodedTarget["checks"] as? [[String: Any]])
        XCTAssertEqual(checks.count, 2)
        XCTAssertEqual(checks[0]["kind"] as? String, "label")
        XCTAssertEqual(checks[0]["match"] as? String, "Delete")
        XCTAssertEqual(checks[1]["kind"] as? String, "traits")
        XCTAssertEqual(checks[1]["values"] as? [String], ["button"])
        let encodedElement = try XCTUnwrap(subjectEvidence["element"] as? [String: Any])
        XCTAssertEqual(encodedElement["identifier"] as? String, "delete_button")
        XCTAssertNil(encodedElement["heistId"], "subject evidence must not expose runtime ids")

        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)
        XCTAssertEqual(decoded.subjectEvidence, evidence)
    }

    func testActionSubjectEvidenceRejectsUnknownFields() throws {
        let json = Data("""
        {
          "source": "resolvedSemanticTarget",
          "phase": "resolvedBeforeDispatch",
          "target": { "label": "Delete" },
          "element": {
            "description": "Delete",
            "label": "Delete",
            "traits": ["button"],
            "frameX": 0,
            "frameY": 0,
            "frameWidth": 100,
            "frameHeight": 44,
            "activationPointX": 50,
            "activationPointY": 22,
            "respondsToUserInteraction": true,
            "actions": ["activate"]
          },
          "heistId": "old-runtime-id"
        }
        """.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(ActionSubjectEvidence.self, from: json)) { error in
            XCTAssertTrue("\(error)".contains("Unknown ActionSubjectEvidence field"))
        }
    }

    func testActionResultPayloadRotorWireShape() throws {
        let rotor = RotorResult(
            rotor: "Errors",
            direction: .next,
            foundElement: HeistElement(
                description: "Email", label: "Email", value: nil, identifier: nil,
                frameX: 0, frameY: 0, frameWidth: 0, frameHeight: 0, actions: []
            ),
            textRange: RotorTextRange(text: "@maria", startOffset: 10, endOffset: 16, rangeDescription: "[10..<16]")
        )
        let result = ActionResult(success: true, method: .rotor, payload: .rotor(rotor))
        let data = try JSONEncoder().encode(result)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let payload = try XCTUnwrap(json["payload"] as? [String: Any])
        XCTAssertEqual(payload["kind"] as? String, "rotor")
        let inner = try XCTUnwrap(payload["data"] as? [String: Any])
        XCTAssertEqual(inner["rotor"] as? String, "Errors")
        XCTAssertEqual(inner["direction"] as? String, "next")
        let foundElement = try XCTUnwrap(inner["foundElement"] as? [String: Any])
        XCTAssertEqual(foundElement["label"] as? String, "Email")
        XCTAssertNil(foundElement["heistId"], "heistId must never appear on the wire")
        let textRange = try XCTUnwrap(inner["textRange"] as? [String: Any])
        XCTAssertEqual(textRange["text"] as? String, "@maria")
        XCTAssertEqual(textRange["startOffset"] as? Int, 10)
        XCTAssertEqual(textRange["endOffset"] as? Int, 16)
        XCTAssertEqual(textRange["rangeDescription"] as? String, "[10..<16]")
    }

    func testRotorResultRejectsObsoleteFoundElementSnapshot() throws {
        let json = Data("""
        {"rotor":"Errors","direction":"next","foundElement":{"heistId":"old"}}
        """.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(RotorResult.self, from: json))
    }

    func testActionResultAccessibilityTraceWireShape() throws {
        let interface = makeTestInterface(
            elements: [
                HeistElement(
                    description: "Submit",
                    label: "Submit",
                    value: nil,
                    identifier: "submit_button",
                    traits: [.button],
                    frameX: 10,
                    frameY: 20,
                    frameWidth: 100,
                    frameHeight: 44,
                    actions: [.activate]
                ),
            ]
        )
        let trace = AccessibilityTrace(first: interface).appending(interface)
        let result = ActionResult(
            success: true,
            method: .activate,
            accessibilityTrace: trace
        )

        let data = try JSONEncoder().encode(result)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNotNil(json["accessibilityTrace"])
    }

    func testActionResultHasNoTraceProjectionWithoutTrace() throws {
        let result = ActionResult(
            success: true,
            method: .activate
        )

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)

        XCTAssertNil(decoded.accessibilityTrace?.endpointDelta)
    }

    func testActionResultScreenContextProjectsFromTrace() throws {
        let before = interfaceWithHeader("Before")
        let after = interfaceWithHeader("Trace Screen", timestamp: 1)
        let trace = AccessibilityTrace(first: before).appending(
            after,
            context: AccessibilityTrace.Context(screenId: "trace_screen")
        )

        let result = ActionResult(
            success: true,
            method: .activate,
            accessibilityTrace: trace
        )

        XCTAssertEqual(result.accessibilityTrace?.endpointScreenName, "Trace Screen")
        XCTAssertEqual(result.accessibilityTrace?.endpointScreenId, "trace_screen")
    }

    func testActionResultScreenContextRoundTripsTraceProjection() throws {
        let before = interfaceWithHeader("Before")
        let after = interfaceWithHeader("Trace Screen", timestamp: 1)
        let trace = AccessibilityTrace(first: before).appending(
            after,
            context: AccessibilityTrace.Context(screenId: "trace_screen")
        )
        let result = ActionResult(
            success: true,
            method: .activate,
            accessibilityTrace: trace
        )

        let data = try JSONEncoder().encode(result)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)

        XCTAssertNil(json["screenName"])
        XCTAssertNil(json["screenId"])
        XCTAssertEqual(decoded.accessibilityTrace?.endpointScreenName, "Trace Screen")
        XCTAssertEqual(decoded.accessibilityTrace?.endpointScreenId, "trace_screen")
    }

    func testActionResultScreenContextDoesNotFallbackWhenTraceProjectsNil() throws {
        let before = interfaceWithHeader("Before")
        let trace = AccessibilityTrace(first: before).appending(interfaceWithoutHeader(timestamp: 1))
        let result = ActionResult(
            success: true,
            method: .activate,
            accessibilityTrace: trace
        )

        XCTAssertNil(result.accessibilityTrace?.endpointScreenName)
        XCTAssertNil(result.accessibilityTrace?.endpointScreenId)
    }

    func testActionResultDecodedScreenContextProjectsFromTrace() throws {
        let before = interfaceWithHeader("Before")
        let after = interfaceWithHeader("Trace Screen", timestamp: 1)
        let trace = AccessibilityTrace(first: before).appending(
            after,
            context: AccessibilityTrace.Context(screenId: "trace_screen")
        )
        let data = try JSONEncoder().encode(StoredActionResultScreenContextFixture(accessibilityTrace: trace))

        let result = try JSONDecoder().decode(ActionResult.self, from: data)

        XCTAssertEqual(result.accessibilityTrace?.endpointScreenName, "Trace Screen")
        XCTAssertEqual(result.accessibilityTrace?.endpointScreenId, "trace_screen")
    }

    func testActionResultRejectsStoredScreenContextFields() {
        let data = Data(#"{"success":true,"method":"activate","screenName":"stored screen"}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(ActionResult.self, from: data)) { error in
            XCTAssertTrue("\(error)".contains("screenName"), "\(error)")
        }
    }

    func testActionResultPayloadDecodesFromExplicitJSON() throws {
        let json = """
        {"type":"actionResult","payload":{"success":true,"method":"typeText","payload":{"kind":"value","data":"Hello"}}}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)
        guard case .actionResult(let result) = decoded,
              case .value(let string) = result.payload else {
            XCTFail("Expected actionResult with .value payload, got \(decoded)")
            return
        }
        XCTAssertEqual(string, "Hello")
    }

    func testActionResultWithoutOptionalFieldsFromExplicitJSON() throws {
        let json = """
        {"type":"actionResult","payload":{"success":true,"method":"syntheticTap"}}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .actionResult(let result) = decoded {
            XCTAssertTrue(result.success)
            XCTAssertEqual(result.method, .syntheticTap)
            XCTAssertNil(result.payload)
            XCTAssertNil(result.message)
        } else {
            XCTFail("Expected actionResult, got \(decoded)")
        }
    }

    func testActionResultWithErrorKind() throws {
        let result = ActionResult(
            success: false,
            method: .syntheticTap,
            message: "Element not found",
            errorKind: .elementNotFound
        )
        let message = ServerMessage.actionResult(result)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .actionResult(let decodedResult) = decoded {
            XCTAssertFalse(decodedResult.success)
            XCTAssertEqual(decodedResult.errorKind, .elementNotFound)
            XCTAssertEqual(decodedResult.message, "Element not found")
        } else {
            XCTFail("Expected actionResult, got \(decoded)")
        }
    }

    func testErrorKindAllCasesRoundTrip() throws {
        for kind in ErrorKind.allCases {
            let result = ActionResult(success: false, method: .syntheticTap, errorKind: kind)
            let data = try JSONEncoder().encode(result)
            let decoded = try JSONDecoder().decode(ActionResult.self, from: data)
            XCTAssertEqual(decoded.errorKind, kind, "Round-trip failed for \(kind)")
        }
    }

    func testActionResultWithoutErrorKindDecodesAsNil() throws {
        let json = """
        {"type":"actionResult","payload":{"success":false,"method":"syntheticTap","message":"fail"}}
        """
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: Data(json.utf8))

        if case .actionResult(let result) = decoded {
            XCTAssertFalse(result.success)
            XCTAssertNil(result.errorKind)
        } else {
            XCTFail("Expected actionResult, got \(decoded)")
        }
    }

    func testScreenEncodeDecode() throws {
        let element = HeistElement(
            description: "Pay",
            label: "Pay",
            value: nil,
            identifier: "pay_button",
            traits: [.button],
            frameX: 20,
            frameY: 700,
            frameWidth: 160,
            frameHeight: 48,
            activationPointX: 100,
            activationPointY: 724,
            actions: [.activate]
        )
        let payload = ScreenPayload(
            pngData: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==",
            width: 390,
            height: 844,
            interface: makeTestInterface(elements: [element], timestamp: Date(timeIntervalSince1970: 42))
        )
        let message = ServerMessage.screen(payload)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(message)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ServerMessage.self, from: data)

        if case .screen(let decodedPayload) = decoded {
            XCTAssertEqual(decodedPayload.pngData, payload.pngData)
            XCTAssertEqual(decodedPayload.width, 390)
            XCTAssertEqual(decodedPayload.height, 844)
            XCTAssertEqual(decodedPayload.interface?.projectedElements, [element])
            XCTAssertEqual(decodedPayload.interface?.projectedElements.first?.frameX, 20)
            XCTAssertEqual(decodedPayload.interface?.projectedElements.first?.activationPointX, 100)
        } else {
            XCTFail("Expected screen, got \(decoded)")
        }
    }

    private struct StoredActionResultScreenContextFixture: Encodable {
        let success = true
        let method = ActionMethod.activate
        let accessibilityTrace: AccessibilityTrace
    }

    private func interfaceWithHeader(
        _ label: String,
        timestamp: TimeInterval = 0
    ) -> Interface {
        makeTestInterface(
            elements: [
                HeistElement(
                    description: label,
                    label: label,
                    value: nil,
                    identifier: nil,
                    traits: [.header],
                    frameX: 0,
                    frameY: 0,
                    frameWidth: 100,
                    frameHeight: 44,
                    actions: []
                ),
            ],
            timestamp: Date(timeIntervalSince1970: timestamp)
        )
    }

    private func interfaceWithoutHeader(timestamp: TimeInterval = 0) -> Interface {
        makeTestInterface(
            elements: [
                HeistElement(
                    description: "Continue",
                    label: "Continue",
                    value: nil,
                    identifier: nil,
                    traits: [.button],
                    frameX: 0,
                    frameY: 0,
                    frameWidth: 100,
                    frameHeight: 44,
                    actions: []
                ),
            ],
            timestamp: Date(timeIntervalSince1970: timestamp)
        )
    }
}
